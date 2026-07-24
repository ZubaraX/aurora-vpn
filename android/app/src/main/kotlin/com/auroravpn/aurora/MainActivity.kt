package com.auroravpn.aurora

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Aurora method/event channels the Dart [AndroidVpnEngine] talks to:
 *
 *  - `aurora/vpn`         start / stop / ping    (control)
 *  - `aurora/vpn/status`  connection status stream
 *  - `aurora/vpn/stats`   throughput stream
 *  - `aurora/apps`        installed-app inventory for per-app routing
 *
 * The VpnService itself ([AuroraVpnService]) is where the bundled sing-box
 * libbox core is driven; this class handles the VPN-consent prompt and wiring.
 */
class MainActivity : FlutterActivity() {

    private val VPN_CHANNEL = "aurora/vpn"
    private val STATUS_CHANNEL = "aurora/vpn/status"
    private val STATS_CHANNEL = "aurora/vpn/stats"
    private val APPS_CHANNEL = "aurora/apps"
    private val VPN_REQUEST = 0x0A11

    private var pendingConfig: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Record any uncaught crash to a readable file so failures on-device can
        // be diagnosed without adb: Android/data/<pkg>/files/aurora-crash.log
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            try {
                val dir = getExternalFilesDir(null) ?: filesDir
                java.io.File(dir, "aurora-crash.log").appendText(
                    "[uncaught ${thread.name}] ${e.javaClass.name}: ${e.message}\n" +
                        e.stackTraceToString() + "\n\n"
                )
            } catch (_: Throwable) {}
            prev?.uncaughtException(thread, e)
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, VPN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> result.success(true)
                "start" -> {
                    pendingConfig = call.argument<String>("config")
                    val prepare = VpnService.prepare(this)
                    if (prepare != null) {
                        startActivityForResult(prepare, VPN_REQUEST)
                    } else {
                        launchTunnel()
                    }
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, AuroraVpnService::class.java)
                    intent.action = AuroraVpnService.ACTION_STOP
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, STATUS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    AuroraVpnService.statusSink = sink
                }
                override fun onCancel(args: Any?) { AuroraVpnService.statusSink = null }
            }
        )

        EventChannel(messenger, STATS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    AuroraVpnService.statsSink = sink
                }
                override fun onCancel(args: Any?) { AuroraVpnService.statsSink = null }
            }
        )

        MethodChannel(messenger, APPS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> result.success(listInstalledApps())
                "running" -> result.success(runningPackages())
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "aurora/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    installApk(call.argument<String>("path")); result.success(true)
                }
                "openUrl" -> {
                    openUrl(call.argument<String>("url")); result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(path: String?) {
        if (path == null) return
        val file = java.io.File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }

    private fun openUrl(url: String?) {
        if (url == null) return
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Package names of currently running / launchable apps (best effort). */
    private fun runningPackages(): List<String> {
        val pm = packageManager
        return pm.getInstalledApplications(0)
            .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
            .map { it.packageName }
    }

    private fun launchTunnel() {
        val intent = Intent(this, AuroraVpnService::class.java)
        intent.action = AuroraVpnService.ACTION_START
        intent.putExtra(AuroraVpnService.EXTRA_CONFIG, pendingConfig)
        startService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST && resultCode == RESULT_OK) launchTunnel()
    }

    /** Launchable apps, for the per-app split-tunnelling screen. */
    private fun listInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        return apps.mapNotNull { info ->
            val launchable = pm.getLaunchIntentForPackage(info.packageName) != null
            val isSystem = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (!launchable && isSystem) return@mapNotNull null
            mapOf(
                "id" to info.packageName,
                "name" to pm.getApplicationLabel(info).toString(),
                "isSystem" to isSystem
            )
        }
    }
}
