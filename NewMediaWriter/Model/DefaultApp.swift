import AppKit
import UniformTypeIdentifiers

enum DefaultApp {
    // Bumped when the prompt was unreachable in shipped builds (hidden behind the launch Open panel), so those users get asked once.
    static let promptedKey = "defaultAppPrompted.2"
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)

    /// True when running from a mounted disk image or an App Translocation
    /// sandbox; registering that copy would break once the volume is ejected.
    static var isRunningFromTemporaryLocation: Bool {
        let url = Bundle.main.bundleURL.resolvingSymlinksInPath()
        if url.path.hasPrefix("/Volumes/") || url.path.contains("/AppTranslocation/") { return true }
        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeIsEjectableKey])
        return values?.volumeIsReadOnly == true || values?.volumeIsEjectable == true
    }

    static var isDefault: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: markdown) else { return false }
        return current.resolvingSymlinksInPath().path == Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    static func makeDefault(completion: ((Error?) -> Void)? = nil) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdown) { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }

    static func promptIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: promptedKey), !isDefault, !isRunningFromTemporaryLocation else { return }
        defaults.set(true, forKey: promptedKey)

        let alert = NSAlert()
        alert.messageText = "Open Markdown files in New Media Writer?"
        alert.informativeText = "Make New Media Writer the default app for .md files. You can change this any time in Settings."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            makeDefault()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Dock click with no windows open: a new Untitled document instead of DocumentGroup's Open panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        NSDocumentController.shared.newDocument(nil)
        return false
    }

    /// ⌘V with no focused editor (end of the responder chain): focus the key window's editor and paste there.
    /// Windows without an editor (Settings, panels) leave Paste disabled, as before.
    private var keyWindowEditor: EditorTextView? {
        guard let root = NSApp.keyWindow?.contentView else { return nil }
        return EditorTextView.firstVisible(in: root)
    }

    @objc func paste(_ sender: Any?) {
        guard let editor = keyWindowEditor, let window = editor.window else { return }
        window.makeFirstResponder(editor)
        editor.paste(sender)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(paste(_:)) ? keyWindowEditor != nil : true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // DocumentGroup opens its Open panel when launched with nothing to open (and ignores
        // applicationShouldOpenUntitledFile). Swap that launch panel for an Untitled document; a
        // launch with a file never shows the panel, so nothing happens then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard NSDocumentController.shared.documents.isEmpty,
                  let panel = NSApp.windows.first(where: { $0 is NSOpenPanel }) as? NSOpenPanel else { return }
            panel.cancel(nil)
            NSDocumentController.shared.newDocument(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            Welcome.showIfNeeded()
            DefaultApp.promptIfNeeded()
        }
        UpdateChecker.shared.checkOnLaunch()
    }
}
