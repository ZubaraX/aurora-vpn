package com.auroravpn.aurora

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.StatusBarManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
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
import android.graphics.drawable.Icon
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
    private val NOTIFICATION_REQUEST = 0x0A13

    private var pendingConfig: String? = null
    private var pendingTitle: String? = null
    private var usageEventsCursor = 0L
    private val foregroundActivities = LinkedHashMap<String, Pair<String, Long>>()

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
        ensureNotificationPermission()
        handleTileIntent(intent)
    }

    /**
     * Asks for POST_NOTIFICATIONS once on Android 13+.
     *
     * The permission was declared in the manifest but never requested, so on
     * Android 13+ it stays denied and the system drops our notifications —
     * which is why the tunnel status and the "update available" message never
     * appeared. Only asked when not already granted; Android itself stops
     * re-prompting once the user has answered, so this never nags.
     */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        try {
            val perm = android.Manifest.permission.POST_NOTIFICATIONS
            if (checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED) return
            requestPermissions(arrayOf(perm), NOTIFICATION_REQUEST)
        } catch (_: Throwable) {}
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
                    pendingTitle = call.argument<String>("title")
                    pendingConfig?.let { AuroraTileState.saveConfig(this, it) }
                    pendingTitle?.let { AuroraTileState.saveTitle(this, it) }
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
                "addQuickTile" -> requestQuickTile(result)
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
                "notifyUpdate" -> {
                    showUpdateNotification(call.argument<String>("version") ?: "")
                    result.success(true)
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
    // Liveness endpoints tried through the proxy outbound, most-reachable first.
    // A single Google URL false-negatives on exits that reach the wider internet
    // but throttle Google or resolve it slowly; Cloudflare's captive-portal probe
    // is plain HTTP and near-universally reachable, so it settles fast.
    private val probeUrls = listOf(
        "http%3A%2F%2Fcp.cloudflare.com%2Fgenerate_204",
        "https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204",
    )

    private fun probeProxy(): Boolean {
        val port = AuroraVpnService.controllerPort()
        if (port <= 0) return false
        // Fast screen so failover stays quick: a working exit answers
        // Cloudflare's captive-portal probe in well under a second. Try
        // Cloudflare, then Google, then a single Cloudflare retry for a cold
        // Reality handshake — each capped at ~2.5s.
        if (delayOk(port, probeUrls[0])) return true
        if (delayOk(port, probeUrls[1])) return true
        try { Thread.sleep(200) } catch (_: InterruptedException) { return false }
        return delayOk(port, probeUrls[0])
    }

    private fun delayOk(port: Int, encodedUrl: String): Boolean {
        val path = "/proxies/proxy/delay?timeout=2000&url=$encodedUrl"
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 1000)
                socket.soTimeout = 2500
                val writer = socket.getOutputStream().bufferedWriter()
                writer.write("GET $path HTTP/1.1\r\n")
                writer.write("Host: 127.0.0.1:$port\r\n")
                writer.write("Connection: close\r\n\r\n")
                writer.flush()
                val status = socket.getInputStream().bufferedReader().readLine()
                status?.contains(" 200 ") == true
            }
        } catch (_: Throwable) {
            false
        }
    }

    /// Posts a shade notification announcing an available update. Tapping it
    /// opens Aurora, where the home-screen banner offers the one-tap update.
    private fun showUpdateNotification(version: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "aurora_update"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        channelId,
                        "Обновления Aurora",
                        NotificationManager.IMPORTANCE_DEFAULT
                    )
                )
            }
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val pending = PendingIntent.getActivity(
                this, 2, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val text = if (version.isNotBlank())
                "Версия $version · нажмите, чтобы обновить"
            else "Нажмите, чтобы обновить"
            val n = Notification.Builder(this, channelId)
                .setContentTitle("Доступно обновление Aurora")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentIntent(pending)
                .setAutoCancel(true)
                .build()
            nm.notify(0xA1, n)
        } catch (_: Throwable) {}
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

    /**
     * The package whose activity is currently in the foreground.
     *
     * Keep a cursor between polls instead of rebuilding state from only the
     * last 30 seconds. A trigger can stay open for hours, and its Wi-Fi/mobile
     * profile must still change when the physical network changes.
     */
    private fun runningPackages(): List<String> {
        if (!hasUsageAccess()) {
            usageEventsCursor = 0L
            foregroundActivities.clear()
            return emptyList()
        }

        val usage = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val begin = if (usageEventsCursor == 0L || usageEventsCursor > now) {
            now - 6L * 60 * 60 * 1000
        } else {
            usageEventsCursor
        }
        val events = usage.queryEvents(begin, now)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            val activityKey = "$packageName:${event.className.orEmpty()}"
            when (event.eventType) {
                // MOVE_TO_FOREGROUND/BACKGROUND use the same values on API
                // 24-28, while these names remain valid on current Android.
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    foregroundActivities[activityKey] = packageName to event.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED -> {
                    foregroundActivities.remove(activityKey)
                }
                UsageEvents.Event.DEVICE_SHUTDOWN,
                UsageEvents.Event.DEVICE_STARTUP -> {
                    foregroundActivities.clear()
                }
            }
            usageEventsCursor = maxOf(usageEventsCursor, event.timeStamp + 1)
        }
        usageEventsCursor = maxOf(usageEventsCursor, now)
        val foregroundPackage = foregroundActivities.values
            .maxByOrNull { it.second }
            ?.first
        return foregroundPackage?.let(::listOf) ?: emptyList()
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
        fun usable(candidate: android.net.Network): Boolean {
            val caps = cm.getNetworkCapabilities(candidate) ?: return false
            return !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        }
        val network = cm.allNetworks
            .filter(::usable)
            .maxByOrNull { candidate ->
                val caps = cm.getNetworkCapabilities(candidate) ?: return@maxByOrNull 0
                var score = 0
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                    score += 100
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED)
                ) {
                    score += 20
                }
                score += when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 12
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 10
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 8
                    else -> 1
                }
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) {
                    score += 2
                }
                // Keep Android's default as a small tie-breaker, but a valid
                // connected Wi-Fi network still wins over cellular.
                if (candidate == active) score += 4
                score
            } ?: return "other"
        val caps = cm.getNetworkCapabilities(network) ?: return "other"
        val type = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "other"
        }
        return type
    }

    private fun launchTunnel() {
        if (pendingConfig.isNullOrBlank()) {
            pendingConfig = AuroraTileState.lastConfig(this)
        }
        val config = pendingConfig ?: return
        AuroraTileState.saveConfig(this, config)
        val intent = Intent(this, AuroraVpnService::class.java)
        intent.action = AuroraVpnService.ACTION_START
        intent.putExtra(AuroraVpnService.EXTRA_CONFIG, config)
        pendingTitle?.let { intent.putExtra(AuroraVpnService.EXTRA_TITLE, it) }
        startService(intent)
    }

    private fun handleTileIntent(intent: Intent?) {
        if (intent?.action != AuroraTileService.ACTION_TILE_CONNECT) return
        pendingConfig = AuroraTileState.lastConfig(this) ?: return
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            startActivityForResult(prepare, VPN_REQUEST)
        } else {
            launchTunnel()
        }
        intent.action = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTileIntent(intent)
    }

    private fun requestQuickTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("manual")
            return
        }
        try {
            val manager = getSystemService(StatusBarManager::class.java)
            manager.requestAddTileService(
                ComponentName(this, AuroraTileService::class.java),
                "Aurora VPN",
                Icon.createWithResource(this, R.drawable.ic_qs_aurora),
                mainExecutor
            ) { code ->
                val value = when (code) {
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "added"
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED ->
                        "already_added"
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED -> "not_added"
                    else -> "error"
                }
                result.success(value)
            }
        } catch (t: Throwable) {
            result.error("quick_tile", t.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST && resultCode == RESULT_OK) launchTunnel()
    }

    /**
     * User-facing apps for per-app routing.
     *
     * Preinstalled apps such as YouTube carry FLAG_SYSTEM even though they are
     * normal launcher apps. Preserve that distinction so Dart can hide actual
     * system services without hiding OEM/Google applications.
     */
    private fun listInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        return apps.mapNotNull { info ->
            val launchable =
                pm.getLaunchIntentForPackage(info.packageName) != null ||
                    pm.getLeanbackLaunchIntentForPackage(info.packageName) != null
            val isSystem = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (!launchable && isSystem) return@mapNotNull null
            mapOf(
                "id" to info.packageName,
                "name" to pm.getApplicationLabel(info).toString(),
                "isSystem" to isSystem,
                "hasLauncher" to launchable
            )
        }
    }
}
