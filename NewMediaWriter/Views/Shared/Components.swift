import AVKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Picks a light/dark variant following the current appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: .adaptive(light: light, dark: dark))
    }
}

extension NSColor {
    static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        }
    }
}

struct AvatarView: View {
    let profile: Profile
    var size: CGFloat = 40
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Group {
            if let image = profile.avatarImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                // Generic Apple Contacts placeholder: grey gradient disc, white rounded initials.
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: 0xB4B9C3), Color(hex: 0x8C919B)],
                        startPoint: .top, endPoint: .bottom
                    )
                    Text(profile.initials)
                        .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous))
    }
}

/// Grey placeholder bar standing in for text in ghost posts.
struct GhostBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 10
    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct GhostCircle: View {
    var size: CGFloat
    var cornerRadius: CGFloat? = nil
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .frame(width: size, height: size)
    }
}

struct GhostParagraph: View {
    var lines: Int = 3
    var seed: Int = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { i in
                GhostBar(width: i == lines - 1 ? widthFor(i) : nil)
            }
        }
    }
    private func widthFor(_ i: Int) -> CGFloat {
        let options: [CGFloat] = [180, 240, 300, 140, 210]
        return options[(seed + i) % options.count]
    }
}

/// Loads a local or remote image through ImageCache, re-rendering once a remote image lands.
struct DocumentImage: View {
    let url: URL?
    @State private var tick = 0

    var body: some View {
        if let url, let image = ImageCache.shared.image(for: url, onLoad: { tick += 1 }) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.08))
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.title2)
                    Text(url?.lastPathComponent ?? "missing image").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .id(tick)
        }
    }
}

/// X / LinkedIn style media grid for 1–4 images or videos (videos play inline).
/// With `onRemove`, each item gets a remove button; clicking an image opens it.
struct MediaGrid: View {
    let urls: [URL?]
    var cornerRadius: CGFloat = 16
    var spacing: CGFloat = 2
    var singleAspect: CGFloat? = nil
    var showsBorder = true
    var onRemove: ((Int) -> Void)? = nil

    var body: some View {
        let items = Array(urls.prefix(4))
        Group {
            switch items.count {
            case 0: EmptyView()
            case 1:
                if let aspect = singleAspect {
                    tile(items, 0, aspect: aspect)
                } else {
                    SingleMedia(url: items[0]).mediaControls(url: items[0], onRemove: remover(0))
                }
            case 2:
                HStack(spacing: spacing) {
                    tile(items, 0, aspect: 0.9)
                    tile(items, 1, aspect: 0.9)
                }
            case 3:
                HStack(spacing: spacing) {
                    tile(items, 0, aspect: 0.9)
                    VStack(spacing: spacing) {
                        tile(items, 1, aspect: 1.8)
                        tile(items, 2, aspect: 1.8)
                    }
                }
            default:
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        tile(items, 0, aspect: 1.8)
                        tile(items, 1, aspect: 1.8)
                    }
                    HStack(spacing: spacing) {
                        tile(items, 2, aspect: 1.8)
                        tile(items, 3, aspect: 1.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func remover(_ index: Int) -> (() -> Void)? {
        onRemove.map { remove in { remove(index) } }
    }

    private func tile(_ items: [URL?], _ index: Int, aspect: CGFloat) -> some View {
        Tile(url: items[index], aspect: aspect).mediaControls(url: items[index], onRemove: remover(index))
    }

    /// Fixed-aspect cell: the media fills and is clipped, never dictating the cell size.
    private struct Tile: View {
        let url: URL?
        let aspect: CGFloat
        var body: some View {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay {
                    if ImageStore.isVideo(url), let url {
                        DocumentVideo(url: url)
                    } else {
                        DocumentImage(url: url)
                    }
                }
                .clipped()
        }
    }

    private struct SingleMedia: View {
        let url: URL?
        var body: some View {
            if ImageStore.isVideo(url), let url {
                SingleVideo(url: url).id(FileIdentity(url))
            } else if let url, let image = ImageCache.shared.image(for: url), image.size.height > 0 {
                let ratio = image.size.width / image.size.height
                if ratio < 0.8 {
                    Tile(url: url, aspect: 0.8)
                } else {
                    Image(nsImage: image).resizable().aspectRatio(ratio, contentMode: .fit)
                }
            } else {
                DocumentImage(url: url).aspectRatio(16 / 9, contentMode: .fill)
            }
        }
    }

    /// A lone video is shown at its own aspect ratio (portrait clamped like images).
    private struct SingleVideo: View {
        let url: URL
        @State private var ratio: CGFloat = 16 / 9
        var body: some View {
            Color.clear
                .aspectRatio(max(ratio, 0.8), contentMode: .fit)
                .overlay { DocumentVideo(url: url) }
                .clipped()
                .task(id: url) { if let r = await DocumentVideo.aspectRatio(of: url) { ratio = r } }
        }
    }
}

private extension View {
    func mediaControls(url: URL?, onRemove: (() -> Void)?) -> some View {
        modifier(MediaControls(url: url, onRemove: onRemove))
    }
}

/// Remove button + open-on-click for one media item. Videos keep their clicks for the player controls.
private struct MediaControls: ViewModifier {
    let url: URL?
    let onRemove: (() -> Void)?
    @State private var hovering = false

    private var isVideo: Bool { ImageStore.isVideo(url) }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { if !isVideo { open() } }
            .onHover { inside in
                guard !isVideo, inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if hovering { hovering = false; NSCursor.pop() } }
            .help(isVideo ? "" : "Click to open \(url?.lastPathComponent ?? "image")")
            .contextMenu {
                if url != nil {
                    Button(isVideo ? "Open Video" : "Open Image") { open() }
                }
                if let url, url.isFileURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                if let onRemove {
                    Divider()
                    Button("Remove from Post", action: onRemove)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.7), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isVideo ? "Remove video" : "Remove image")
                    .padding(8)
                }
            }
    }

    private func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Inline, playable native video player for a local or remote video. Re-created when the file at
/// `url` is replaced, so a new video saved under an old name never shows the old one.
struct DocumentVideo: View {
    let url: URL

    var body: some View {
        if url.isFileURL, FileIdentity(url) == nil {
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.08))
                VStack(spacing: 6) {
                    Image(systemName: "video").font(.title2)
                    Text(url.lastPathComponent).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        } else {
            VideoPlayerView(url: url).id(FileIdentity(url))
        }
    }

    static func aspectRatio(of url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        guard rect.height != 0 else { return nil }
        return abs(rect.width / rect.height)
    }
}

private struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspectFill
        view.showsFullScreenToggleButton = true
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player = AVPlayer(url: url)
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

/// Copies the current document in the format the active preview's composer expects.
struct CopyButton: View {
    let payload: () -> Exporter.Payload
    var alternatives: [(title: String, payload: () -> Exporter.Payload)] = []
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                perform(payload)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(copied ? "Copied" : "Copy")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Copy for this view (⇧⌘C)")

