import SwiftUI

enum XTheme {
    static let blue = Color(hex: 0x1D9BF0)
    static let text = Color.adaptive(light: 0x0F1419, dark: 0xE7E9EA)
    static let secondary = Color.adaptive(light: 0x536471, dark: 0x71767B)
    static let border = Color.adaptive(light: 0xEFF3F4, dark: 0x2F3336)
    static let limit = 25_000
    static let columnWidth: CGFloat = 600
}

struct XPostFeedView: View {
    let text: String
    let baseURL: URL?
    let profile: Profile

    private var segments: [String] { MarkdownParser.threadSegments(text) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    ghostPost(seed: 0)
                    ForEach(Array(segments.enumerated()), id: \.offset) { i, segment in
                        XPostCell(markdown: segment, baseURL: baseURL, profile: profile,
                                  isThread: segments.count > 1, isLast: i == segments.count - 1, index: i)
                    }
                    ghostPost(seed: 1)
                    ghostPost(seed: 2)
                    ghostPost(seed: 3)
                }
                .frame(width: XTheme.columnWidth)
                .overlay(alignment: .leading) { XTheme.border.frame(width: 1) }
                .overlay(alignment: .trailing) { XTheme.border.frame(width: 1) }
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
            }

            CharacterBadge(count: totalCount, limit: XTheme.limit,
                           detail: segments.count > 1 ? "\(segments.count) posts" : nil)
                .padding(16)
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

    private var attributed: AttributedString {
        MarkdownRender.xAttributed(markdown)
            .styled(baseFont: .system(size: 15), color: XTheme.text, codeFont: .system(size: 14, design: .monospaced), linkColor: XTheme.blue)
    }

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
                        Image(systemName: "ellipsis").foregroundStyle(XTheme.secondary)
                    }
                    .font(.system(size: 15))

                    if attributed.characters.isEmpty && images.isEmpty {
                        Text(index == 0 ? "What is happening?!" : "Add another post…")
                            .font(.system(size: 15)).foregroundStyle(XTheme.secondary)
                    } else {
                        Text(attributed)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
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
