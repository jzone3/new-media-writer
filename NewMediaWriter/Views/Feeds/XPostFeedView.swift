import SwiftUI

enum XTheme {
    static let blue = Color(hex: 0x1D9BF0)
    static let text = Color.adaptive(light: 0x0F1419, dark: 0xE7E9EA)
    static let secondary = Color.adaptive(light: 0x536471, dark: 0x71767B)
    static let border = Color.adaptive(light: 0xEFF3F4, dark: 0x2F3336)
    static let limit = 25_000
    static let columnWidth: CGFloat = 600

    static let editorTheme = EditorTheme.post(
        size: 15,
        text: .adaptive(light: 0x0F1419, dark: 0xE7E9EA),
        secondary: .adaptive(light: 0x536471, dark: 0x71767B),
        accent: NSColor(blue),
        codeBackground: NSColor.labelColor.withAlphaComponent(0.055)
    )
}

struct XPostFeedView: View {
    @ObservedObject var document: MarkdownDocument
    let baseURL: URL?
    let profile: Profile

    private var text: String { document.text }
    private var thread: [MarkdownParser.ThreadSegment] { MarkdownParser.thread(text, keepTrailingEmpty: true) }
    private var segments: [String] { thread.map(\.text) }
    @State private var focusedNewPost: Int?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    ghostPost(seed: 0)
                    ForEach(Array(thread.enumerated()), id: \.offset) { i, segment in
                        XPostCell(markdown: segment.text, baseURL: baseURL, profile: profile,
                                  isThread: thread.count > 1, isLast: i == thread.count - 1, index: i,
                                  takesFocus: focusedNewPost == i,
                                  onEdit: { replace(at: i, with: $0) })
                    }
                    addToThreadRow
                    ghostPost(seed: 1)
                    ghostPost(seed: 2)
                    ghostPost(seed: 3)
                }
                .frame(width: XTheme.columnWidth)
                .overlay(alignment: .leading) { XTheme.border.frame(width: 1) }
                .overlay(alignment: .trailing) { XTheme.border.frame(width: 1) }
                .frame(maxWidth: .infinity)
                .padding(.top, 44)
            }

            HStack(spacing: 8) {
                CopyButton(payload: { Exporter.xThread(text) }, alternatives: copyAlternatives)
                CharacterBadge(count: totalCount, limit: XTheme.limit,
                               detail: segments.count > 1 ? "\(segments.count) posts" : nil)
            }
            .padding(16)
        }
    }

    private var addToThreadRow: some View {
        Button {
            let trimmed = text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            focusedNewPost = thread.count
            document.text = trimmed.isEmpty ? "\n\n---\n\n" : trimmed + "\n\n---\n\n"
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .light))
                    .frame(width: 40)
                Text("Add another post")
                    .font(.system(size: 15))
                Spacer()
            }
            .foregroundStyle(XTheme.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add a post to the thread (inserts a --- separator)")
        .overlay(alignment: .bottom) { XTheme.border.frame(height: 1) }
    }

    /// Writes an edited post back into its slice of the document, keeping the `---` separators padded.
    /// Segments are re-parsed here: keystrokes can arrive faster than SwiftUI re-renders the cards.
    private func replace(at index: Int, with edited: String) {
        let ns = document.text as NSString
        let thread = MarkdownParser.thread(document.text, keepTrailingEmpty: true)
        guard index < thread.count else { return }
        let segment = thread[index]
        guard NSMaxRange(segment.range) <= ns.length else { return }
        // Keep the blank lines that padded this post around its `---` separators.
        let original = ns.substring(with: segment.range)
        var replacement = edited
        if index > 0 {
            let lead = String(original.prefix { $0 == "\n" })
            replacement = (lead.isEmpty ? "\n" : lead) + replacement.drop { $0 == "\n" }
        }
        if index < thread.count - 1 {
            let trail = String(original.reversed().prefix { $0 == "\n" })
            let body = String(replacement.reversed().drop { $0 == "\n" }.reversed())
            replacement = body + (trail.isEmpty ? "\n" : trail)
        }
        document.text = ns.replacingCharacters(in: segment.range, with: replacement)
    }

    private var copyAlternatives: [(title: String, payload: () -> Exporter.Payload)] {
        let segments = self.segments
        guard segments.count > 1 else { return [] }
        return segments.enumerated().map { i, segment in
            (title: "Copy post \(i + 1)", payload: { Exporter.xPost(segment) })
        }
    }

    private var totalCount: Int {
        segments.map { String(MarkdownRender.xAttributed($0).characters).count }.reduce(0, +)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tab("For you", active: true)
                tab("Following", active: false)
            }
            .frame(height: 53)
            XTheme.border.frame(height: 1)
        }
    }

    private func tab(_ title: String, active: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: active ? .bold : .medium))
                .foregroundStyle(active ? XTheme.text : XTheme.secondary)
            Spacer()
            RoundedRectangle(cornerRadius: 2).fill(active ? XTheme.blue : .clear).frame(width: 56, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func ghostPost(seed: Int) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                GhostCircle(size: 40)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        GhostBar(width: 110, height: 12)
                        GhostBar(width: 70, height: 10)
                    }
                    GhostParagraph(lines: seed % 2 == 0 ? 3 : 2, seed: seed)
                    if seed == 2 {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                            .frame(height: 220)
                    }
                    HStack {
                        ForEach(0..<4, id: \.self) { _ in
                            GhostBar(width: 36, height: 10)
                            Spacer()
                        }
                        GhostBar(width: 20, height: 10)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            XTheme.border.frame(height: 1)
        }
        .opacity(0.55)
    }
}

