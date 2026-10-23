import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct Vectors: Decodable {
    let phoneStaticPrivate: String
    let phoneStaticPublic: String
    let phoneEphemeralPublic: String
    let macStaticPrivate: String
    let macStaticPublic: String
    let sessionKey: String
    let nonce: String
    let plaintext: String
    let sealed: String

    static func load() throws -> Vectors {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../testdata/vectors.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }
}

extension Data {
    init(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

@Test func macDerivesSharedSessionKey() throws {
    let v = try Vectors.load()
    let mac = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v.macStaticPrivate))
    #expect(mac.publicKey.rawRepresentation == Data(hex: v.macStaticPublic))
    let key = try BridgeCrypto.macSessionKey(
        macKey: mac,
        phonePublic: Data(hex: v.phoneStaticPublic),
        ephemeralPublic: Data(hex: v.phoneEphemeralPublic)
    )
    #expect(key.rawData == Data(hex: v.sessionKey))
}

@Test func sealMatchesVector() throws {
    let v = try Vectors.load()
    let key = SymmetricKey(data: Data(hex: v.sessionKey))
    let sealed = try BridgeCrypto.seal(Data(v.plaintext.utf8), key: key, nonce: Data(hex: v.nonce))
    #expect(sealed == Data(hex: v.sealed))
}

@Test func openVectorDecodesMessage() throws {
    let v = try Vectors.load()
    let key = SymmetricKey(data: Data(hex: v.sessionKey))
    let plaintext = try BridgeCrypto.open(Data(hex: v.sealed), key: key)
    let message = try JSONDecoder().decode(Message.self, from: plaintext)
    #expect(message.type == .posted)
    #expect(message.appName == "Example")
    #expect(message.title == "Hello")
}

@Test func tamperedCiphertextFails() throws {
    let v = try Vectors.load()
    var sealed = Data(hex: v.sealed)
    sealed[20] ^= 1
    #expect(throws: (any Error).self) {
        try BridgeCrypto.open(sealed, key: SymmetricKey(data: Data(hex: v.sessionKey)))
    }
}

@Test func helloParses() throws {
    let v = try Vectors.load()
    let payload = Data([BridgeCrypto.protocolVersion]) + Data(hex: v.phoneStaticPublic)
        + Data(hex: v.phoneEphemeralPublic) + Data("Pixel".utf8)
    let hello = try #require(Hello(payload))
    #expect(hello.phonePublic == Data(hex: v.phoneStaticPublic))
    #expect(hello.deviceName == "Pixel")
    #expect(Hello(Data([2]) + payload.dropFirst()) == nil)
}

@Test func fingerprintFormat() throws {
    let v = try Vectors.load()
    #expect(BridgeCrypto.fingerprint(Data(hex: v.macStaticPublic)) == "384C-C8E5-9332")
}
