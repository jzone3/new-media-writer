import AppKit
import SwiftUI

/// One-time "thanks for downloading" sheet on first launch; OK opens the author's X profile.
enum Welcome {
    static let shownKey = "welcomeShown"
    static let repoURL = URL(string: "https://github.com/jzone3/new-media-writer")!
    static let authorURL = URL(string: "https://x.com/imjaredz")!

    static func showIfNeeded(then next: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: shownKey) else { return next() }
        defaults.set(true, forKey: shownKey)

        let host = NSHostingController(rootView: WelcomeView())
        host.sizingOptions = [.preferredContentSize]
        let sheet = NSWindow(contentViewController: host)
        sheet.setContentSize(host.view.fittingSize)
        sheet.styleMask = [.titled, .fullSizeContentView]
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        let finish = {
            NSWorkspace.shared.open(authorURL)
            next()
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            window.beginSheet(sheet) { _ in finish() }
        } else {
            sheet.center()
            NSApp.runModal(for: sheet)
            sheet.orderOut(nil)
            finish()
        }
    }

    static func dismiss(_ window: NSWindow?) {
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            NSApp.stopModal()
        }
    }
}

private struct WelcomeView: View {
    @State private var window: NSWindow?
    @State private var hoveringLink = false

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .padding(.bottom, 18)
            Text("Thanks for downloading\nNew Media Writer")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            Text("I built this with Devin, Cognition's AI software engineer. The whole thing is open source.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            Button {
                NSWorkspace.shared.open(Welcome.repoURL)
            } label: {
                Text("github.com/jzone3/new-media-writer")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .underline(hoveringLink)
                    .foregroundStyle(hoveringLink ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .onHover { hoveringLink = $0 }
            .padding(.bottom, 28)
            Button {
                Welcome.dismiss(window)
            } label: {
                Text("OK")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 400)
        .background(WindowReader { window = $0 })
    }
}

private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { found(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
