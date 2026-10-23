import BridgeCore
import CryptoKit
import Foundation
import Network
import os

let log = Logger(subsystem: "au.glob.NotificationBridge", category: "bridge")

/// advertises the bonjour service and decodes framed, encrypted messages from phones.
/// everything runs on the main queue; traffic is tiny.
final class Listener {
    typealias Handler = (Phone, Message) -> Status

    private let identity: Curve25519.KeyAgreement.PrivateKey
    private let onMessage: Handler
    private let onState: (Bool) -> Void
    private var listener: NWListener?

    init(
        identity: Curve25519.KeyAgreement.PrivateKey,
        onState: @escaping (Bool) -> Void,
        onMessage: @escaping Handler
    ) {
        self.identity = identity
        self.onState = onState
        self.onMessage = onMessage
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp)
            let txt = NWTXTRecord(["pk": identity.publicKey.rawRepresentation.base64EncodedString()])
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac", type: serviceType, txtRecord: txt)
            listener.stateUpdateHandler = { [weak self] state in
                log.info("listener state \(String(describing: state), privacy: .public)")
                switch state {
                case .ready:
                    self?.onState(true)
                case .failed:
                    self?.onState(false)
                    self?.restart()
                case .cancelled:
                    self?.onState(false)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            log.error("listener failed: \(error, privacy: .public)")
            onState(false)
            restart()
        }
    }

    private func restart() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.start() }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        readFrame(connection) { [weak self] payload in
            guard let self, let hello = Hello(payload) else {
                connection.cancel()
                return
            }
            do {
                let key = try BridgeCrypto.macSessionKey(
                    macKey: self.identity, phonePublic: hello.phonePublic, ephemeralPublic: hello.ephemeralPublic)
                let phone = Phone(publicKey: hello.phonePublic, name: hello.deviceName)
                self.readMessages(connection, phone: phone, key: key)
            } catch {
                log.error("handshake failed: \(error, privacy: .public)")
                connection.cancel()
            }
        }
    }

    private func readMessages(_ connection: NWConnection, phone: Phone, key: SymmetricKey) {
        readFrame(connection) { [weak self] sealed in
            guard let self else { return }
            let status: Status
            do {
                let message = try JSONDecoder().decode(Message.self, from: BridgeCrypto.open(sealed, key: key))
                if abs(message.date.timeIntervalSinceNow) > 300 {
                    log.error("stale message from \(phone.name, privacy: .public)")
                    status = .rejected
                } else {
                    status = self.onMessage(phone, message)
                }
            } catch {
                log.error("bad message from \(phone.name, privacy: .public): \(error, privacy: .public)")
                status = .rejected
            }
            if status == .rejected || status == .denied {
                connection.send(
                    content: Data([status.rawValue]), completion: .contentProcessed { _ in connection.cancel() })
            } else {
                connection.send(content: Data([status.rawValue]), completion: .contentProcessed { _ in })
                self.readMessages(connection, phone: phone, key: key)
            }
        }
    }

    /// frame: u32 big endian length || payload
    private func readFrame(_ connection: NWConnection, completion: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, header.count == 4 else {
                connection.cancel()
                return
            }
            let length = header.reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= maxFrameLength else {
                connection.cancel()
                return
            }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { payload, _, _, error in
                guard error == nil, let payload, payload.count == length else {
                    connection.cancel()
                    return
                }
                completion(payload)
            }
        }
    }
}
