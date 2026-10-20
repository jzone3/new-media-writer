import AppKit
import SwiftUI

/// One-time "thanks for downloading" sheet on first launch; Let's Write opens the author's X profile.
enum Welcome {
    static let shownKey = "welcomeShown"
    static let repoURL = URL(string: "https://github.com/jzone3/new-media-writer")!
    static let authorURL = URL(string: "https://x.com/imjaredz")!

    static func showIfNeeded(then next: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: shownKey) else { return next() }
        defaults.set(true, forKey: shownKey)

        let finish = {
            NSWorkspace.shared.open(authorURL)
            next()
        }
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        sheet.isReleasedWhenClosed = false
        // The button holds the window itself: no runtime window lookup and no modal loop to stop.
        let host = NSHostingController(rootView: WelcomeView { [weak sheet] in
            guard let sheet else { return }
            if let parent = sheet.sheetParent {
                parent.endSheet(sheet)
            } else {
                sheet.orderOut(nil)
                finish()
            }
        })
        host.sizingOptions = [.preferredContentSize]
        sheet.contentViewController = host
        sheet.setContentSize(host.view.fittingSize)

        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible, window.attachedSheet == nil {
            window.beginSheet(sheet) { _ in finish() }
        } else {
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
        }
    }
}

private struct WelcomeView: View {
    let done: () -> Void

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
                .padding(.bottom, 28)
            HStack(spacing: 10) {
                pill("GitHub", filled: false) { NSWorkspace.shared.open(Welcome.repoURL) }
                pill("Let's Write", filled: true, action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 400)
        .onExitCommand(perform: done)
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(filled ? Color.primary : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(filled ? 0 : 0.25), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
