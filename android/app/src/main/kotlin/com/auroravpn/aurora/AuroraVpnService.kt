package com.auroravpn.aurora

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.EventChannel
import libbox.CommandServer
import libbox.CommandServerHandler
import libbox.ConnectionOwner
import libbox.InterfaceUpdateListener
import libbox.Libbox
import libbox.LocalDNSTransport
import libbox.OverrideOptions
import libbox.PlatformInterface
import libbox.SetupOptions
import libbox.StringIterator
import libbox.SystemProxyStatus
import libbox.TunOptions
import libbox.WIFIState
import org.json.JSONObject
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import libbox.NetworkInterface as LibboxNetworkInterface
import libbox.NetworkInterfaceIterator as LibboxNetworkInterfaceIterator
import libbox.Notification as LibboxNotification

/**
 * The Aurora tunnel service, now driven by the real sing-box core (libbox).
 *
 * It implements the libbox [PlatformInterface] (openTun builds the Android VPN
 * from sing-box's TunOptions and returns the fd; autoDetectInterfaceControl
 * protects sockets; a ConnectivityManager callback feeds the interface monitor)
 * and [CommandServerHandler], then starts the core via
 * `CommandServer.startOrReloadService(config)`.
 */
class AuroraVpnService : VpnService(), PlatformInterface, CommandServerHandler {

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
    private var commandServer: CommandServer? = null
    private var tun: ParcelFileDescriptor? = null
    private var connectedSince: Long = 0
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var defaultNetwork: Network? = null
    private var statsUploadTotal = 0L
    private var statsDownloadTotal = 0L
    private var statsSampleAt = 0L

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startBox(intent.getStringExtra(EXTRA_CONFIG))
            ACTION_STOP -> stopBox()
        }
        return START_STICKY
    }

    private fun startBox(config: String?) {
        if (config == null) {
            emitStatus("error"); stopSelf(); return
        }
        emitStatus("connecting")
        // Foreground promotion must happen promptly and on the main thread.
        try { startForegroundNotification() } catch (t: Throwable) { logError("fg", t) }

        // The core is heavy (parses config, raises the TUN via openTun) — never
        // run it on the main thread or the app ANRs / is killed on connect.
        Thread({
            try {
                val work = File(filesDir, "work").apply { mkdirs() }
                // Send the core's own logs to a file the in-app Logs screen reads.
                try { Libbox.redirectStderr(File(filesDir, "box.log").absolutePath) } catch (_: Throwable) {}
                Libbox.setup(SetupOptions().apply {
                    basePath = filesDir.absolutePath
                    workingPath = work.absolutePath
                    tempPath = cacheDir.absolutePath
                })
                // OverrideOptions MUST be non-null — the Go side dereferences it
                // unconditionally (nil → native panic → crash on connect).
                val override = OverrideOptions().apply {
                    includePackage = StringList(emptyList())
                    excludePackage = StringList(emptyList())
                }
                val server = CommandServer(this, this)
                server.start()
                // Resolve the log file with Android's actual user/profile
                // directory instead of hard-coding /data/user/0 in Dart.
                val resolvedConfig = JSONObject(config).apply {
                    optJSONObject("log")
                        ?.put("output", File(filesDir, "box.log").absolutePath)
                }.toString()
                server.startOrReloadService(resolvedConfig, override)
                commandServer = server
                connectedSince = System.currentTimeMillis()
                statsUploadTotal = 0
                statsDownloadTotal = 0
                statsSampleAt = 0
                emitStatus("connected")
                main.post { startStatsPump() }
            } catch (t: Throwable) {
                logError("start", t)
                emitStatus("error:" + (t.message ?: "не удалось запустить ядро"))
                main.post { stopBox() }
            }
        }, "aurora-box").start()
    }

    private fun logError(where: String, t: Throwable) {
        try {
            android.util.Log.e("AuroraVPN", "[$where] ${t.message}", t)
            File(filesDir, "aurora-crash.log").appendText(
                "[$where] ${t.javaClass.simpleName}: ${t.message}\n" +
                    t.stackTraceToString() + "\n\n"
            )
        } catch (_: Throwable) {}
    }

    private fun stopBox() {
        emitStatus("disconnecting")
        main.removeCallbacksAndMessages(null)
        try { commandServer?.closeService() } catch (_: Throwable) {}
        try { commandServer?.close() } catch (_: Throwable) {}
        commandServer = null
        networkCallback?.let {
            try {
                (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                    .unregisterNetworkCallback(it)
            } catch (_: Throwable) {}
        }
        networkCallback = null
        defaultNetwork = null
        try { tun?.close() } catch (_: Throwable) {}
        tun = null
        emitStatus("disconnected")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
        stopSelf()
    }

    // --- PlatformInterface ---------------------------------------------------

    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
        builder.setMtu(if (options.mtu in 1..9000) options.mtu else 1500)
        builder.setSession("Aurora")
        builder.setBlocking(false)

        forEachPrefix(options.inet4Address) { builder.addAddress(it.address(), it.prefix()) }
        forEachPrefix(options.inet6Address) { builder.addAddress(it.address(), it.prefix()) }

        if (options.autoRoute) {
            var addedV4 = false
            forEachPrefix(options.inet4RouteAddress) {
                builder.addRoute(it.address(), it.prefix()); addedV4 = true
            }
            if (!addedV4) builder.addRoute("0.0.0.0", 0)
            forEachPrefix(options.inet6RouteAddress) {
                builder.addRoute(it.address(), it.prefix())
            }
        }

        try {
            val dns = options.dnsServerAddress
            if (dns.value.isNotEmpty()) builder.addDnsServer(dns.value)
        } catch (_: Throwable) {}

        var hasInclude = false
        forEachString(options.includePackage) {
            try { builder.addAllowedApplication(it); hasInclude = true } catch (_: Throwable) {}
        }
        if (!hasInclude) {
            forEachString(options.excludePackage) {
                try { builder.addDisallowedApplication(it) } catch (_: Throwable) {}
            }
            // Keep our own traffic (bootstrap DNS, updater) outside the tunnel.
            try { builder.addDisallowedApplication(packageName) } catch (_: Throwable) {}
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val pfd = builder.establish()
            ?: throw IllegalStateException("VpnService.establish() returned null")
        tun = pfd
        return pfd.fd
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun useProcFS(): Boolean = false

    override fun findConnectionOwner(
        ipProto: Int, srcIp: String, srcPort: Int, destIp: String, destPort: Int
    ): ConnectionOwner {
        // Not needed: Android per-app routing uses include/exclude package, not
        // process rules.
        throw UnsupportedOperationException("process lookup unsupported")
    }

    override fun getInterfaces(): LibboxNetworkInterfaceIterator {
        val items = ArrayList<LibboxNetworkInterface>()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        try {
            // libbox needs Android's usable networks, not every kernel
            // interface (loopback, stale TUNs, etc.). In particular, the
            // transport type and DNS servers are used while the core resolves
            // remote rule-sets before the VPN itself exists.
            for (network in cm.allNetworks) {
                val lp = cm.getLinkProperties(network) ?: continue
                val caps = cm.getNetworkCapabilities(network) ?: continue
                // The TUN is an output of libbox, never an upstream network.
                // Feeding it back to auto_detect_interface creates a routing
                // loop where protected proxy sockets are bound to the VPN.
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                val name = lp.interfaceName ?: continue
                val ni = java.net.NetworkInterface.getByName(name) ?: continue
                val item = LibboxNetworkInterface()
                item.name = name
                item.index = ni.index
                item.mtu = try { ni.mtu } catch (_: Throwable) { 0 }
                val addrs = ArrayList<String>()
                for (ia in ni.interfaceAddresses) {
                    val host = ia.address?.hostAddress ?: continue
                    // Java appends an IPv6 scope (for example "%wlan0") to
                    // link-local addresses. netip.ParsePrefix in libbox rejects
                    // zones and panics across the gomobile boundary, killing the
                    // whole app. The interface index is already supplied
                    // separately, so strip the textual scope from the prefix.
                    addrs.add("${host.substringBefore('%')}/${ia.networkPrefixLength}")
                }
                item.addresses = StringList(addrs)
                var flags = 0
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                    flags = flags or 0x1 or 0x40 // IFF_UP | IFF_RUNNING
                }
                if (ni.isLoopback) flags = flags or 0x8
                if (ni.isPointToPoint) flags = flags or 0x10
                if (ni.supportsMulticast()) flags = flags or 0x1000
                item.flags = flags
                item.type = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ->
                        Libbox.InterfaceTypeWIFI
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
                        Libbox.InterfaceTypeCellular
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
                        Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                item.dnsServer =
                    StringList(lp.dnsServers.mapNotNull { it.hostAddress })
                item.metered =
                    !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                items.add(item)
            }
        } catch (_: Throwable) {}
        return NetworkInterfaceList(items)
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (notify(cm, network, listener)) defaultNetwork = network
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) =
                updateDefaultNetwork(cm, network, listener)

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities
            ) = updateDefaultNetwork(cm, network, listener)

            override fun onLost(network: Network) {
                if (network != defaultNetwork) return
                defaultNetwork = null
                val replacement = findUnderlyingNetwork(cm)
                if (replacement == null || !notify(cm, replacement, listener)) {
                    listener.updateDefaultInterface("", -1, false, false)
                } else {
                    defaultNetwork = replacement
                }
            }
        }
        networkCallback = cb
        // Registration is asynchronous. libbox can start resolving remote
        // rule-sets immediately, so seed the monitor before returning.
        findUnderlyingNetwork(cm)?.let {
            if (notify(cm, it, listener)) defaultNetwork = it
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .build()

        // Since Android P registerDefaultNetworkCallback() reports the VPN
        // itself. Keep a request for the physical default network instead,
        // matching the approach used by the official sing-box Android client.
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                cm.registerBestMatchingNetworkCallback(request, cb, main)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ->
                cm.requestNetwork(request, cb, main)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                cm.registerDefaultNetworkCallback(cb, main)
            else ->
                cm.registerDefaultNetworkCallback(cb)
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkCallback?.let {
            try {
                (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                    .unregisterNetworkCallback(it)
            } catch (_: Throwable) {}
        }
        networkCallback = null
        defaultNetwork = null
    }

    private fun updateDefaultNetwork(
        cm: ConnectivityManager,
        network: Network,
        listener: InterfaceUpdateListener
    ) {
        if (network != defaultNetwork && defaultNetwork != null) return
        if (notify(cm, network, listener)) defaultNetwork = network
    }

    private fun findUnderlyingNetwork(cm: ConnectivityManager): Network? {
        fun usable(network: Network): Boolean {
            val caps = cm.getNetworkCapabilities(network) ?: return false
            return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                cm.getLinkProperties(network)?.interfaceName != null
        }

        val active = cm.activeNetwork
        if (active != null && usable(active)) return active
        return cm.allNetworks
            .filter(::usable)
            .maxByOrNull { network ->
                val caps = cm.getNetworkCapabilities(network)
                when {
                    caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true -> 2
                    caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true -> 1
                    else -> 0
                }
            }
    }

    private fun notify(
        cm: ConnectivityManager,
        network: Network,
        listener: InterfaceUpdateListener
    ): Boolean {
        return try {
            val caps = cm.getNetworkCapabilities(network) ?: return false
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            ) {
                return false
            }
            val name = cm.getLinkProperties(network)?.interfaceName ?: return false
            val index = java.net.NetworkInterface.getByName(name)?.index ?: -1
            listener.updateDefaultInterface(name, index, false, false)
            true
        } catch (_: Throwable) {
            false
        }
    }

    override fun clearDNSCache() {}
    override fun includeAllNetworks(): Boolean = false
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun readWIFIState(): WIFIState? = null
    override fun sendNotification(notification: LibboxNotification) {}
    override fun systemCertificates(): StringIterator = StringList(emptyList())
    override fun underNetworkExtension(): Boolean = false

    // --- CommandServerHandler ------------------------------------------------

    override fun serviceReload() {}
    override fun serviceStop() { main.post { stopBox() } }
    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply { available = false; enabled = false }
    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun writeDebugMessage(message: String) {}

    // --- helpers -------------------------------------------------------------

    private inline fun forEachString(it: StringIterator, block: (String) -> Unit) {
        while (it.hasNext()) block(it.next())
    }

    private inline fun forEachPrefix(
        it: libbox.RoutePrefixIterator, block: (libbox.RoutePrefix) -> Unit
    ) {
        while (it.hasNext()) block(it.next())
    }

    private fun startStatsPump() {
        val tick = object : Runnable {
            override fun run() {
                if (commandServer == null) return
                val nextTick = this
                Thread({
                    val totals = readClashTotals()
                    main.post {
                        if (commandServer == null) return@post
                        val now = System.currentTimeMillis()
                        val upload = totals?.first ?: statsUploadTotal
                        val download = totals?.second ?: statsDownloadTotal
                        val elapsedSeconds =
                            if (statsSampleAt == 0L) 0.0
                            else (now - statsSampleAt).coerceAtLeast(1) / 1000.0
                        val uploadSpeed =
                            if (elapsedSeconds == 0.0) 0.0
                            else (upload - statsUploadTotal)
                                .coerceAtLeast(0) / elapsedSeconds
                        val downloadSpeed =
                            if (elapsedSeconds == 0.0) 0.0
                            else (download - statsDownloadTotal)
                                .coerceAtLeast(0) / elapsedSeconds
                        statsUploadTotal = upload
                        statsDownloadTotal = download
                        statsSampleAt = now
                        statsSink?.success(
                            mapOf(
                                "uploadTotal" to upload,
                                "downloadTotal" to download,
                                "uploadSpeed" to uploadSpeed,
                                "downloadSpeed" to downloadSpeed,
                                "connectedSince" to connectedSince
                            )
                        )
                        main.postDelayed(nextTick, 1000)
                    }
                }, "aurora-stats").start()
            }
        }
        main.post(tick)
    }

    private fun readClashTotals(): Pair<Long, Long>? {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", 9090), 1000)
                socket.soTimeout = 3000
                val writer = socket.getOutputStream().bufferedWriter()
                writer.write("GET /connections HTTP/1.1\r\n")
                writer.write("Host: 127.0.0.1:9090\r\n")
                writer.write("Connection: close\r\n\r\n")
                writer.flush()
                val response = socket.getInputStream().bufferedReader().readText()
                val start = response.indexOf('{')
                val end = response.lastIndexOf('}')
                if (start < 0 || end < start) return null
                val json = JSONObject(response.substring(start, end + 1))
                Pair(
                    json.optLong("uploadTotal", statsUploadTotal),
                    json.optLong("downloadTotal", statsDownloadTotal)
                )
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun startForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Aurora VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val pending = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
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

    override fun onRevoke() { main.post { stopBox() }; super.onRevoke() }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        try { tun?.close() } catch (_: Throwable) {}
        super.onDestroy()
    }

    /** libbox StringIterator backed by a Kotlin list. */
    private class StringList(private val items: List<String>) : StringIterator {
        private var i = 0
        override fun hasNext(): Boolean = i < items.size
        override fun next(): String = items[i++]
        override fun len(): Int = items.size.toLong().toInt()
    }

    private class NetworkInterfaceList(
        private val items: List<LibboxNetworkInterface>
    ) : LibboxNetworkInterfaceIterator {
        private var i = 0
        override fun hasNext(): Boolean = i < items.size
        override fun next(): LibboxNetworkInterface = items[i++]
    }
}
