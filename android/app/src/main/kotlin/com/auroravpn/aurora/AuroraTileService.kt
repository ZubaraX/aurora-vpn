package com.auroravpn.aurora

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

internal object AuroraTileState {
    private const val PREFS = "aurora_native"
    private const val CONFIG = "last_vpn_config"
    private const val STATUS = "vpn_status"

    fun saveConfig(context: Context, config: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(CONFIG, config)
            .apply()
    }

    fun lastConfig(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(CONFIG, null)

    fun status(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(STATUS, "disconnected") ?: "disconnected"

    fun updateStatus(context: Context, status: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(STATUS, status.substringBefore(':'))
            .apply()
        try {
            TileService.requestListeningState(
                context,
                ComponentName(context, AuroraTileService::class.java)
            )
        } catch (_: Throwable) {}
    }
}

/**
 * Quick Settings toggle for the last successfully configured Aurora tunnel.
 *
 * Android does not let apps silently place a tile. The Settings screen uses
 * requestAddTileService() on Android 13+, while older versions expose this
 * service in the system tile editor.
 */
class AuroraTileService : TileService() {

    companion object {
        const val ACTION_TILE_CONNECT = "com.auroravpn.aurora.TILE_CONNECT"
        private const val ACTIVITY_REQUEST = 0xA012
    }

    override fun onStartListening() {
        super.onStartListening()
        // A freshly created process cannot have a live in-process VPN service.
        // Clear a persisted active state left by an abrupt process kill.
        if (!AuroraVpnService.isTunnelActive() &&
            AuroraTileState.status(this) in setOf("connecting", "connected")
        ) {
            AuroraTileState.updateStatus(this, "disconnected")
        }
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val action = Runnable { toggleTunnel() }
        if (isLocked) unlockAndRun(action) else action.run()
    }

    private fun toggleTunnel() {
        if (AuroraVpnService.isTunnelActive()) {
            AuroraTileState.updateStatus(this, "disconnecting")
            startService(Intent(this, AuroraVpnService::class.java).apply {
                action = AuroraVpnService.ACTION_STOP
            })
            updateTile()
            return
        }

        val config = AuroraTileState.lastConfig(this)
        if (config.isNullOrBlank() || VpnService.prepare(this) != null) {
            openAurora(connect = !config.isNullOrBlank())
            return
        }

        AuroraTileState.updateStatus(this, "connecting")
        val service = Intent(this, AuroraVpnService::class.java).apply {
            action = AuroraVpnService.ACTION_START
            putExtra(AuroraVpnService.EXTRA_CONFIG, config)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(service)
        } else {
            startService(service)
        }
        updateTile()
    }

    private fun openAurora(connect: Boolean) {
        val intent = Intent(this, MainActivity::class.java).apply {
            if (connect) action = ACTION_TILE_CONNECT
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this,
                ACTIVITY_REQUEST,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val status = AuroraTileState.status(this)
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_aurora)
        tile.label = "Aurora VPN"
        tile.contentDescription = "Aurora VPN"
        tile.state = when (status) {
            "connected" -> Tile.STATE_ACTIVE
            "connecting", "disconnecting" -> Tile.STATE_UNAVAILABLE
            else -> Tile.STATE_INACTIVE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when (status) {
                "connected" -> "Подключено"
                "connecting" -> "Подключение…"
                "disconnecting" -> "Отключение…"
                else -> "Отключено"
            }
        }
        tile.updateTile()
    }
}
