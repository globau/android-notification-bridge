package au.glob.notificationbridge

import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** mirrors mac/Sources/BridgeCore/Crypto.swift; see testdata/vectors.json */
object Crypto {
    const val PROTOCOL_VERSION: Byte = 1
    private val salt = "notifbridge/1".toByteArray()

    // rfc 8410 der prefixes for raw x25519 keys
    private val publicPrefix = "302a300506032b656e032100".hexToByteArray()
    private val privatePrefix = "302e020100300506032b656e04220420".hexToByteArray()
    private val random = SecureRandom()

    class KeyPair(val privateKey: ByteArray, val publicKey: ByteArray)

    fun generateKeyPair(): KeyPair {
        // conscrypt rejects any parameter spec; both it and the jdk default to x25519
        val pair = KeyPairGenerator.getInstance("XDH").generateKeyPair()
        val private = pair.private.encoded
        val public = pair.public.encoded
        require(private.startsWith(privatePrefix) && public.startsWith(publicPrefix)) {
            "unexpected x25519 key encoding"
        }
        return KeyPair(
            private.copyOfRange(privatePrefix.size, privatePrefix.size + 32),
            public.copyOfRange(publicPrefix.size, publicPrefix.size + 32),
        )
    }

    fun dh(privateKey: ByteArray, publicKey: ByteArray): ByteArray {
        val factory = KeyFactory.getInstance("XDH")
        return KeyAgreement.getInstance("XDH").run {
            init(factory.generatePrivate(PKCS8EncodedKeySpec(privatePrefix + privateKey)))
            doPhase(factory.generatePublic(X509EncodedKeySpec(publicPrefix + publicKey)), true)
            generateSecret()
        }
    }

    /** ikm = dh(phone static, mac static) || dh(phone ephemeral, mac static) */
    fun sessionKey(phone: KeyPair, ephemeral: KeyPair, macPublic: ByteArray): ByteArray {
        val ikm = dh(phone.privateKey, macPublic) + dh(ephemeral.privateKey, macPublic)
        return hkdf(ikm, phone.publicKey + ephemeral.publicKey + macPublic)
    }

    private fun hkdf(ikm: ByteArray, info: ByteArray): ByteArray {
        val prk = hmac(salt, ikm)
        return hmac(prk, info + 1.toByte())
    }

    private fun hmac(key: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(data)
        }

    /** sealed layout: nonce (12) || ciphertext || tag (16) */
    fun seal(plaintext: ByteArray, key: ByteArray, nonce: ByteArray = ByteArray(12).also(random::nextBytes)): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        return nonce + cipher.doFinal(plaintext)
    }

    fun hello(phonePublic: ByteArray, ephemeralPublic: ByteArray, deviceName: String): ByteArray =
        byteArrayOf(PROTOCOL_VERSION) + phonePublic + ephemeralPublic + deviceName.toByteArray()

    fun fingerprint(publicKey: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(publicKey)
            .copyOf(6)
            .toHexString(HexFormat.UpperCase)
            .chunked(4)
            .joinToString("-")

    private fun ByteArray.startsWith(prefix: ByteArray) =
        size >= prefix.size && copyOf(prefix.size).contentEquals(prefix)
}
