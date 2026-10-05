import SwiftUI

enum SlackTheme {
    static let sidebar = Color.adaptive(light: 0x3F0E40, dark: 0x19171D)
    static let sidebarActive = Color(hex: 0x1164A3)
    static let text = Color.adaptive(light: 0x1D1C1D, dark: 0xD1D2D3)
    static let secondary = Color.adaptive(light: 0x616061, dark: 0xABABAD)
    static let border = Color.adaptive(light: 0xDDDDDD, dark: 0x35373B)
    static let codePink = Color(hex: 0xE01E5A)
    static let codeBackground = Color.adaptive(light: 0xF8F8F8, dark: 0x222529)
    static let limit = 40_000

    static let editorTheme = EditorTheme.post(
        size: 15,
        text: .adaptive(light: 0x1D1C1D, dark: 0xD1D2D3),
        secondary: .adaptive(light: 0x616061, dark: 0xABABAD),
        accent: NSColor(Color(hex: 0x1264A3)),
        codeBackground: .adaptive(light: 0xF8F8F8, dark: 0x222529),
        lineHeightMultiple: 1.45
    )
}

struct SlackView: View {
    @ObservedObject var document: MarkdownDocument
    let baseURL: URL?
    let profile: Profile

    private var text: String { document.text }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            VStack(spacing: 0) {
                channelHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 24)
                        ghostMessage(seed: 0)
                        ghostMessage(seed: 1)
                        dateDivider("Today")
                        SlackMessage(markdown: text, baseURL: baseURL, profile: profile, onEdit: { document.text = $0 })
                        ghostMessage(seed: 2).padding(.top, 16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 60)
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 8) {
                        CopyButton(payload: { Exporter.slack(text) },
                                   alternatives: [(title: "Copy as plain mrkdwn only", payload: { Exporter.slackPlain(text) })])
                        CharacterBadge(count: MarkdownRender.plainText(text).count, limit: SlackTheme.limit)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                }
                composer
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Workspace").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Image(systemName: "square.and.pencil").foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16).padding(.top, 44).padding(.bottom, 14)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

            VStack(alignment: .leading, spacing: 2) {
                sidebarItem("Threads", symbol: "text.bubble")
                sidebarItem("Mentions & reactions", symbol: "at")
                sidebarItem("Drafts & sent", symbol: "paperplane")
                Text("Channels").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).padding(.top, 16).padding(.horizontal, 16).padding(.bottom, 6)
                ForEach(["random", "announcements", "engineering"], id: \.self) { sidebarItem($0, symbol: "number") }
                sidebarItem(profile.slackChannel.isEmpty ? "general" : profile.slackChannel, symbol: "number", active: true)
                ForEach(["design", "product"], id: \.self) { sidebarItem($0, symbol: "number") }
            }
            .padding(.top, 10)
            Spacer()
        }
        .background(SlackTheme.sidebar)
    }

    private func sidebarItem(_ title: String, symbol: String, active: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 16)
            Text(title).font(.system(size: 15, weight: active ? .semibold : .regular))
            Spacer()
        }
        .foregroundStyle(active ? .white : .white.opacity(0.7))
        .padding(.horizontal, 16).frame(height: 28)
        .background(active ? SlackTheme.sidebarActive : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
    }

    private var channelHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "number").font(.system(size: 15, weight: .bold))
                    Text(profile.slackChannel.isEmpty ? "general" : profile.slackChannel).font(.system(size: 18, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(SlackTheme.text)
                Spacer()
                HStack(spacing: -6) {
                    ForEach(0..<3, id: \.self) { i in
                        GhostCircle(size: 20, cornerRadius: 5).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.adaptive(light: 0xFFFFFF, dark: 0x1A1D21), lineWidth: 1.5))
                    }
                }
                Text("48").font(.system(size: 13)).foregroundStyle(SlackTheme.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 44).padding(.bottom, 10)
            Rectangle().fill(SlackTheme.border).frame(height: 1)
        }
    }

    private func ghostMessage(seed: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            GhostCircle(size: 36, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { GhostBar(width: 96, height: 12); GhostBar(width: 44, height: 9) }
                GhostParagraph(lines: seed == 1 ? 1 : 2, seed: seed)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .opacity(0.55)
    }

    private func dateDivider(_ label: String) -> some View {
        ZStack {
            Rectangle().fill(SlackTheme.border).frame(height: 1)
            Text(label)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(SlackTheme.text)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.adaptive(light: 0xFFFFFF, dark: 0x1A1D21), in: Capsule())
                .overlay(Capsule().strokeBorder(SlackTheme.border))
        }
        .padding(.vertical, 8)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                ForEach(["bold", "italic", "strikethrough", "link", "list.number", "list.bullet", "chevron.left.forwardslash.chevron.right"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(SlackTheme.secondary)
            .padding(.horizontal, 12).padding(.top, 8)
            Text("Message #\(profile.slackChannel.isEmpty ? "general" : profile.slackChannel)")
                .font(.system(size: 15)).foregroundStyle(SlackTheme.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
            HStack {
                ForEach(["plus", "textformat", "face.smiling", "at", "video", "mic"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 13))
                }
                Spacer()
                Image(systemName: "paperplane.fill").font(.system(size: 12))
                    .foregroundStyle(.white).padding(6)
                    .background(Color(hex: 0x007A5A), in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(SlackTheme.secondary)
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SlackTheme.border))
        .padding(.horizontal, 20).padding(.bottom, 24)
        .opacity(0.8)
    }
}

struct SlackMessage: View {
    let markdown: String
    let baseURL: URL?
    let profile: Profile
    var onEdit: (String) -> Void = { _ in }

    var body: some View {
        let images = MarkdownParser.images(in: markdown).map { ImagePathResolver.resolve($0.path, relativeTo: baseURL) }

        HStack(alignment: .top, spacing: 10) {
            AvatarView(profile: profile, size: 36, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(profile.name).font(.system(size: 15, weight: .black)).foregroundStyle(SlackTheme.text)
                    Text(Date(), style: .time).font(.system(size: 12)).foregroundStyle(SlackTheme.secondary)
                }
                PostEditor(text: markdown, theme: SlackTheme.editorTheme, documentURL: baseURL, onChange: onEdit)
                    .overlay(alignment: .topLeading) {
                        if markdown.isEmpty {
                            Text("Message #\(profile.slackChannel)").font(.system(size: 15)).foregroundStyle(SlackTheme.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                if !images.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, url in
                            MediaGrid(urls: [url], cornerRadius: 8)
                                .frame(maxWidth: 360, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
                HStack(spacing: 6) {
                    reactionPill("👍", 3)
                    reactionPill("🎉", 1)
                    Image(systemName: "face.smiling.inverse").font(.system(size: 12)).foregroundStyle(SlackTheme.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color.adaptive(light: 0xF8F8F8, dark: 0x222529).opacity(0.0))
    }

    private func reactionPill(_ emoji: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(emoji).font(.system(size: 12))
            Text("\(count)").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(SlackTheme.sidebarActive)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(SlackTheme.sidebarActive.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(SlackTheme.sidebarActive.opacity(0.4)))
    }

    static let style = BlockStyle(
        body: .system(size: 15),
        text: SlackTheme.text,
        link: Color(hex: 0x1264A3),
        codeFont: .system(size: 12.5, design: .monospaced),
        codeBackground: SlackTheme.codeBackground,
        quoteBar: Color(hex: 0xDDDDDD),
        quoteText: SlackTheme.text,
        quoteFont: .system(size: 15),
        lineSpacing: 3,
        blockSpacing: 8,
        imageCornerRadius: 8,
        maxImageWidth: 360,
        headingFont: { _ in .system(size: 15, weight: .bold) }
    )
}
