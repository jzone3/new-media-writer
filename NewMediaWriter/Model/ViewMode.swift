import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable, Codable {
    case plaintext, markdown, xPost, linkedin, slack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plaintext: "Plaintext"
        case .markdown: "Markdown"
        case .xPost: "X"
        case .linkedin: "LinkedIn"
        case .slack: "Slack"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .plaintext: "1"
        case .markdown: "2"
        case .xPost: "3"
        case .linkedin: "4"
        case .slack: "5"
        }
    }

    var shortcutLabel: String { "⌘\(shortcut.character)" }

    var isEditor: Bool { self == .markdown || self == .plaintext }

    private static let lastUsedKey = "viewMode"

    static var lastUsed: ViewMode {
        get { UserDefaults.standard.string(forKey: lastUsedKey).flatMap(ViewMode.init(rawValue:)) ?? .markdown }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastUsedKey) }
    }
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
    @FocusedValue(\.viewPickerShown) private var viewPickerShown

    private func step(_ delta: Int) {
        guard let viewMode else { return }
        let all = ViewMode.allCases
        let i = all.firstIndex(of: viewMode.wrappedValue) ?? 0
        viewMode.wrappedValue = all[(i + delta + all.count) % all.count]
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(ViewMode.allCases) { m in
                Button(m.title) { viewMode?.wrappedValue = m }
                    .keyboardShortcut(m.shortcut, modifiers: .command)
            }
            Divider()
            Button("Switch View…") { viewPickerShown?.wrappedValue.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(viewPickerShown == nil)
            Button("Previous View") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(viewMode == nil)
            Button("Next View") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(viewMode == nil)
        }
        CommandGroup(replacing: .textFormatting) {
            Button("Bold") { send(Selector(("toggleBoldface:"))) }.keyboardShortcut("b", modifiers: .command)
            Button("Italic") { send(Selector(("toggleItalics:"))) }.keyboardShortcut("i", modifiers: .command)
            Button("Inline Code") { send(#selector(EditorTextView.toggleInlineCode(_:))) }.keyboardShortcut("e", modifiers: .command)
            Button("Link") { send(#selector(EditorTextView.insertLink(_:))) }.keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Bulleted List") { send(#selector(EditorTextView.toggleBulletedList(_:))) }.keyboardShortcut("u", modifiers: [.command, .option])
            Button("Numbered List") { send(#selector(EditorTextView.toggleNumberedList(_:))) }.keyboardShortcut("o", modifiers: [.command, .option])
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy for Current View") {
                NotificationCenter.default.post(name: .copyForCurrentView, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(viewMode == nil)
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
