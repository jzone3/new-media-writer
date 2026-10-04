import SwiftUI

@main
struct NewMediaWriterApp: App {
    init() { ScrollPassthrough.install() }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { config in
            ContentView(document: config.document, fileURL: config.fileURL)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 980, height: 760)
        .commands {
            ViewCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
