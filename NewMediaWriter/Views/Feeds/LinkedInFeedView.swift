import SwiftUI

enum LinkedInTheme {
    static let blue = Color(hex: 0x0A66C2)
    static let text = Color.adaptive(light: 0x191919, dark: 0xE9E5DF)
    static let secondary = Color.adaptive(light: 0x666666, dark: 0xB0B0B0)
    static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x1B1F23)
    static let border = Color.adaptive(light: 0xE0DFDC, dark: 0x3A3A3A)
    static let limit = 3_000
    /// Desktop feed truncates after roughly this many characters with "…more".
    static let fold = 210
    static let columnWidth: CGFloat = 555

    /// LinkedIn has no bold/italic/strikethrough (Copy strips them too), so the card shows the text as it will post.
    static let editorTheme: EditorTheme = {
        var theme = EditorTheme.post(
            size: 14,
            text: .adaptive(light: 0x191919, dark: 0xE9E5DF),
            secondary: .adaptive(light: 0x666666, dark: 0xB0B0B0),
            accent: NSColor(blue),
            codeBackground: NSColor.labelColor.withAlphaComponent(0.055),
            lineHeightMultiple: 1.35
        )
        theme.rendersEmphasis = false
        theme.headingFontOverride = { _ in .systemFont(ofSize: 14) }
        return theme
    }()
}

struct LinkedInFeedView: View {
    @ObservedObject var document: MarkdownDocument
    let baseURL: URL?
    let profile: Profile

    private var text: String { document.text }
    private var plain: String { MarkdownRender.plainText(text) }
    private var images: [URL?] {
        MarkdownParser.images(in: text).map { ImagePathResolver.resolve($0.path, relativeTo: baseURL) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 8) {
                    composer
                    sortRow
                    LinkedInPostCard(markdown: text, images: images, profile: profile, baseURL: baseURL,
                                     onEdit: { document.text = $0 })
                    ghostPost(seed: 1, hasImage: false)
                    ghostPost(seed: 2, hasImage: true)
                }
                .frame(width: LinkedInTheme.columnWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 44)
                .padding(.bottom, 60)
            }
            HStack(spacing: 8) {
                CopyButton(payload: { Exporter.linkedIn(text) })
                CharacterBadge(count: plain.count, limit: LinkedInTheme.limit)
            }
            .padding(16)
        }
    }

    private var composer: some View {
        card {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AvatarView(profile: profile, size: 48)
                    Text("Start a post")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinkedInTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).frame(height: 48)
                        .overlay(Capsule().strokeBorder(LinkedInTheme.border))
                }
                HStack {
                    ForEach(["photo.fill", "play.rectangle.fill", "doc.text.fill"], id: \.self) {
                        Label($0 == "photo.fill" ? "Media" : $0 == "play.rectangle.fill" ? "Video" : "Write article", systemImage: $0)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LinkedInTheme.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(12)
        }
        .opacity(0.8)
    }

    private var sortRow: some View {
        HStack(spacing: 6) {
            Rectangle().fill(LinkedInTheme.border).frame(height: 1)
            Text("Sort by:").font(.system(size: 12)).foregroundStyle(LinkedInTheme.secondary)
            Text("Top ▾").font(.system(size: 12, weight: .semibold)).foregroundStyle(LinkedInTheme.text)
        }
        .padding(.horizontal, 2)
    }

    private func ghostPost(seed: Int, hasImage: Bool) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    GhostCircle(size: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        GhostBar(width: 140, height: 12)
                        GhostBar(width: 220, height: 10)
                        GhostBar(width: 60, height: 10)
                    }
                    Spacer()
                }
                GhostParagraph(lines: 3, seed: seed)
                if hasImage {
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 260).padding(.horizontal, -16)
                }
                HStack { GhostBar(width: 90, height: 10); Spacer(); GhostBar(width: 120, height: 10) }
                Rectangle().fill(LinkedInTheme.border).frame(height: 1)
                HStack {
                    ForEach(0..<4, id: \.self) { _ in GhostBar(width: 64, height: 12); Spacer() }
                }
                .padding(.horizontal, 16)
            }
            .padding(16)
        }
        .opacity(0.55)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .background(LinkedInTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LinkedInTheme.border))
    }
}

struct LinkedInPostCard: View {
    let markdown: String
    let images: [URL?]
    let profile: Profile
    var baseURL: URL? = nil
    var onEdit: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

            PostEditor(text: markdown, theme: LinkedInTheme.editorTheme, documentURL: baseURL,
                       foldAfter: LinkedInTheme.fold, takesFocusOnAppear: true, onChange: onEdit)
                .overlay(alignment: .topLeading) {
                    if markdown.isEmpty {
                        Text("What do you want to talk about?")
                            .font(.system(size: 14)).foregroundStyle(LinkedInTheme.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)

            if !images.isEmpty {
                MediaGrid(urls: images, cornerRadius: 0, singleAspect: nil, showsBorder: false)
            }

            socialCounts.padding(.horizontal, 16).padding(.vertical, 8)
            Rectangle().fill(LinkedInTheme.border).frame(height: 1).padding(.horizontal, 16)
            actionBar.padding(.horizontal, 8).padding(.vertical, 4)
        }
        .background(LinkedInTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LinkedInTheme.border))
        .imageDrop(documentURL: baseURL, markdown: markdown, accent: LinkedInTheme.blue, cornerRadius: 8, onEdit: onEdit)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(profile: profile, size: 48)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(profile.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(LinkedInTheme.text)
                    Text("• You").font(.system(size: 12)).foregroundStyle(LinkedInTheme.secondary)
                }
                Text(profile.headline).font(.system(size: 12)).foregroundStyle(LinkedInTheme.secondary).lineLimit(1)
                HStack(spacing: 3) {
                    Text("Now •").font(.system(size: 12))
                    Image(systemName: "globe.americas.fill").font(.system(size: 11))
                }
                .foregroundStyle(LinkedInTheme.secondary)
            }
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(LinkedInTheme.secondary)
        }
    }

    private var socialCounts: some View {
        HStack(spacing: 4) {
            HStack(spacing: -4) {
                reaction(Color(hex: 0x378FE9), "hand.thumbsup.fill")
                reaction(Color(hex: 0xDF704D), "heart.fill")
                reaction(Color(hex: 0xF5BB5C), "lightbulb.fill")
            }
            Text("48").font(.system(size: 12)).foregroundStyle(LinkedInTheme.secondary)
            Spacer()
            Text("12 comments · 3 reposts").font(.system(size: 12)).foregroundStyle(LinkedInTheme.secondary)
        }
    }

    private func reaction(_ color: Color, _ symbol: String) -> some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
        .overlay(Circle().stroke(LinkedInTheme.card, lineWidth: 1.5))
    }

    private var actionBar: some View {
        HStack {
            ForEach([("hand.thumbsup", "Like"), ("text.bubble", "Comment"), ("arrow.2.squarepath", "Repost"), ("paperplane", "Send")], id: \.1) { symbol, title in
                Label(title, systemImage: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinkedInTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
