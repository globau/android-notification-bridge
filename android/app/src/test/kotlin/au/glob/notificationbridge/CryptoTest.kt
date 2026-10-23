package au.glob.notificationbridge

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class CryptoTest {
    private val vectors = JSONObject(File("../../testdata/vectors.json").readText())

    private fun bytes(name: String) = vectors.getString(name).hexToByteArray()

    private val phone = Crypto.KeyPair(bytes("phoneStaticPrivate"), bytes("phoneStaticPublic"))
    private val ephemeral = Crypto.KeyPair(bytes("phoneEphemeralPrivate"), bytes("phoneEphemeralPublic"))

    @Test
    fun phoneDerivesSharedSessionKey() {
        val key = Crypto.sessionKey(phone, ephemeral, bytes("macStaticPublic"))
        assertArrayEquals(bytes("sessionKey"), key)
    }

    @Test
    fun sealMatchesVector() {
        val sealed = Crypto.seal(vectors.getString("plaintext").toByteArray(), bytes("sessionKey"), bytes("nonce"))
        assertArrayEquals(bytes("sealed"), sealed)
    }

    @Test
    fun dhIsSymmetric() {
        val a = Crypto.generateKeyPair()
        val b = Crypto.generateKeyPair()
        assertArrayEquals(Crypto.dh(a.privateKey, b.publicKey), Crypto.dh(b.privateKey, a.publicKey))
    }

    @Test
    fun fingerprintMatchesMac() {
        assertEquals("384C-C8E5-9332", Crypto.fingerprint(bytes("macStaticPublic")))
    }
}
