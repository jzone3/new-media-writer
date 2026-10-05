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

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Launching with nothing to open starts an Untitled document, not DocumentGroup's Open panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.newDocument(nil)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // SwiftUI may still have put up its Open panel; swap it for an Untitled document.
            if NSDocumentController.shared.documents.isEmpty {
                NSApp.windows.compactMap { $0 as? NSOpenPanel }.forEach { $0.cancel(nil) }
                NSDocumentController.shared.newDocument(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            DefaultApp.promptIfNeeded()
        }
    }
}
