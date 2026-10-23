// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotificationBridge",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BridgeCore"),
        .executableTarget(name: "NotificationBridge", dependencies: ["BridgeCore"]),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
