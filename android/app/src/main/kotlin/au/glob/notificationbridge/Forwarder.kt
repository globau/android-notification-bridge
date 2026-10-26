package au.glob.notificationbridge

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.text.DateFormat
import java.util.Base64
import java.util.Date
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.json.JSONObject

/**
 * sends messages to each paired mac on its own background thread, one short connection per message,
 * so an unreachable mac never delays the others
 */
class Forwarder private constructor(context: Context) {
    private val app = context.applicationContext
    private val prefs = Prefs(app)
    private val locator = MacLocator(app)
    private val executors = ConcurrentHashMap<String, ExecutorService>()
    private val unreachableUntil = ConcurrentHashMap<String, Long>()

    fun posted(key: String, pkg: String, appName: String, title: String, text: String, target: ByteArray? = null) {
        send(
            JSONObject()
                .put("type", "posted")
                .put("key", key)
                .put("package", pkg)
                .put("appName", appName)
                .put("title", title)
                .put("text", text),
            target,
        )
    }

    fun removed(key: String) {
        send(JSONObject().put("type", "removed").put("key", key))
    }

    /** sends to every paired mac, or just target */
    fun test(target: ByteArray? = null) {
        target?.let { unreachableUntil.remove(id(it)) }
        posted(
            "test:${System.currentTimeMillis()}", app.packageName, "Notification Bridge", "Test",
            "Hello from your phone", target,
        )
    }

    private fun send(message: JSONObject, target: ByteArray? = null) {
        val payload = message.put("ts", System.currentTimeMillis()).toString().toByteArray()
        val macs = prefs.macs
        val ids = macs.map { id(it.publicKey) }.toSet()
        executors.entries.removeIf { (id, executor) -> (id !in ids).also { if (it) executor.shutdown() } }
        unreachableUntil.keys.retainAll(ids)
        macs
            .filter { target == null || it.publicKey.contentEquals(target) }
            .forEach { mac ->
                val id = id(mac.publicKey)
                executors.computeIfAbsent(id) { Executors.newSingleThreadExecutor() }.execute {
                    sendTo(id, mac.publicKey, payload)
                }
            }
    }

    private fun id(publicKey: ByteArray) = Base64.getEncoder().encodeToString(publicKey)

    private fun sendTo(id: String, publicKey: ByteArray, payload: ByteArray) {
        val mac = prefs.mac(publicKey)?.takeIf { it.enabled } ?: return
        val result = try {
            if (System.currentTimeMillis() < (unreachableUntil[id] ?: 0)) throw IOException("mac not found")
            val cached = mac.host?.let { Endpoint(mac.name, it, mac.port, publicKey) }
            try {
                deliver(cached ?: rediscover(id, publicKey), payload)
            } catch (e: IOException) {
                if (cached == null) throw e
                Log.i(TAG, "send to ${cached.host} failed, rediscovering", e)
                deliver(rediscover(id, publicKey), payload)
            }
        } catch (e: Exception) {
            Log.w(TAG, "send to ${mac.name} failed", e)
            "Failed: ${e.message}"
        }
        val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
        prefs.updateMac(publicKey) { it.copy(lastResult = "$result ($time)") }
    }

    /** a failed discovery skips the mac for a while rather than spending the full timeout on every message */
    private fun rediscover(id: String, publicKey: ByteArray): Endpoint {
        val endpoint = locator.locate(publicKey)
        if (endpoint == null) {
            unreachableUntil[id] = System.currentTimeMillis() + UNREACHABLE_MS
            prefs.updateMac(publicKey) { it.copy(host = null) }
            throw IOException("mac not found")
        }
        unreachableUntil.remove(id)
        prefs.updateMac(publicKey) { it.copy(name = endpoint.name, host = endpoint.host, port = endpoint.port) }
        return endpoint
    }

    private fun deliver(endpoint: Endpoint, payload: ByteArray): String {
        val identity = prefs.identity
        val ephemeral = Crypto.generateKeyPair()
        val key = Crypto.sessionKey(identity, ephemeral, endpoint.publicKey)
        Socket().use { socket ->
            socket.connect(InetSocketAddress(endpoint.host, endpoint.port), 3000)
            socket.soTimeout = 5000
            val output = DataOutputStream(socket.getOutputStream().buffered())
            output.frame(Crypto.hello(identity.publicKey, ephemeral.publicKey, deviceName()))
            output.frame(Crypto.seal(payload, key))
            output.flush()
            val status = DataInputStream(socket.getInputStream()).readUnsignedByte()
            if (status <= 2) {
                prefs.updateMac(endpoint.publicKey) { it.copy(approved = status == 0) }
            }
            return when (status) {
                0 -> "Delivered to ${endpoint.name}"
                1 -> "Waiting for approval on ${endpoint.name}"
                2 -> "Denied by ${endpoint.name}"
                3 -> "Rejected by ${endpoint.name}"
                else -> "Unknown status $status"
            }
        }
    }

    private fun DataOutputStream.frame(bytes: ByteArray) {
        writeInt(bytes.size)
        write(bytes)
    }

    private fun deviceName(): String =
        Settings.Global.getString(app.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL

    companion object {
        private const val TAG = "Forwarder"
        private const val UNREACHABLE_MS = 60_000L

        @Volatile
        private var instance: Forwarder? = null

        fun get(context: Context): Forwarder =
            instance ?: synchronized(this) { instance ?: Forwarder(context).also { instance = it } }
    }
}
