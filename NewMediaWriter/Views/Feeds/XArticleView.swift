import SwiftUI

struct XArticleView: View {
    let text: String
    let baseURL: URL?
    let profile: Profile

    private var blocks: [MDBlock] { MarkdownParser.parse(text) }

    var body: some View {
        let blocks = self.blocks
        let title = MarkdownParser.title(in: blocks)
        let cover = coverImage(in: blocks)
        let body = bodyBlocks(blocks, title: title != nil, cover: cover)

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "arrow.left").font(.system(size: 17, weight: .semibold))
                        Text("Article").font(.system(size: 20, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(XTheme.text)
                    .padding(.horizontal, 16)
                    .frame(height: 53)

                    if let cover {
                        MediaGrid(urls: [cover], cornerRadius: 16, singleAspect: 16 / 9, showsBorder: false)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    }

                    Text(title ?? "Untitled article")
                        .font(.system(size: 31, weight: .heavy))
                        .foregroundStyle(title == nil ? XTheme.secondary : XTheme.text)
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    HStack(spacing: 12) {
                        AvatarView(profile: profile, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(profile.name).font(.system(size: 15, weight: .bold)).foregroundStyle(XTheme.text)
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 14)).foregroundStyle(XTheme.blue)
                            }
                            Text("@\(profile.handle)").font(.system(size: 15)).foregroundStyle(XTheme.secondary)
                        }
                        Spacer()
                        Text("Subscribe")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.adaptive(light: 0xFFFFFF, dark: 0x0F1419))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Color.adaptive(light: 0x0F1419, dark: 0xEFF3F4), in: Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    Text("Published now · \(readingTime(body)) min read")
                        .font(.system(size: 14)).foregroundStyle(XTheme.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    XTheme.border.frame(height: 1).padding(.horizontal, 16).padding(.bottom, 24)

                    if body.isEmpty && title == nil {
                        Text("Start with a `# Title`, then write. The first image becomes the cover.")
                            .font(.system(size: 17)).foregroundStyle(XTheme.secondary)
                            .padding(.horizontal, 16)
                    } else {
                        BlockStack(blocks: body, baseURL: baseURL, style: Self.style)
                            .padding(.horizontal, 16)
                    }

                    XTheme.border.frame(height: 1).padding(.horizontal, 16).padding(.top, 32)
                    HStack {
                        ForEach(["bubble.right", "arrow.2.squarepath", "heart", "bookmark", "square.and.arrow.up"], id: \.self) {
                            Image(systemName: $0).font(.system(size: 17)).foregroundStyle(XTheme.secondary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                }
                .frame(width: 680)
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
                .padding(.bottom, 60)
            }

            CharacterBadge(count: MarkdownRender.plainText(text).count, limit: 100_000, detail: "\(wordCount) words")
                .padding(16)
        }
    }

    private var wordCount: Int {
        MarkdownRender.plainText(text).split { $0.isWhitespace || $0.isNewline }.count
    }

    private func readingTime(_ blocks: [MDBlock]) -> Int { max(1, Int((Double(wordCount) / 230).rounded(.up))) }

    private func coverImage(in blocks: [MDBlock]) -> URL? {
        for case let .image(_, path) in blocks {
            return ImagePathResolver.resolve(path, relativeTo: baseURL)
        }
        return nil
    }

    private func bodyBlocks(_ blocks: [MDBlock], title: Bool, cover: URL?) -> [MDBlock] {
        var out: [MDBlock] = []
        var skippedTitle = !title
        var skippedCover = cover == nil
        for block in blocks {
            if !skippedTitle, case .heading(1, _) = block { skippedTitle = true; continue }
            if !skippedCover, case .image = block { skippedCover = true; continue }
            out.append(block)
        }
        return out
    }

    static let style = BlockStyle(
        body: .system(size: 17),
        text: XTheme.text,
        link: XTheme.blue,
        codeFont: .system(size: 14, design: .monospaced),
        codeBackground: Color.adaptive(light: 0xF7F9F9, dark: 0x16181C),
        quoteBar: XTheme.border,
        quoteText: XTheme.secondary,
        quoteFont: .system(size: 19, weight: .regular, design: .serif).italic(),
        lineSpacing: 6,
        blockSpacing: 18,
        imageCornerRadius: 16,
        headingFont: { level in
            switch level {
            case 1, 2: .system(size: 24, weight: .bold)
            case 3: .system(size: 20, weight: .bold)
            default: .system(size: 17, weight: .bold)
            }
        }
    )
}
