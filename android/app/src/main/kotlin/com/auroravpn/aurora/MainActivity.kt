package com.auroravpn.aurora

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

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
                java.io.File(filesDir, "aurora-crash.log").appendText(
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
                "probe" -> Thread({
                    val reachable = probeProxy()
                    runOnUiThread { result.success(reachable) }
                }, "aurora-probe").start()
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
                "networkType" -> result.success(activeNetworkType())
                "hasTriggerAccess" -> result.success(hasUsageAccess())
                "requestTriggerAccess" -> {
                    requestUsageAccess()
                    result.success(null)
                }
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

        MethodChannel(messenger, "aurora/logs").setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> result.success(readLogs())
                "clear" -> {
                    File(filesDir, "box.log").delete()
                    File(filesDir, "aurora-crash.log").delete()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readLogs(): String {
        val out = StringBuilder()
        val crash = File(filesDir, "aurora-crash.log")
        if (crash.exists() && crash.length() > 0) {
            out.append("═══ CRASH / ERRORS ═══\n")
            out.append(crash.readText().takeLast(20000)).append("\n\n")
        }
        val box = File(filesDir, "box.log")
        if (box.exists() && box.length() > 0) {
            out.append("═══ sing-box core ═══\n")
            out.append(box.readText().takeLast(20000))
        }
        return if (out.isEmpty()) "Логи пока пусты. Нажмите подключение, чтобы записать." else out.toString()
    }

    /**
     * Tests the selected outbound through sing-box's local Clash API. A TCP
     * ping to the server is not enough: expired Reality credentials still
     * accept TCP while every proxied request fails.
     */
    private fun probeProxy(): Boolean {
        val path = "/proxies/proxy/delay" +
            "?timeout=8000" +
            "&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204"
        repeat(3) {
            try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress("127.0.0.1", 9090), 2000)
                    socket.soTimeout = 10000
                    val writer = socket.getOutputStream().bufferedWriter()
                    writer.write("GET $path HTTP/1.1\r\n")
                    writer.write("Host: 127.0.0.1:9090\r\n")
                    writer.write("Connection: close\r\n\r\n")
                    writer.flush()
                    val status = socket.getInputStream().bufferedReader().readLine()
                    if (status?.contains(" 200 ") == true) return true
                }
            } catch (_: Throwable) {}
            try { Thread.sleep(600) } catch (_: InterruptedException) {
                return false
            }
        }
        return false
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

    /** Package names that entered or remain in the foreground recently. */
    private fun runningPackages(): List<String> {
        if (hasUsageAccess()) {
            val usage = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            val events = usage.queryEvents(now - 30_000, now)
            val event = UsageEvents.Event()
            val foreground = LinkedHashMap<String, Boolean>()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val packageName = event.packageName ?: continue
                when (event.eventType) {
                    UsageEvents.Event.ACTIVITY_RESUMED -> foreground[packageName] = true
                    UsageEvents.Event.ACTIVITY_PAUSED,
                    UsageEvents.Event.ACTIVITY_STOPPED -> foreground[packageName] = false
                }
            }
            return foreground.filterValues { it }.keys.toList()
        }

        // Limited fallback for devices where Usage Access has not been
        // granted. Unlike the old installed-app list, this cannot fire every
        // trigger immediately after Aurora starts.
        val activity = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return activity.runningAppProcesses.orEmpty()
            .filter {
                it.importance <=
                    ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE
            }
            .flatMap { it.pkgList?.toList().orEmpty() }
            .distinct()
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageAccess() {
        val intent = Intent(
            Settings.ACTION_USAGE_ACCESS_SETTINGS,
            Uri.parse("package:$packageName")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (_: Throwable) {
            startActivity(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /** Physical upstream type; the VPN transport itself is deliberately ignored. */
    private fun activeNetworkType(): String {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val active = cm.activeNetwork
        val network = if (active != null &&
            cm.getNetworkCapabilities(active)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == false
        ) {
            active
        } else {
            cm.allNetworks.firstOrNull { candidate ->
                val caps = cm.getNetworkCapabilities(candidate) ?: return@firstOrNull false
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            }
        } ?: return "other"
        val caps = cm.getNetworkCapabilities(network) ?: return "other"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "other"
        }
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
