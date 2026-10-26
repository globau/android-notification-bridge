package au.glob.notificationbridge

import android.content.Context
import android.content.SharedPreferences
import java.util.Base64
import org.json.JSONArray
import org.json.JSONObject

class Endpoint(val name: String, val host: String, val port: Int, val publicKey: ByteArray)

/**
 * approved: the mac has accepted this phone; fingerprints are only shown until then
 * enabled: nothing is sent to a disabled mac, but it stays paired
 */
data class PairedMac(
    val publicKey: ByteArray,
    val name: String,
    val host: String?,
    val port: Int,
    val approved: Boolean = false,
    val lastResult: String? = null,
    val enabled: Boolean = true,
)

class Prefs(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("bridge", Context.MODE_PRIVATE)

    @get:Synchronized
    val identity: Crypto.KeyPair
        get() {
            val private = prefs.getString("phonePrivate", null)
            val public = prefs.getString("phonePublic", null)
            if (private != null && public != null) {
                return Crypto.KeyPair(decode(private), decode(public))
            }
            return Crypto.generateKeyPair().also {
                prefs.edit()
                    .putString("phonePrivate", encode(it.privateKey))
                    .putString("phonePublic", encode(it.publicKey))
                    .apply()
            }
        }

    /** macs explicitly paired from the app, at most MAX_MACS */
    val macs: List<PairedMac>
        get() = synchronized(lock) {
            val array = JSONArray(prefs.getString("macs", "[]"))
            (0 until array.length()).map { i ->
                val mac = array.getJSONObject(i)
                PairedMac(
                    decode(mac.getString("publicKey")),
                    mac.getString("name"),
                    mac.optString("host").ifEmpty { null },
                    mac.optInt("port"),
                    mac.optBoolean("approved"),
                    mac.optString("lastResult").ifEmpty { null },
                    mac.optBoolean("enabled", true),
                )
            }
        }

    fun mac(publicKey: ByteArray): PairedMac? = macs.firstOrNull { it.publicKey.contentEquals(publicKey) }

    fun addMac(endpoint: Endpoint): Boolean = synchronized(lock) {
        val current = macs
        if (current.size >= MAX_MACS || current.any { it.publicKey.contentEquals(endpoint.publicKey) }) {
            return false
        }
        saveMacs(current + PairedMac(endpoint.publicKey, endpoint.name, endpoint.host, endpoint.port))
        true
    }

    fun updateMac(publicKey: ByteArray, transform: (PairedMac) -> PairedMac) = synchronized(lock) {
        saveMacs(macs.map { if (it.publicKey.contentEquals(publicKey)) transform(it) else it })
    }

    fun forgetMac(publicKey: ByteArray) = synchronized(lock) {
        saveMacs(macs.filterNot { it.publicKey.contentEquals(publicKey) })
    }

    private fun saveMacs(macs: List<PairedMac>) {
        val array = JSONArray()
        macs.forEach {
            array.put(
                JSONObject()
                    .put("publicKey", encode(it.publicKey))
                    .put("name", it.name)
                    .put("host", it.host)
                    .put("port", it.port)
                    .put("approved", it.approved)
                    .put("lastResult", it.lastResult)
                    .put("enabled", it.enabled)
            )
        }
        prefs.edit().putString("macs", array.toString()).apply()
    }

    val seenPackages: Set<String>
        get() = prefs.getStringSet("seen", emptySet())!!

    fun markSeen(pkg: String) {
        if (pkg !in seenPackages) {
            prefs.edit().putStringSet("seen", seenPackages + pkg).apply()
        }
    }

    val deniedPackages: Set<String>
        get() = prefs.getStringSet("denied", emptySet())!!

    fun setForwarded(pkg: String, forwarded: Boolean) {
        val denied = if (forwarded) deniedPackages - pkg else deniedPackages + pkg
        prefs.edit().putStringSet("denied", denied).apply()
    }

    private fun encode(bytes: ByteArray) = Base64.getEncoder().encodeToString(bytes)
    private fun decode(text: String) = Base64.getDecoder().decode(text)

    companion object {
        const val MAX_MACS = 3

        /** prefs instances are per component but share the same file, so mac list edits share a lock */
        private val lock = Any()
    }
}
