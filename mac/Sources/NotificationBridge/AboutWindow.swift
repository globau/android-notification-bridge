import AppKit
import SwiftUI

@MainActor
final class AboutWindow {
    private var window: NSWindow?
    private var cracktro: CracktroView?
    private var aboutFrame: NSRect?

    func show() {
        let window = self.window ?? makeWindow()
        // activation is only a request for an accessory app, so force the window above others regardless
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let content = aboutContent()
        let window = ClosingWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.contentView = content
        window.title = "About Notification Bridge"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.onClose = { [weak self] in self?.stopCracktro() }
        window.center()
        return window
    }

    private func aboutContent() -> NSView {
        NSHostingView(rootView: AboutView(onIconClick: { [weak self] in self?.startCracktro() }))
    }

    private func startCracktro() {
        guard let window, cracktro == nil else { return }
        let view = CracktroView()
        view.onExit = { [weak self] in self?.stopCracktro() }
        cracktro = view
        aboutFrame = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: CracktroView.size))
        frame.origin = NSPoint(x: window.frame.midX - frame.width / 2, y: window.frame.midY - frame.height / 2)
        window.contentView = view
        window.setFrame(frame, display: true, animate: true)
        window.makeFirstResponder(view)
        view.start()
    }

    private func stopCracktro() {
        guard let window, let cracktro else { return }
        cracktro.stop()
        self.cracktro = nil
        // shrink before swapping the content back, so the hosting view's size constraints don't snap the window
        if let aboutFrame {
            window.setFrame(aboutFrame, display: true, animate: window.isVisible)
        }
        window.contentView = aboutContent()
    }
}

private final class ClosingWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        super.close()
        onClose?()
    }
}

private struct AboutView: View {
    private static let repo = URL(string: "https://github.com/globau/android-notification-bridge")!

    let onIconClick: () -> Void

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
                .onTapGesture(perform: onIconClick)
            Text(name)
                .font(.title2.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Link("github.com/globau/android-notification-bridge", destination: Self.repo)
                .focusEffectDisabled()
                .padding(.top, 4)
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
