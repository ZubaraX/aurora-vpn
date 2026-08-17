package com.auroravpn.aurora

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
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
import android.os.Process
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
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
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
        const val EXTRA_TITLE = "title"

        private const val CHANNEL_ID = "aurora_vpn"
        private const val NOTIFICATION_ID = 0xA0

        @JvmStatic var statusSink: EventChannel.EventSink? = null
        @JvmStatic var statsSink: EventChannel.EventSink? = null

        // The Clash API port is deliberately generation-specific. libbox
        // closes the old instance synchronously during a reload, but its HTTP
        // listener can remain bound for a short time. Reusing 9090 therefore
        // makes rapid reconnects fail with "address already in use".
        @Volatile private var publishedControllerPort = 0
        @Volatile private var libboxInitialized = false
        private val libboxSetupLock = Any()

        @JvmStatic
        fun controllerPort(): Int = publishedControllerPort

        @Volatile private var tunnelActive = false

        // Whether a TUN interface is actually established right now. MIUI can
        // tear the tunnel down while leaving the Service object alive, so
        // "we asked for a tunnel" (tunnelActive) is NOT proof one exists —
        // reporting "Защищено" off that alone hid a completely dead tunnel.
        @Volatile private var tunOpen = false

        @JvmStatic
        fun isTunnelActive(): Boolean = tunnelActive

        /// True only when the core is up AND the VPN interface is open.
        @JvmStatic
        fun isTunnelAlive(): Boolean = tunnelActive && tunOpen && coreConnectedFlag

        @Volatile private var coreConnectedFlag = false
    }

    private val main = Handler(Looper.getMainLooper())
    private val coreExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "aurora-box")
    }
    @Volatile private var coreGeneration = 0L
    @Volatile
    private var commandServer: CommandServer? = null
    @Volatile private var requestedConfig: String? = null
    @Volatile private var coreConnected = false
    private var controllerPort = 0
    private var tun: ParcelFileDescriptor? = null
    private var connectedSince: Long = 0
    @Volatile private var serverName: String? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var defaultNetwork: Network? = null
    private var statsUploadTotal = 0L
    private var statsDownloadTotal = 0L
    private var statsSampleAt = 0L

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                intent.getStringExtra(EXTRA_TITLE)?.let { serverName = it }
                startBox(intent.getStringExtra(EXTRA_CONFIG))
            }
            ACTION_STOP -> stopBox()
        }
        // A killed process cannot recover the in-memory config from a null
        // sticky intent. Let Dart/auto-connect issue a complete fresh request.
        return START_NOT_STICKY
    }

    private fun startBox(config: String?) {
        if (config == null) {
            tunnelActive = false
            emitStatus("error"); stopSelf(); return
        }
        AuroraTileState.saveConfig(this, config)
        tunnelActive = true
        // A double tap or two trigger polls can deliver the same request while
        // the first one is still starting. Coalesce it instead of reloading a
        // healthy (or not-yet-healthy) core.
        if (config == requestedConfig) {
            emitStatus(if (coreConnected) "connected" else "connecting")
            return
        }
        requestedConfig = config
        coreConnected = false
        val generation = ++coreGeneration
        emitStatus("connecting")
        // Foreground promotion must happen promptly and on the main thread.
        try { startForegroundNotification() } catch (t: Throwable) { logError("fg", t) }

        // All core mutations use one worker. Profile switches reuse the same
        // CommandServer and call startOrReloadService(), so a second Clash API
        // listener can never race the existing 127.0.0.1:9090 listener.
        coreExecutor.execute {
            if (generation != coreGeneration) return@execute
            var server = commandServer
            try {
                android.util.Log.i("AuroraVPN", "core request $generation: preparing")
                val work = File(filesDir, "work").apply { mkdirs() }
                // Send the core's own logs to a file the in-app Logs screen reads.
                try { Libbox.redirectStderr(File(filesDir, "box.log").absolutePath) } catch (_: Throwable) {}
                if (!libboxInitialized) {
                    synchronized(libboxSetupLock) {
                        if (!libboxInitialized) {
                            Libbox.setup(SetupOptions().apply {
                                basePath = filesDir.absolutePath
                                workingPath = work.absolutePath
                                tempPath = cacheDir.absolutePath
                            })
                            libboxInitialized = true
                            android.util.Log.i(
                                "AuroraVPN",
                                "core request $generation: libbox ready"
                            )
                        }
                    }
                }
                // OverrideOptions MUST be non-null — the Go side dereferences it
                // unconditionally (nil → native panic → crash on connect).
                val override = OverrideOptions().apply {
                    includePackage = StringList(emptyList())
                    excludePackage = StringList(emptyList())
                }
                val activeServer = server ?: CommandServer(this, this).also {
                    it.start()
                    server = it
                    commandServer = it
                    android.util.Log.i("AuroraVPN", "core request $generation: command server ready")
                }
                android.util.Log.i("AuroraVPN", "core request $generation: applying config")
                val resolvedConfig = resolveServerHost(config)
                val newControllerPort = applyConfig(activeServer, resolvedConfig, override)
                if (generation != coreGeneration) return@execute
                controllerPort = newControllerPort
                publishedControllerPort = newControllerPort
                coreConnected = true
                coreConnectedFlag = true
                connectedSince = System.currentTimeMillis()
                statsUploadTotal = 0
                statsDownloadTotal = 0
                statsSampleAt = 0
                android.util.Log.i("AuroraVPN", "core request $generation: connected")
                emitStatus("connected")
                main.post { startStatsPump(generation) }
            } catch (t: Throwable) {
                if (generation != coreGeneration) return@execute
                tunnelActive = false
                requestedConfig = null
                coreConnected = false
                coreConnectedFlag = false
                logError("start", t)
                closeCoreResources(server)
                emitStatus("error:" + (t.message ?: "не удалось запустить ядро"))
                main.post { finishStopped(generation) }
            }
        }
    }

    private fun applyConfig(
        server: CommandServer,
        config: String,
        override: OverrideOptions
    ): Int {
        var lastFailure: Throwable? = null
        for (attempt in 1..3) {
            val candidatePort = findFreeControllerPort()
            val resolvedConfig = JSONObject(config).apply {
                val log = optJSONObject("log") ?: JSONObject().also { put("log", it) }
                log.put("output", File(filesDir, "box.log").absolutePath)
                val experimental = optJSONObject("experimental")
                    ?: JSONObject().also { put("experimental", it) }
                val clash = experimental.optJSONObject("clash_api")
                    ?: JSONObject().also { experimental.put("clash_api", it) }
                clash.put("external_controller", "127.0.0.1:$candidatePort")
            }.toString()
            try {
                server.startOrReloadService(resolvedConfig, override)
                return candidatePort
            } catch (t: Throwable) {
                lastFailure = t
                if (!isAddressInUse(t) || attempt == 3) throw t
                android.util.Log.w(
                    "AuroraVPN",
                    "Clash API port $candidatePort raced during reload; retry $attempt/3",
                    t
                )
                try {
                    Thread.sleep(150L * attempt)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw t
                }
            }
        }
        throw lastFailure ?: IllegalStateException("Не удалось запустить Clash API")
    }

    private val ipv4Regex = Regex("^\\d{1,3}(\\.\\d{1,3}){3}$")

    private fun isNumericHost(host: String): Boolean =
        host.contains(':') || host.startsWith("[") || ipv4Regex.matches(host)

    /**
     * Rewrites every proxy outbound's `server` domain to an IP resolved through
     * the PHYSICAL network's own DNS (the carrier resolver), leaving the TLS
     * `server_name` (Reality's borrowed SNI) untouched.
     *
     * Why: on a restricted / white-list network a public DoH (1.1.1.1) is
     * refused, so sing-box cannot bootstrap-resolve the server's own domain and
     * the tunnel comes up but passes no traffic (the exact failure seen in
     * reference clients on cellular). The carrier resolver bound to the
     * underlying network is always reachable and returns a routable IP.
     */
    private fun resolveServerHost(config: String): String {
        return try {
            val json = JSONObject(config)
            val outbounds = json.optJSONArray("outbounds") ?: return config
            var changed = false
            for (i in 0 until outbounds.length()) {
                val ob = outbounds.optJSONObject(i) ?: continue
                when (ob.optString("type")) {
                    "", "direct", "block", "dns", "selector", "urltest" -> continue
                }
                val host = ob.optString("server")
                if (host.isEmpty() || isNumericHost(host)) continue
                val ip = resolveViaUnderlying(host) ?: continue
                ob.put("server", ip)
                changed = true
                android.util.Log.i("AuroraVPN", "resolved server $host -> $ip")
            }
            if (changed) json.toString() else config
        } catch (t: Throwable) {
            logError("resolve", t)
            config
        }
    }

    private fun resolveViaUnderlying(host: String): String? {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = defaultNetwork ?: findUnderlyingNetwork(cm)
        return try {
            val addrs = if (net != null) net.getAllByName(host)
                        else InetAddress.getAllByName(host)
            // Prefer IPv4 — widest reachability on cellular (464XLAT handles v6).
            val chosen = addrs.firstOrNull { it is java.net.Inet4Address }
                ?: addrs.firstOrNull()
            chosen?.hostAddress
        } catch (_: Throwable) {
            null
        }
    }

    private fun findFreeControllerPort(): Int =
        ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use {
            it.reuseAddress = false
            it.localPort
        }

    private fun isAddressInUse(t: Throwable): Boolean {
        var current: Throwable? = t
        while (current != null) {
            val message = current.message.orEmpty().lowercase()
            if ("address already in use" in message || "bind: address" in message) {
                return true
            }
            current = current.cause
        }
        return false
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
        val generation = ++coreGeneration
        tunnelActive = false
        requestedConfig = null
        coreConnected = false
        emitStatus("disconnecting")
        coreExecutor.execute {
            // A newer start supersedes a queued stop and reloads the existing
            // service instead of tearing it down underneath the new request.
            if (generation != coreGeneration) return@execute
            closeCoreResources(commandServer)
            emitStatus("disconnected")
            main.post { finishStopped(generation) }
        }
    }

    private fun closeCoreResources(server: CommandServer?) {
        if (commandServer === server) commandServer = null
        val closingPort = controllerPort
        controllerPort = 0
        if (publishedControllerPort == closingPort) publishedControllerPort = 0
        requestedConfig = null
        coreConnected = false
        // Release the Android VPN descriptor before waiting for the Go service
        // to finish, matching the official sing-box Android lifecycle.
        try { tun?.close() } catch (_: Throwable) {}
        tun = null
        tunOpen = false
        try { server?.closeService() } catch (_: Throwable) {}
        try { server?.close() } catch (_: Throwable) {}
        networkCallback?.let {
            try {
                (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                    .unregisterNetworkCallback(it)
            } catch (_: Throwable) {}
        }
        networkCallback = null
        defaultNetwork = null
    }

    private fun finishStopped(generation: Long) {
        // A new ACTION_START may arrive after the worker posted this callback.
        // Never let an old stop/error callback tear down that newer request.
        if (generation != coreGeneration) return
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
        val previousTun = tun
        tun = pfd
        tunOpen = true
        try { previousTun?.close() } catch (_: Throwable) {}

        // Bind the tunnel to the physical network that actually carries it.
        // Without this the OS keeps the VPN tied to whatever was default at
        // establish() time; on cellular that leaves protected proxy sockets on a
        // stale/wrong interface, so the tunnel connects but no traffic flows
        // (the classic "works on Wi-Fi, dead on mobile data"). The interface
        // monitor keeps this current on every network change.
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        applyUnderlyingNetwork(defaultNetwork ?: findUnderlyingNetwork(cm))
        return pfd.fd
    }

    /// Tells Android which physical network backs the VPN, or null to fall back
    /// to the system default. Safe to call before establish() (no-op then).
    private fun applyUnderlyingNetwork(network: Network?) {
        try {
            setUnderlyingNetworks(if (network != null) arrayOf(network) else null)
        } catch (_: Throwable) {}
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProto: Int, srcIp: String, srcPort: Int, destIp: String, destPort: Int
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw UnsupportedOperationException("Android connection lookup requires API 29")
        }
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val uid = cm.getConnectionOwnerUid(
            ipProto,
            InetSocketAddress(srcIp, srcPort),
            InetSocketAddress(destIp, destPort)
        )
        if (uid == Process.INVALID_UID) {
            throw IllegalStateException("Android connection owner not found")
        }
        val packages = packageManager.getPackagesForUid(uid)?.toList().orEmpty()
        return ConnectionOwner().apply {
            userId = uid
            userName = packages.firstOrNull().orEmpty()
            setAndroidPackageNames(StringList(packages))
        }
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
                if (notify(cm, network, listener)) {
                    defaultNetwork = network
                    applyUnderlyingNetwork(network)
                }
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
                    applyUnderlyingNetwork(null)
                } else {
                    defaultNetwork = replacement
                    applyUnderlyingNetwork(replacement)
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
        if (notify(cm, network, listener)) {
            defaultNetwork = network
            applyUnderlyingNetwork(network)
        }
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
    override fun serviceStop() {
        if (commandServer != null) main.post { stopBox() }
    }
    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply { available = false; enabled = false }
    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun writeDebugMessage(message: String) {}

    // --- helpers -------------------------------------------------------------

    private fun fmtSpeed(bytesPerSec: Double): String {
        val v = if (bytesPerSec < 0) 0.0 else bytesPerSec
        return when {
            v >= 1024 * 1024 -> String.format("%.1f МБ/с", v / (1024 * 1024))
            v >= 1024 -> String.format("%.0f КБ/с", v / 1024)
            else -> String.format("%.0f Б/с", v)
        }
    }

    private inline fun forEachString(it: StringIterator, block: (String) -> Unit) {
        while (it.hasNext()) block(it.next())
    }

    private inline fun forEachPrefix(
        it: libbox.RoutePrefixIterator, block: (libbox.RoutePrefix) -> Unit
    ) {
        while (it.hasNext()) block(it.next())
    }

    private fun startStatsPump(generation: Long) {
        val tick = object : Runnable {
            override fun run() {
                if (generation != coreGeneration || commandServer == null) return
                val nextTick = this
                Thread({
                    val totals = readClashTotals()
                    main.post {
                        if (generation != coreGeneration || commandServer == null) {
                            return@post
                        }
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
                        // Live speed in the shade — state, profile (title) and
                        // throughput without opening the app.
                        if (coreConnected) {
                            updateNotification(
                                "Подключено · ↓ ${fmtSpeed(downloadSpeed)} · ↑ ${fmtSpeed(uploadSpeed)}"
                            )
                        }
                        main.postDelayed(nextTick, 1000)
                    }
                }, "aurora-stats").start()
            }
        }
        main.post(tick)
    }

    private fun readClashTotals(): Pair<Long, Long>? {
        val port = controllerPort
        if (port <= 0) return null
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 1000)
                socket.soTimeout = 3000
                val writer = socket.getOutputStream().bufferedWriter()
                writer.write("GET /connections HTTP/1.1\r\n")
                writer.write("Host: 127.0.0.1:$port\r\n")
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

    private fun buildNotification(statusLine: String): Notification {
        val pending = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        // A one-tap "Disconnect" straight from the shade — the tunnel can be
        // stopped without opening the app or hunting for the Quick Settings tile.
        val stopIntent = Intent(this, AuroraVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE
        )
        // The status + speed goes in the TITLE, not the second line: aggressive
        // launchers (MIUI etc.) collapse a low-importance foreground notification
        // to the title only and hide contentText/BigText, which is why the status
        // line never appeared. The profile name is the (best-effort) second line.
        val profile = serverName?.takeIf { it.isNotBlank() } ?: "Aurora VPN"
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(statusLine)
            .setContentText(profile)
            .setStyle(
                Notification.BigTextStyle()
                    .setBigContentTitle(statusLine)
                    .bigText(profile)
            )
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                    "Отключить",
                    stopPending
                ).build()
            )
            .build()
    }

    private fun startForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Aurora VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        startForeground(NOTIFICATION_ID, buildNotification("Подключение…"))
    }

    private fun updateNotification(text: String) {
        // Always post on the main thread — emitStatus runs on the core worker,
        // and some launchers drop foreground-notification updates issued off the
        // main thread.
        main.post {
            try {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, buildNotification(text))
            } catch (_: Throwable) {}
        }
    }

    private fun emitStatus(status: String) {
        AuroraTileState.updateStatus(this, status)
        when {
            status == "connected" -> updateNotification("Подключено · защищено")
            status == "connecting" -> updateNotification("Подключение…")
        }
        main.post { statusSink?.success(status) }
    }

    override fun onRevoke() { main.post { stopBox() }; super.onRevoke() }

    override fun onDestroy() {
        ++coreGeneration
        tunnelActive = false
        AuroraTileState.updateStatus(this, "disconnected")
        requestedConfig = null
        coreConnected = false
        if (publishedControllerPort == controllerPort) publishedControllerPort = 0
        main.removeCallbacksAndMessages(null)
        coreExecutor.execute { closeCoreResources(commandServer) }
        coreExecutor.shutdown()
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
