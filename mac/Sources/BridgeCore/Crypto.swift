import CryptoKit
import Foundation

public enum BridgeCrypto {
    public static let protocolVersion: UInt8 = 1
    static let salt = Data("notifbridge/1".utf8)

    /// session key shared by phone and mac for one connection.
    /// ikm = dh(phone static, mac static) || dh(phone ephemeral, mac static)
    public static func sessionKey(
        staticSecret: Data,
        ephemeralSecret: Data,
        phonePublic: Data,
        ephemeralPublic: Data,
        macPublic: Data
    ) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: staticSecret + ephemeralSecret),
            salt: salt,
            info: phonePublic + ephemeralPublic + macPublic,
            outputByteCount: 32
        )
    }

    public static func macSessionKey(
        macKey: Curve25519.KeyAgreement.PrivateKey,
        phonePublic: Data,
        ephemeralPublic: Data
    ) throws -> SymmetricKey {
        let phone = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: phonePublic)
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublic)
        return sessionKey(
            staticSecret: try macKey.sharedSecretFromKeyAgreement(with: phone).rawData,
            ephemeralSecret: try macKey.sharedSecretFromKeyAgreement(with: ephemeral).rawData,
            phonePublic: phonePublic,
            ephemeralPublic: ephemeralPublic,
            macPublic: macKey.publicKey.rawRepresentation
        )
    }

    /// sealed layout: nonce (12) || ciphertext || tag (16)
    public static func seal(_ plaintext: Data, key: SymmetricKey, nonce: Data? = nil) throws -> Data {
        let n = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        return try AES.GCM.seal(plaintext, using: key, nonce: n).combined!
    }

    public static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }

    /// short human-comparable fingerprint, shown on both devices during pairing
    public static func fingerprint(_ publicKey: Data) -> String {
        let hex = SHA256.hash(data: publicKey).prefix(6).map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return String(hex[start..<hex.index(start, offsetBy: 4)])
        }.joined(separator: "-")
    }
}

extension SharedSecret {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}

extension SymmetricKey {
    public var rawData: Data { withUnsafeBytes { Data($0) } }
}
