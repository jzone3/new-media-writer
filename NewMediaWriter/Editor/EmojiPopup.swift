import AppKit
import SwiftUI

/// Slack-style suggestion list shown under the caret while typing `:shortcode`.
final class EmojiPopup {
    private(set) var items: [EmojiCatalog.Entry] = []
    private(set) var selection = 0
    private(set) var query = ""
    var onPick: ((EmojiCatalog.Entry) -> Void)?

    private let panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = true
        return p
    }()
    private lazy var host = NSHostingView(rootView: list)
    private var clickMonitor: Any?
    private var wheelObserver: Any?

    var isVisible: Bool { panel.isVisible }

    func show(_ items: [EmojiCatalog.Entry], query: String, below caret: NSRect, in parent: NSWindow) {
        guard !items.isEmpty else { hide(); return }
        if items != self.items { selection = 0 }
        self.items = items
        self.query = query
        if panel.contentView !== host {
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
        }
        render()
        let size = EmojiList.size(rows: items.count)
        var origin = NSPoint(x: caret.minX - 8, y: caret.minY - size.height - 4)
        if let screen = parent.screen?.visibleFrame {
            origin.x = min(origin.x, screen.maxX - size.width - 8)
            if origin.y < screen.minY { origin.y = caret.maxY + 4 }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        // Clicks on chrome that doesn't take focus (feed background, scroll) leave the caret put, so watch for them here.
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                if let self, event.window !== self.panel { self.hide() }
                return event
            }
        }
        if wheelObserver == nil {
            wheelObserver = NotificationCenter.default.addObserver(forName: ScrollPassthrough.didForwardWheel, object: nil, queue: .main) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func hide() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        if let wheelObserver { NotificationCenter.default.removeObserver(wheelObserver); self.wheelObserver = nil }
        guard panel.isVisible || panel.parent != nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        items = []
        query = ""
        selection = 0
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + delta + items.count) % items.count
        render()
    }

    func pickSelected() {
        guard items.indices.contains(selection) else { return }
        onPick?(items[selection])
    }

    private func render() {
        host.rootView = list
    }

    private var list: EmojiList {
        EmojiList(items: items, query: query, selection: selection,
                  onHover: { [weak self] i in
                      guard let self, self.selection != i else { return }
                      self.selection = i
                      self.render()
                  },
                  onPick: { [weak self] e in self?.onPick?(e) })
    }
}

private struct EmojiList: View {
    let items: [EmojiCatalog.Entry]
    let query: String
    let selection: Int
    let onHover: (Int) -> Void
    let onPick: (EmojiCatalog.Entry) -> Void

    static let width: CGFloat = 300
    static let headerHeight: CGFloat = 30
    static let rowHeight: CGFloat = 28
    static let listPadding: CGFloat = 4
    static let footerHeight: CGFloat = 28
    static let hairline: CGFloat = 1
    static let radius: CGFloat = 8

    /// Fixed geometry, so the panel can be sized without asking SwiftUI (fittingSize is unreliable before first layout).
    static func size(rows: Int) -> NSSize {
        NSSize(width: width,
               height: headerHeight + hairline + listPadding * 2 + CGFloat(rows) * rowHeight + hairline + footerHeight)
    }

    private static let background = Color.adaptive(light: 0xFFFFFF, dark: 0x1A1D21)
    private static let border = Color(nsColor: NSColor(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.12)
    })
    private static let highlight = Color(nsColor: NSColor(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(Color(hex: 0x1D9BD1, opacity: 0.22))
            : NSColor(Color(hex: 0x1264A3, opacity: 0.12))
    })

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EMOJI MATCHING \":\(query)\"")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: Self.width, height: Self.headerHeight, alignment: .leading)
            Self.border.frame(height: Self.hairline)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { i, e in
                    HStack(spacing: 10) {
                        Text(e.emoji).font(.system(size: 18))
                        Text(shortcode(e.name)).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: Self.width, height: Self.rowHeight, alignment: .leading)
                    .foregroundStyle(.primary)
                    .background(i == selection ? Self.highlight : Color.clear)
                    .contentShape(Rectangle())
                    .onHover { if $0 { onHover(i) } }
                    .onTapGesture { onPick(e) }
                }
            }
            .padding(.vertical, Self.listPadding)
            Self.border.frame(height: Self.hairline)
            HStack(spacing: 14) {
                Text("↑↓ to navigate")
                Text("↩ to select")
                Text("esc to dismiss")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(width: Self.width, height: Self.footerHeight, alignment: .leading)
        }
        .background(Self.background)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(Self.border))
    }

    /// `:fire:` with the part that matched the query in bold, like Slack.
    private func shortcode(_ name: String) -> AttributedString {
        var text = AttributedString(":\(name):")
        if !query.isEmpty, let hit = text.range(of: query, options: .caseInsensitive) {
            text[hit].font = .system(size: 13, weight: .bold)
        }
        return text
    }
}
