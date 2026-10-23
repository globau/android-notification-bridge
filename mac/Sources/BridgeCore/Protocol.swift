import Foundation

public let serviceType = "_notifbridge._tcp"
public let maxFrameLength = 64 * 1024

/// hello payload: version (1) || phone static public (32) || ephemeral public (32) || device name (utf8)
public struct Hello {
    public let phonePublic: Data
    public let ephemeralPublic: Data
    public let deviceName: String

    public init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 65, bytes[0] == BridgeCrypto.protocolVersion else { return nil }
        phonePublic = Data(bytes[1..<33])
        ephemeralPublic = Data(bytes[33..<65])
        deviceName = String(decoding: bytes[65...], as: UTF8.self)
    }
}

/// one status byte is written back for every message frame
public enum Status: UInt8 {
    case delivered = 0
    case pending = 1
    case denied = 2
    case rejected = 3
}

public struct Message: Codable, Equatable {
    public enum Kind: String, Codable {
        case posted
        case removed
    }

    public let type: Kind
    public let key: String
    public var package: String?
    public var appName: String?
    public var title: String?
    public var text: String?
    public let ts: Int64

    public var date: Date { Date(timeIntervalSince1970: Double(ts) / 1000) }
}
