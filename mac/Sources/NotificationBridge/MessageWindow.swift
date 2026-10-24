import AppKit
import SwiftUI

struct MessageDetails {
    let appName: String
    let title: String
    let text: String
    let phoneName: String
    let date: Date
}

/// shows a clicked notification in a window, so its text can be selected and copied
@MainActor
final class MessageWindow {
    private var window: NSWindow?

    func show(_ details: MessageDetails) {
        let window = self.window ?? makeWindow()
        window.title = details.appName
        window.contentView = NSHostingView(rootView: MessageView(details: details))
        // activation is only a request for an accessory app, so force the window above others regardless
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = EscapableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        return window
    }
}

/// closes on escape
private final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private struct MessageView: View {
    let details: MessageDetails

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(details.phoneName), \(details.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !details.title.isEmpty {
                    Text(details.title)
                        .font(.headline)
                }
                Text(details.text)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(minWidth: 300, minHeight: 120)
    }
}
