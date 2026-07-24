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
import libbox.PlatformInterface
import libbox.SetupOptions
import libbox.StringIterator
import libbox.SystemProxyStatus
import libbox.TunOptions
import libbox.WIFIState
import java.io.File
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
                server.startOrReloadService(config, override)
                commandServer = server
                connectedSince = System.currentTimeMillis()
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
        try {
            for (ni in java.net.NetworkInterface.getNetworkInterfaces()) {
                if (!ni.isUp) continue
                val item = LibboxNetworkInterface()
                item.name = ni.name
                item.index = ni.index
                item.mtu = try { ni.mtu } catch (_: Throwable) { 0 }
                val addrs = ArrayList<String>()
                for (ia in ni.interfaceAddresses) {
                    val host = ia.address?.hostAddress ?: continue
                    addrs.add("$host/${ia.networkPrefixLength}")
                }
                item.addresses = StringList(addrs)
                var flags = 0
                if (ni.isUp) flags = flags or 0x1 or 0x40
                if (ni.isLoopback) flags = flags or 0x8
                if (ni.isPointToPoint) flags = flags or 0x10
                if (ni.supportsMulticast()) flags = flags or 0x1000
                item.flags = flags
                item.type = Libbox.InterfaceTypeOther
                item.dnsServer = StringList(emptyList())
                item.metered = false
                items.add(item)
            }
        } catch (_: Throwable) {}
        return NetworkInterfaceList(items)
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = notify(cm, network, listener)
            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) =
                notify(cm, network, listener)
            override fun onLost(network: Network) =
                listener.updateDefaultInterface("", -1, false, false)
        }
        networkCallback = cb
        cm.registerDefaultNetworkCallback(cb)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkCallback?.let {
            try {
                (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                    .unregisterNetworkCallback(it)
            } catch (_: Throwable) {}
        }
        networkCallback = null
    }

    private fun notify(cm: ConnectivityManager, network: Network, l: InterfaceUpdateListener) {
        try {
            val name = cm.getLinkProperties(network)?.interfaceName ?: return
            val index = java.net.NetworkInterface.getByName(name)?.index ?: -1
            l.updateDefaultInterface(name, index, false, false)
        } catch (_: Throwable) {}
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
