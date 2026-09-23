package com.chenweikeng.monkeycraft

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class TailscaleTransportPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val io = Executors.newSingleThreadExecutor()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val methods = MethodChannel(messenger, "monkeycraft/tailscale")
    private val events = EventChannel(messenger, "monkeycraft/tailscale_events")
    private val generation = AtomicLong(0)
    private val refreshQueued = AtomicBoolean(false)

    @Volatile
    private var sink: EventChannel.EventSink? = null

    @Volatile
    private var disposed = false

    @Volatile
    private var pollTask: ScheduledFuture<*>? = null

    private var handle = -1
    private var bridge: Bridge? = null

    @Volatile
    private var authOpenError: String? = null

    @Volatile
    private var lastSnapshot: Map<String, Any?> = mapOf("phase" to "stopped", "peers" to emptyList<Any>())

    private val authUrlLauncher = AuthUrlLauncher(
        currentGeneration = generation::get,
        isDisposed = { disposed },
        postToUi = { runnable -> activity.runOnUiThread(Runnable(runnable)) },
        open = { authUrl ->
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(authUrl)))
        },
        onOpenSuccess = {
            authOpenError = null
            sink?.success(lastSnapshot + mapOf(
                "errorCode" to null,
                "errorMessage" to null,
            ))
        },
        onOpenFailure = {
            authOpenError = "Could not open the Tailscale sign-in page. Tap to try again."
            val value = lastSnapshot + mapOf(
                "errorCode" to "auth_url_open_failed",
                "errorMessage" to authOpenError,
            )
            sink?.success(value)
        },
    )

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        disposed = true
        generation.incrementAndGet()
        sink = null
        stopPolling()
        scheduler.shutdownNow()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        try {
            io.execute {
                try {
                    closeNode()
                } catch (_: Throwable) {
                }
            }
        } catch (_: RejectedExecutionException) {
        }
        io.shutdown()
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        sink = eventSink
        queueEmit()
        startPolling()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stopPolling()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val callGeneration = when (call.method) {
            "stop", "cancel", "logout" -> generation.incrementAndGet()
            else -> generation.get()
        }
        try {
            io.execute {
                try {
                    when (call.method) {
                        "diagnostics" -> result.success(diagnostics())
                        "status" -> result.success(snapshot())
                        "start" -> {
                            start(callGeneration)
                            result.success(snapshot())
                        }
                        "loginInteractive" -> {
                            login(callGeneration)
                            result.success(null)
                        }
                        "listPeers" -> result.success(snapshot()["peers"])
                        "openBridge" -> {
                            val nodeId = call.argument<String>("nodeId")
                                ?: throw IllegalArgumentException("missing nodeId")
                            val port = call.argument<Int>("port") ?: 9600
                            require(port in 1..65535) { "invalid port" }
                            bridge?.close()
                            val currentHandle = requireHandle()
                            val fd = TailscaleNative.dial(
                                currentHandle,
                                "tcp",
                                "${peerAddress(nodeId)}:$port",
                                15_000,
                            )
                            check(fd >= 0) { TailscaleNative.error(currentHandle) }
                            bridge = Bridge(fd)
                            result.success(mapOf("url" to bridge!!.url, "leaseId" to bridge!!.id))
                        }
                        "closeBridge" -> {
                            val id = call.argument<String>("leaseId")
                            if (id != null && bridge?.id != id) {
                                throw IllegalArgumentException("unknown bridge lease")
                            }
                            bridge?.close()
                            bridge = null
                            result.success(null)
                        }
                        "stop", "cancel" -> {
                            closeNode()
                            result.success(null)
                        }
                        "logout" -> {
                            logout()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("tailscale", t.message ?: "embedded Tailscale failed", null)
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("tailscale", "embedded Tailscale is shutting down", null)
        }
    }

    private fun start(expectedGeneration: Long = generation.get()) {
        if (expectedGeneration != generation.get() || disposed) return
        check(TailscaleNative.available) { "embedded Tailscale is unavailable for this ABI" }
        if (handle >= 0) return
        authOpenError = null
        val dir = stateDirectory()
        check(dir.mkdirs() || dir.isDirectory) {
            "could not create embedded Tailscale state directory"
        }
        check(TailscaleNative.configure(dir.absolutePath) == 0) {
            "could not configure embedded Tailscale runtime"
        }
        val newHandle = TailscaleNative.newNode()
        check(newHandle >= 0) { "could not create embedded Tailscale node" }
        try {
            check(TailscaleNative.setDir(newHandle, dir.absolutePath) == 0) {
                TailscaleNative.error(newHandle)
            }
            check(TailscaleNative.setHostname(newHandle, "monkeycraft-android") == 0) {
                TailscaleNative.error(newHandle)
            }
            check(TailscaleNative.start(newHandle) == 0) {
                TailscaleNative.error(newHandle)
            }
            if (expectedGeneration != generation.get() || disposed) {
                TailscaleNative.close(newHandle)
                return
            }
            handle = newHandle
            emit(expectedGeneration)
        } catch (t: Throwable) {
            TailscaleNative.close(newHandle)
            throw t
        }
    }

    private fun diagnostics(): Map<String, Any> {
        val available = TailscaleNative.available
        return mapOf(
            "available" to available,
            "libtailscaleLinked" to available,
            "statusJsonAvailable" to available,
            "reason" to if (available) {
                "libtailscale linked"
            } else {
                "embedded Tailscale is unavailable for this ABI"
            },
            "libtailscaleCommit" to "80771313ac4127973677c993889fe215abcf1fbd",
            "tailscaleGoModule" to "tailscale.com v1.94.1",
        )
    }

    private fun login(expectedGeneration: Long) {
        start(expectedGeneration)
        if (expectedGeneration != generation.get() || disposed) return
        val authUrl = JSONObject(statusJson()).optString("AuthURL")
        if (isOfficialAuthUrl(authUrl)) {
            emit(expectedGeneration, false)
            openAuthUrl(authUrl, expectedGeneration, true)
        }
    }

    private fun logout() {
        try {
            if (handle >= 0) postLocalApi("/localapi/v0/logout")
        } finally {
            closeNode()
            val dir = stateDirectory()
            check(!dir.exists() || dir.deleteRecursively()) {
                "could not delete embedded Tailscale state"
            }
        }
    }

    private fun postLocalApi(path: String) {
        val loopback = TailscaleNative.loopback(requireHandle())
            ?: error(TailscaleNative.error(handle))
        val connection = URL("http://${loopback[0]}$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            connection.setRequestProperty("Sec-Tailscale", "localapi")
            val credentials = Base64.encodeToString(
                "tsnet:${loopback[2]}".toByteArray(),
                Base64.NO_WRAP,
            )
            connection.setRequestProperty("Authorization", "Basic $credentials")
            connection.doOutput = true
            connection.outputStream.use { }
            check(connection.responseCode < 300) {
                "Tailscale local API returned ${connection.responseCode}"
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun requireHandle(): Int {
        check(handle >= 0) { "embedded Tailscale is not running" }
        return handle
    }

    private fun closeNode() {
        bridge?.close()
        bridge = null
        val closingHandle = handle
        handle = -1
        authOpenError = null
        if (closingHandle >= 0) {
            check(TailscaleNative.close(closingHandle) == 0) {
                TailscaleNative.error(closingHandle)
            }
        }
        emit()
    }

    private fun peerAddress(nodeId: String): String {
        val peers = JSONObject(statusJson()).optJSONObject("Peer") ?: error("peer not found")
        val peer = peers.keys().asSequence()
            .mapNotNull { peers.optJSONObject(it) }
            .firstOrNull { it.optString("ID") == nodeId }
            ?: error("peer not found")
        val ips = peer.optJSONArray("TailscaleIPs")
        for (index in 0 until (ips?.length() ?: 0)) {
            val ip = ips!!.optString(index)
            if (ip.isNotEmpty() && !ip.contains(':')) return ip
        }
        return peer.optString("DNSName").trimEnd('.').ifEmpty {
            error("peer has no address")
        }
    }

    private fun snapshot(): Map<String, Any?> {
        if (handle < 0) {
            return mapOf("phase" to "stopped", "peers" to emptyList<Any>())
        }
        val json = JSONObject(statusJson())
        val self = json.optJSONObject("Self")
        val peers = json.optJSONObject("Peer")
        val list = peers?.keys()?.asSequence()?.mapNotNull { key ->
            peers.optJSONObject(key)?.let { peer ->
                mapOf(
                    "nodeId" to peer.optString("ID"),
                    "hostName" to peer.optString("HostName"),
                    "online" to peer.optBoolean("Online"),
                    "dnsName" to peer.optString("DNSName"),
                    "tailscaleIPs" to peer.optJSONArray("TailscaleIPs")?.let { addresses ->
                        (0 until addresses.length()).map { addresses.optString(it) }
                    },
                )
            }
        }?.filter { (it["nodeId"] as String).isNotEmpty() }?.toList() ?: emptyList()
        val backendState = json.optString("BackendState")
        val health = json.optJSONArray("Health")
        val phase = when (backendState) {
            "NeedsLogin" -> "needsLogin"
            "NeedsMachineAuth" -> "needsApproval"
            "Running" -> "running"
            "Starting", "NoState" -> "starting"
            "Stopped" -> "stopped"
            else -> if (health != null && health.length() > 0) "failed" else "starting"
        }
        return mapOf(
            "phase" to phase,
            "errorCode" to if (phase == "failed") {
                "status_failed"
            } else if (authOpenError != null) {
                "auth_url_open_failed"
            } else {
                null
            },
            "errorMessage" to if (phase == "failed") {
                "Embedded Tailscale reported an unhealthy state"
            } else {
                authOpenError
            },
            "nodeId" to self?.optString("ID"),
            "hostName" to self?.optString("HostName"),
            "backendState" to backendState,
            "authUrlHost" to Uri.parse(json.optString("AuthURL")).host,
            "peers" to list,
        )
    }

    private fun statusJson(): String {
        return TailscaleNative.status(requireHandle())
            ?: error(TailscaleNative.error(handle))
    }

    private fun emit(
        expectedGeneration: Long = generation.get(),
        openAuthUrl: Boolean = true,
    ) {
        var authUrl: String? = null
        val value = if (handle < 0) {
            snapshot()
        } else {
            try {
                authUrl = JSONObject(statusJson()).optString("AuthURL")
                snapshot()
            } catch (_: Throwable) {
                mapOf(
                    "phase" to "failed",
                    "errorCode" to "status_failed",
                    "errorMessage" to "Could not read embedded Tailscale status",
                    "peers" to emptyList<Any>(),
                )
            }
        }
        lastSnapshot = value
        activity.runOnUiThread {
            if (!disposed && expectedGeneration == generation.get()) sink?.success(value)
        }
        if (openAuthUrl) {
            authUrl?.takeIf(::isOfficialAuthUrl)?.let {
                openAuthUrl(it, expectedGeneration, false)
            }
        }
    }

    private fun openAuthUrl(authUrl: String, expectedGeneration: Long, allowReopen: Boolean) {
        if (allowReopen) {
            authUrlLauncher.openExplicit(authUrl, expectedGeneration)
        } else {
            authUrlLauncher.openAutomatic(authUrl, expectedGeneration)
        }
    }

    private fun startPolling() {
        stopPolling()
        pollTask = scheduler.scheduleWithFixedDelay(
            { queueEmit() },
            1,
            1,
            TimeUnit.SECONDS,
        )
    }

    private fun stopPolling() {
        pollTask?.cancel(false)
        pollTask = null
    }

    private fun queueEmit() {
        if (disposed || sink == null || !refreshQueued.compareAndSet(false, true)) return
        val expectedGeneration = generation.get()
        try {
            io.execute {
                try {
                    emit(expectedGeneration)
                } finally {
                    refreshQueued.set(false)
                }
            }
        } catch (_: RejectedExecutionException) {
            refreshQueued.set(false)
        }
    }

    private fun stateDirectory(): File {
        return File(activity.noBackupFilesDir, "MonkeyCraftTailscale")
    }

    private fun isOfficialAuthUrl(value: String): Boolean {
        val uri = Uri.parse(value)
        val host = uri.host ?: return false
        return uri.scheme == "https" &&
            (host == "tailscale.com" || host.endsWith(".tailscale.com"))
    }
}

private class Bridge(fd: Int) {
    val id = UUID.randomUUID().toString()
    private val server = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
    val url = "ws://127.0.0.1:${server.localPort}"
    private val remote = ParcelFileDescriptor.adoptFd(fd)
    private val closed = AtomicBoolean(false)

    @Volatile
    private var local: java.net.Socket? = null

    init {
        Thread {
            try {
                server.accept().use { socket ->
                    local = socket
                    if (closed.get()) return@use
                    server.close()
                    val inbound = Thread {
                        try {
                            FileInputStream(remote.fileDescriptor).copyTo(socket.getOutputStream())
                        } finally {
                            close()
                        }
                    }
                    inbound.start()
                    try {
                        socket.getInputStream().copyTo(FileOutputStream(remote.fileDescriptor))
                    } finally {
                        close()
                        inbound.join()
                    }
                }
            } catch (_: Throwable) {
            } finally {
                close()
            }
        }.start()
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        try {
            local?.close()
        } catch (_: Throwable) {
        }
        try {
            server.close()
        } catch (_: Throwable) {
        }
        try {
            remote.close()
        } catch (_: Throwable) {
        }
    }
}
