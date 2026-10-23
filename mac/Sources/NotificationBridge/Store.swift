import BridgeCore
import CryptoKit
import Foundation

struct Phone: Codable, Hashable, Identifiable {
    let publicKey: Data
    var name: String

    var id: Data { publicKey }
    var fingerprint: String { BridgeCrypto.fingerprint(publicKey) }
}

enum Store {
    private static let defaults = UserDefaults.standard

    static func identity() throws -> Curve25519.KeyAgreement.PrivateKey {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "NotificationBridge")
        let file = dir.appending(path: "identity.key")
        if let data = try? Data(contentsOf: file) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: file.path, contents: key.rawRepresentation, attributes: [.posixPermissions: 0o600])
        return key
    }

    static var trusted: [Phone] {
        get { load("trustedPhones") }
        set { save(newValue, "trustedPhones") }
    }

    static var denied: [Phone] {
        get { load("deniedPhones") }
        set { save(newValue, "deniedPhones") }
    }

    static var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }

    private static func load(_ key: String) -> [Phone] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Phone].self, from: data)) ?? []
    }

    private static func save(_ phones: [Phone], _ key: String) {
        defaults.set(try? JSONEncoder().encode(phones), forKey: key)
    }
}
