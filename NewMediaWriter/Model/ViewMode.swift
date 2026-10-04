import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable, Codable {
    case markdown, raw, xPost, xArticle, linkedin, slack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .raw: "Raw Markdown"
        case .xPost: "X Post"
        case .xArticle: "X Article"
        case .linkedin: "LinkedIn"
        case .slack: "Slack"
        }
    }

    var isEditor: Bool { self == .markdown || self == .raw }
    var isX: Bool { self == .xPost || self == .xArticle }
}

struct ViewModeFocusedKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeFocusedKey.self] }
        set { self[ViewModeFocusedKey.self] = newValue }
    }
}

struct ViewCommands: Commands {
    @FocusedValue(\.viewMode) private var viewMode

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Markdown") { viewMode?.wrappedValue = .markdown }
                .keyboardShortcut("1", modifiers: .command)
            Button("Raw Markdown") { viewMode?.wrappedValue = .raw }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Divider()
            Button("X Post") { viewMode?.wrappedValue = .xPost }
                .keyboardShortcut("2", modifiers: .command)
            Button("X Article") { viewMode?.wrappedValue = .xArticle }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            Button("LinkedIn") { viewMode?.wrappedValue = .linkedin }
                .keyboardShortcut("3", modifiers: .command)
            Button("Slack") { viewMode?.wrappedValue = .slack }
                .keyboardShortcut("4", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy for Current View") {
                NotificationCenter.default.post(name: .copyForCurrentView, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(viewMode == nil)
        }
    }
}
