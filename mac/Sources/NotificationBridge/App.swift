import BridgeCore
import CryptoKit
import ServiceManagement
import SwiftUI

@MainActor
final class Bridge: ObservableObject {
    @Published var listening = false
    @Published var trusted = Store.trusted
    @Published var pending: [Phone] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    let fingerprint: String

    private let notifier = Notifier()
    private let messageWindow = MessageWindow()
    private let aboutWindow = AboutWindow()
    private var listener: Listener?
    private var buffered: [Data: [Message]] = [:]

    init() {
        let identity: Curve25519.KeyAgreement.PrivateKey
        do {
            identity = try Store.identity()
        } catch {
            fatalError("cannot load identity: \(error)")
        }
        fingerprint = BridgeCrypto.fingerprint(identity.publicKey.rawRepresentation)
        notifier.onPairingDecision = { [weak self] key, allow in
            MainActor.assumeIsolated { self?.decide(key, allow: allow) }
        }
        notifier.onOpen = { [weak self] details in
            MainActor.assumeIsolated { self?.messageWindow.show(details) }
        }
        listener = Listener(
            identity: identity,
            onState: { [weak self] ready in
                MainActor.assumeIsolated { self?.listening = ready }
            },
            onMessage: { [weak self] phone, message in
                MainActor.assumeIsolated { self?.receive(message, from: phone) ?? .rejected }
            }
        )
        listener?.start()
    }

    private func receive(_ message: Message, from phone: Phone) -> Status {
        if Store.denied.contains(where: { $0.publicKey == phone.publicKey }) {
            return .denied
        }
        guard let index = trusted.firstIndex(where: { $0.publicKey == phone.publicKey }) else {
            if !pending.contains(where: { $0.publicKey == phone.publicKey }) {
                pending.append(phone)
                notifier.requestPairing(phone)
            }
            buffered[phone.publicKey, default: []].append(message)
            return .pending
        }
        if trusted[index].name != phone.name {
            trusted[index].name = phone.name
            Store.trusted = trusted
        }
        deliver(message, from: phone)
        return .delivered
    }

    private func deliver(_ message: Message, from phone: Phone) {
        switch message.type {
        case .posted:
            notifier.post(message, from: phone)
        case .removed:
            notifier.remove(message, from: phone)
        }
    }

    func decide(_ publicKey: Data, allow: Bool) {
        guard let index = pending.firstIndex(where: { $0.publicKey == publicKey }) else { return }
        let phone = pending.remove(at: index)
        notifier.clearPairing(phone)
        let messages = buffered.removeValue(forKey: publicKey) ?? []
        if allow {
            trusted.append(phone)
            Store.trusted = trusted
            messages.forEach { deliver($0, from: phone) }
        } else {
            Store.denied.append(phone)
        }
    }

    func forget(_ phone: Phone) {
        trusted.removeAll { $0.publicKey == phone.publicKey }
        Store.trusted = trusted
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch at login: \(error, privacy: .public)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func showAbout() {
        aboutWindow.show()
    }
}

@main
struct NotificationBridgeApp: App {
    @StateObject private var bridge = Bridge()

    var body: some Scene {
        MenuBarExtra {
            BridgeMenu(bridge: bridge)
        } label: {
            Image(nsImage: menuBarIcon)
        }
    }
}

private let menuBarIcon: NSImage = {
    let image = NSImage(named: "MenuBarIcon")
        ?? NSImage(systemSymbolName: "iphone.radiowaves.left.and.right", accessibilityDescription: nil)!
    image.isTemplate = true
    return image
}()

struct BridgeMenu: View {
    @ObservedObject var bridge: Bridge

    var body: some View {
        Text(bridge.listening ? "Listening" : "Not listening")
        if !bridge.pending.isEmpty {
            Divider()
            Text("This Mac: \(bridge.fingerprint)")
            ForEach(bridge.pending) { phone in
                Menu("Pair \(phone.name) (\(phone.fingerprint))") {
                    Button("Allow") { bridge.decide(phone.publicKey, allow: true) }
                    Button("Deny") { bridge.decide(phone.publicKey, allow: false) }
                }
            }
        }

        Divider()
        Toggle(
            "Launch at Login",
            isOn: Binding(get: { bridge.launchAtLogin }, set: { bridge.setLaunchAtLogin($0) }))
        if !bridge.trusted.isEmpty {
            Menu("Paired Phones") {
                ForEach(bridge.trusted) { phone in
                    Button("Forget \"\(phone.name)\"") { bridge.forget(phone) }
                }
            }
        }
        Divider()
        Button("About Notification Bridge") { bridge.showAbout() }
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
