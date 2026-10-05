import AppKit
import UniformTypeIdentifiers

enum DefaultApp {
    static let promptedKey = "defaultAppPrompted"
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    static var isDefault: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: markdown) else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault(completion: ((Error?) -> Void)? = nil) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdown) { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }

    static func promptIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: promptedKey), !isDefault else { return }
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            DefaultApp.promptIfNeeded()
        }
    }
}
