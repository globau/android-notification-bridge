package au.glob.notificationbridge

import android.content.Context
import android.content.SharedPreferences
import java.util.Base64

class Endpoint(val name: String, val host: String, val port: Int, val publicKey: ByteArray)

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

    /** the mac's public key is pinned the first time one is seen */
    var pinnedMac: ByteArray?
        get() = prefs.getString("macPublic", null)?.let(::decode)
        set(value) = prefs.edit().putString("macPublic", value?.let(::encode)).apply()

    var endpoint: Endpoint?
        get() {
            val key = pinnedMac ?: return null
            val host = prefs.getString("macHost", null) ?: return null
            return Endpoint(prefs.getString("macName", "")!!, host, prefs.getInt("macPort", 0), key)
        }
        set(value) {
            prefs.edit().apply {
                if (value == null) {
                    remove("macHost")
                } else {
                    putString("macName", value.name)
                    putString("macHost", value.host)
                    putInt("macPort", value.port)
                }
            }.apply()
        }

    val macName: String?
        get() = prefs.getString("macName", null)

    /** the mac has accepted this phone; fingerprints are only shown until then */
    var approved: Boolean
        get() = prefs.getBoolean("approved", false)
        set(value) = prefs.edit().putBoolean("approved", value).apply()

    var lastResult: String?
        get() = prefs.getString("lastResult", null)
        set(value) = prefs.edit().putString("lastResult", value).apply()

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

    fun forgetMac() {
        prefs.edit()
            .remove("macPublic")
            .remove("macHost")
            .remove("macName")
            .remove("macPort")
            .remove("approved")
            .apply()
    }

    private fun encode(bytes: ByteArray) = Base64.getEncoder().encodeToString(bytes)
    private fun decode(text: String) = Base64.getDecoder().decode(text)
}