struct XPostCell: View {
    let markdown: String
    let baseURL: URL?
    let profile: Profile
    var isThread = false
    var isLast = true
    var index = 0
    var takesFocus = false
    var onEdit: (String) -> Void = { _ in }
    @State private var copied = false

    private var images: [URL?] {
        MarkdownParser.images(in: markdown).map { ImagePathResolver.resolve($0.path, relativeTo: baseURL) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(profile: profile, size: 40)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(profile.name).font(.system(size: 15, weight: .bold)).foregroundStyle(XTheme.text)
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 14)).foregroundStyle(XTheme.blue)
                        Text("@\(profile.handle)").foregroundStyle(XTheme.secondary)
                        Text("·").foregroundStyle(XTheme.secondary)
                        Text("now").foregroundStyle(XTheme.secondary)
                        Spacer()
                        if isThread {
                            Button {
                                Exporter.xPost(markdown).copy()
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            } label: {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13))
                                    .foregroundStyle(copied ? Color.green : XTheme.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Copy post \(index + 1)")
                        }
                        Menu {
                            Button("Copy") {
                                Exporter.xPost(markdown).copy()
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            }
                            Button("Follow me") {
                                NSWorkspace.shared.open(URL(string: "https://x.com/imjaredz")!)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(XTheme.secondary)
                                .frame(width: 24, height: 20)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    .font(.system(size: 15))

                    PostEditor(text: markdown, theme: XTheme.editorTheme, documentURL: baseURL,
                               takesFocusOnAppear: takesFocus, onChange: onEdit)
                        .overlay(alignment: .topLeading) {
                            if markdown.isEmpty {
                                Text(index == 0 ? "What is happening?!" : "Post \(index + 1)…")
                                    .font(.system(size: 15)).foregroundStyle(XTheme.secondary)
                                    .allowsHitTesting(false)
                            }
                        }

                    if !images.isEmpty {
                        MediaGrid(urls: images, cornerRadius: 16)
                            .padding(.top, 4)
                    }

                    actionBar
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(alignment: .topLeading) {
                if isThread && !isLast {
                    RoundedRectangle(cornerRadius: 1).fill(XTheme.border).frame(width: 2)
                        .padding(.leading, 16 + 19)
                        .padding(.top, 12 + 44)
                        .padding(.bottom, -14)
                }
            }

            if !isThread || isLast {
                XTheme.border.frame(height: 1)
            }
        }
        .background(Color.clear)
        .imageDrop(documentURL: baseURL, markdown: markdown, accent: XTheme.blue, onEdit: onEdit)
    }

    private var actionBar: some View {
        HStack {
            action("bubble.right", "4")
            Spacer()
            action("arrow.2.squarepath", "12")
            Spacer()
            action("heart", "128")
            Spacer()
            action("chart.bar.xaxis", "9.4K")
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "bookmark")
                Image(systemName: "square.and.arrow.up")
            }
            .foregroundStyle(XTheme.secondary)
        }
        .font(.system(size: 13))
        .padding(.trailing, 8)
    }

    private func action(_ symbol: String, _ count: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(count)
        }
        .foregroundStyle(XTheme.secondary)
    }
}
