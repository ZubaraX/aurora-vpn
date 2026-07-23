package com.auroravpn.aurora

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.EventChannel

/**
 * The Aurora tunnel service.
 *
 * It owns the Android VPN interface and the sing-box libbox core lifecycle.
 * The Dart side ([AndroidVpnEngine]) generates the full sing-box config
 * (including per-app `include_package` / `exclude_package`) and hands it here;
 * this service raises the TUN, starts the core against it, and streams status
 * and throughput back over the event channels.
 *
 * INTEGRATION: drop the sing-box `libbox` AAR into android/app/libs and start
 * `BoxService` at the marked point, passing this VpnService as the platform
 * interface so libbox can protect sockets and read the tun fd. Everything
 * around that hand-off — consent, foreground notification, channels, teardown —
 * is already wired.
 */
class AuroraVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.auroravpn.aurora.START"
        const val ACTION_STOP = "com.auroravpn.aurora.STOP"
        const val EXTRA_CONFIG = "config"

        private const val CHANNEL_ID = "aurora_vpn"
        private const val NOTIFICATION_ID = 0xA0

        @JvmStatic var statusSink: EventChannel.EventSink? = null
        @JvmStatic var statsSink: EventChannel.EventSink? = null
    }

    private val main = Handler(Looper.getMainLooper())
    private var tun: ParcelFileDescriptor? = null
    private var connectedSince: Long = 0

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startTunnel(intent.getStringExtra(EXTRA_CONFIG))
            ACTION_STOP -> stopTunnel()
        }
        return START_STICKY
    }

    private fun startTunnel(config: String?) {
        emitStatus("connecting")
        try {
            val builder = Builder()
                .setSession("Aurora")
                .setMtu(9000)
                .addAddress("172.19.0.1", 30)
                .addDnsServer("1.1.1.1")
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)
            builder.setBlocking(false)

            tun = builder.establish()
            startForegroundNotification()
            connectedSince = System.currentTimeMillis()

            // ── sing-box libbox hand-off ─────────────────────────────────
            // val options = Libbox.newOptions(config)
            // boxService = Libbox.newService(options, AuroraPlatformInterface(this, tun))
            // boxService.start()
            // ─────────────────────────────────────────────────────────────

            emitStatus("connected")
            startStatsPump()
        } catch (t: Throwable) {
            emitStatus("error")
            stopTunnel()
        }
    }

    private fun stopTunnel() {
        // boxService?.close()
        main.removeCallbacksAndMessages(null)
        tun?.close()
        tun = null
        emitStatus("disconnected")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
        stopSelf()
    }

    /** Emits throughput once a second. With libbox wired, read its counters. */
    private fun startStatsPump() {
        val tick = object : Runnable {
            override fun run() {
                if (tun == null) return
                statsSink?.success(
                    mapOf(
                        "uploadTotal" to 0,
                        "downloadTotal" to 0,
                        "uploadSpeed" to 0,
                        "downloadSpeed" to 0,
                        "connectedSince" to connectedSince
                    )
                )
                main.postDelayed(this, 1000)
            }
        }
        main.postDelayed(tick, 1000)
    }

    private fun startForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Aurora VPN", NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(channel)
        }
        val pending = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val notification: Notification =
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Aurora")
                .setContentText("Туннель активен")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentIntent(pending)
                .setOngoing(true)
                .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun emitStatus(status: String) {
        main.post { statusSink?.success(status) }
    }

    override fun onRevoke() {
        stopTunnel()
        super.onRevoke()
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        tun?.close()
        super.onDestroy()
    }
}