            if !alternatives.isEmpty {
                Menu {
                    ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alt in
                        Button(alt.title) { perform(alt.payload) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointingHandCursor()
                .padding(.leading, 4)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(copied ? Color.green : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .animation(.easeOut(duration: 0.15), value: copied)
        .onReceive(NotificationCenter.default.publisher(for: .copyForCurrentView)) { _ in perform(payload) }
    }

    private func perform(_ make: () -> Exporter.Payload) {
        make().copy()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

extension View {
    /// Pointing-hand cursor while hovering a clickable control.
    func pointingHandCursor() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.underMouse.set()
            }
        }
    }
}

private extension NSCursor {
    /// Arrow, or I-beam when leaving a control straight into editable text.
    static var underMouse: NSCursor {
        guard let window = NSApp.keyWindow, let content = window.contentView else { return .arrow }
        let point = content.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        var view = content.hitTest(point)
        while let v = view {
            if let text = v as? NSTextView { return text.isEditable ? .iBeam : .arrow }
            view = v.superview
        }
        return .arrow
    }
}

extension Notification.Name {
    static let copyForCurrentView = Notification.Name("copyForCurrentView")
}

/// "1,234 / 25,000" pill shown in the corner of every social preview.
struct CharacterBadge: View {
    let count: Int
    let limit: Int
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let detail {
                Text(detail)
                Text("·")
            }
            Text("\(count.formattedCount) / \(limit.formattedCount)")
                .foregroundStyle(count > limit ? Color.red : Color.secondary)
                .fontWeight(count > limit ? .semibold : .regular)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: min(CGFloat(count) / CGFloat(max(limit, 1)), 1))
                    .stroke(count > limit ? Color.red : Color(hex: 0x1D9BF0), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
        .font(.system(size: 12, design: .rounded).monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Renders parsed markdown blocks with a given visual style (used by X Article and Slack).
struct BlockStack: View {
    let blocks: [MDBlock]
    let baseURL: URL?
    var style: BlockStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownInline.attributed(text).styled(baseFont: style.headingFont(level), color: style.text, codeFont: style.codeFont, linkColor: style.link))
                .lineSpacing(2)
                .padding(.top, level <= 2 ? 10 : 4)
        case .paragraph(let text):
            Text(MarkdownInline.attributed(text).styled(baseFont: style.body, color: style.text, codeFont: style.codeFont, linkColor: style.link))
                .lineSpacing(style.lineSpacing)
        case .quote(let lines):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(style.quoteBar).frame(width: 4)
                Text(MarkdownInline.attributed(lines.joined(separator: "\n")).styled(baseFont: style.quoteFont, color: style.quoteText, codeFont: style.codeFont, linkColor: style.link))
                    .lineSpacing(style.lineSpacing)
            }
        case .code(_, let code):
            Text(code)
                .font(style.codeFont)
                .foregroundStyle(style.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(i + 1)." : "•")
                            .font(style.body)
                            .foregroundStyle(style.text)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(MarkdownInline.attributed(item).styled(baseFont: style.body, color: style.text, codeFont: style.codeFont, linkColor: style.link))
                            .lineSpacing(style.lineSpacing)
                    }
                }
            }
        case .image(_, let path):
            MediaGrid(urls: [ImagePathResolver.resolve(path, relativeTo: baseURL)], cornerRadius: style.imageCornerRadius)
                .frame(maxWidth: style.maxImageWidth, alignment: .leading)
        case .rule:
            Divider().padding(.vertical, 8)
        }
    }
}

struct BlockStyle {
    var body: Font
    var text: Color
    var link: Color
    var codeFont: Font
    var codeBackground: Color
    var quoteBar: Color
    var quoteText: Color
    var quoteFont: Font
    var lineSpacing: CGFloat
    var blockSpacing: CGFloat
    var imageCornerRadius: CGFloat
    var maxImageWidth: CGFloat? = nil
    var headingFont: (Int) -> Font
}
