import AppKit
import SwiftUI

@MainActor
final class AboutWindow {
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        // activation is only a request for an accessory app, so force the window above others regardless
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingView(rootView: AboutView())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.contentView = content
        window.title = "About Notification Bridge"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        return window
    }
}

private struct AboutView: View {
    private static let repo = URL(string: "https://github.com/globau/android-notification-bridge")!

    private var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Notification Bridge"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(name)
                .font(.title2.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Link("github.com/globau/android-notification-bridge", destination: Self.repo)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
