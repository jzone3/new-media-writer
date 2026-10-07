import AppKit

/// One-time "thanks for downloading" note on first launch; OK opens the author's X profile.
enum Welcome {
    static let shownKey = "welcomeShown"
    static let repoURL = URL(string: "https://github.com/jzone3/new-media-writer")!
    static let authorURL = URL(string: "https://x.com/imjaredz")!

    static func showIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: shownKey) else { return }
        defaults.set(true, forKey: shownKey)

        let alert = NSAlert()
        alert.messageText = "Thanks for downloading New Media Writer"
        alert.accessoryView = description()
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSWorkspace.shared.open(authorURL)
    }

    /// NSAlert's informative text can't hold a link, so the description is a read-only text view.
    private static func description() -> NSView {
        let text = NSMutableAttributedString(
            string: "I built this with Devin, Cognition's AI software engineer.\nThe source is open: ",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: repoURL.absoluteString.replacingOccurrences(of: "https://", with: ""),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .link: repoURL]
        ))
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 48))
        view.textStorage?.setAttributedString(text)
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.alignment = .center
        view.sizeToFit()
        return view
    }
}
