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
import java.util.Date
import java.util.concurrent.Executors
import org.json.JSONObject

/** sends messages to the mac on a single background thread, one short connection per message */
class Forwarder private constructor(context: Context) {
    private val app = context.applicationContext
    private val prefs = Prefs(app)
    private val locator = MacLocator(app, prefs)
    private val executor = Executors.newSingleThreadExecutor()

    fun posted(key: String, pkg: String, appName: String, title: String, text: String) {
        send(
            JSONObject()
                .put("type", "posted")
                .put("key", key)
                .put("package", pkg)
                .put("appName", appName)
                .put("title", title)
                .put("text", text)
        )
    }

    fun removed(key: String) {
        send(JSONObject().put("type", "removed").put("key", key))
    }

    private fun send(message: JSONObject) {
        executor.execute {
            message.put("ts", System.currentTimeMillis())
            val payload = message.toString().toByteArray()
            val result = try {
                val endpoint = prefs.endpoint ?: locator.locate() ?: throw IOException("no mac found")
                try {
                    deliver(endpoint, payload)
                } catch (e: IOException) {
                    Log.i(TAG, "send to ${endpoint.host} failed, rediscovering", e)
                    prefs.endpoint = null
                    deliver(locator.locate() ?: throw IOException("no mac found"), payload)
                }
            } catch (e: Exception) {
                Log.w(TAG, "send failed", e)
                "Failed: ${e.message}"
            }
            prefs.lastResult = "$result (${DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())})"
        }
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
                prefs.approved = status == 0
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

        @Volatile
        private var instance: Forwarder? = null

        fun get(context: Context): Forwarder =
            instance ?: synchronized(this) { instance ?: Forwarder(context).also { instance = it } }
    }
}
