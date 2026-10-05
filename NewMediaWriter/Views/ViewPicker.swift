import SwiftUI

extension ViewMode {
    /// Extra words the ⌘K picker matches besides the title.
    var searchTerms: [String] {
        switch self {
        case .plaintext: ["plaintext", "plain", "raw", "text", "txt", "source"]
        case .markdown: ["markdown", "md", "wysiwyg", "rich"]
        case .xPost: ["x", "twitter", "tweet", "post", "thread"]
        case .linkedin: ["linkedin", "li", "in"]
        case .slack: ["slack", "channel", "message"]
        }
    }

    /// Lower is better; nil means no match. Exact alias ("x") beats a prefix ("sl") beats a substring inside the title.
    func matchRank(_ query: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return 0 }
        if searchTerms.contains(q) { return 1 }
        if searchTerms.contains(where: { $0.hasPrefix(q) }) { return 2 }
        if title.lowercased().contains(q) { return 3 }
        return nil
    }
}

struct ViewPickerFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var viewPickerShown: Binding<Bool>? {
        get { self[ViewPickerFocusedKey.self] }
        set { self[ViewPickerFocusedKey.self] = newValue }
    }
}

/// Spotlight-style switcher: ⌘K, type "sl", return.
struct ViewPicker: View {
    @Binding var mode: ViewMode
    @Binding var shown: Bool
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var results: [ViewMode] {
        ViewMode.allCases
            .compactMap { m in m.matchRank(query).map { (m, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { shown = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Switch view…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($focused)
                        .onSubmit(pick)
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.escape) { shown = false; return .handled }
                        .onKeyPress(.tab) { move(1); return .handled }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)

                Divider()

                if results.isEmpty {
                    Text("No view matches “\(query)”")
                        .foregroundStyle(.secondary)
                        .padding(14)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element) { i, m in
                            row(m, selected: i == selection)
                                .contentShape(Rectangle())
                                .onTapGesture { mode = m; shown = false }
                                .onHover { if $0 { selection = i } }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 400)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .padding(.top, 72)
        }
        .onAppear {
            query = ""
            selection = 0
            // The editor's NSTextView keeps first responder otherwise, so keystrokes would edit the document.
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func row(_ m: ViewMode, selected: Bool) -> some View {
        HStack {
            Text(m.title).font(.system(size: 14, weight: .medium))
            if m == mode {
                Text("current").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(m.shortcutLabel).font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func pick() {
        guard results.indices.contains(selection) else { return }
        mode = results[selection]
        shown = false
    }
}
