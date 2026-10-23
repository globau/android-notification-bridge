import BridgeCore
import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let pairingCategory = "pairing"
    private static let allowAction = "allow"
    private static let denyAction = "deny"

    private let center = UNUserNotificationCenter.current()
    var onPairingDecision: ((Data, Bool) -> Void)?

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.pairingCategory,
                actions: [
                    UNNotificationAction(identifier: Self.allowAction, title: "Allow"),
                    UNNotificationAction(identifier: Self.denyAction, title: "Deny", options: .destructive),
                ],
                intentIdentifiers: []
            )
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted {
                log.error("notification permission not granted: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func post(_ message: Message, from phone: Phone) {
        let content = UNMutableNotificationContent()
        let appName = message.appName ?? message.package ?? phone.name
        if let title = message.title, !title.isEmpty {
            content.title = title
            content.subtitle = appName
        } else {
            content.title = appName
        }
        content.body = message.text ?? ""
        content.sound = .default
        content.threadIdentifier = message.package ?? appName
        center.add(UNNotificationRequest(identifier: identifier(message, phone), content: content, trigger: nil))
    }

    func remove(_ message: Message, from phone: Phone) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier(message, phone)])
    }

    func requestPairing(_ phone: Phone) {
        let content = UNMutableNotificationContent()
        content.title = "Allow \(phone.name)?"
        content.body = "Forward notifications from this phone. Fingerprint \(phone.fingerprint)"
        content.categoryIdentifier = Self.pairingCategory
        content.userInfo = ["publicKey": phone.publicKey.base64EncodedString()]
        content.sound = .default
        center.add(UNNotificationRequest(identifier: pairingIdentifier(phone), content: content, trigger: nil))
    }

    func clearPairing(_ phone: Phone) {
        center.removeDeliveredNotifications(withIdentifiers: [pairingIdentifier(phone)])
    }

    private func identifier(_ message: Message, _ phone: Phone) -> String {
        "\(phone.fingerprint):\(message.key)"
    }

    private func pairingIdentifier(_ phone: Phone) -> String {
        "pairing:\(phone.fingerprint)"
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let content = response.notification.request.content
        guard content.categoryIdentifier == Self.pairingCategory,
            let encoded = content.userInfo["publicKey"] as? String,
            let publicKey = Data(base64Encoded: encoded)
        else { return }
        switch response.actionIdentifier {
        case Self.allowAction:
            DispatchQueue.main.async { self.onPairingDecision?(publicKey, true) }
        case Self.denyAction:
            DispatchQueue.main.async { self.onPairingDecision?(publicKey, false) }
        default:
            break
        }
    }
}
