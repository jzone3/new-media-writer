import AppKit
import SwiftUI

/// Slack-style suggestion list shown under the caret while typing `:shortcode`.
final class EmojiPopup {
    private(set) var items: [EmojiCatalog.Entry] = []
    private(set) var selection = 0
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

    var isVisible: Bool { panel.isVisible }

    func show(_ items: [EmojiCatalog.Entry], below caret: NSRect, in parent: NSWindow) {
        guard !items.isEmpty else { hide(); return }
        if items != self.items { selection = 0 }
        self.items = items
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
    }

    func hide() {
        guard panel.isVisible || panel.parent != nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        items = []
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
        EmojiList(items: items, selection: selection,
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
    let selection: Int
    let onHover: (Int) -> Void
    let onPick: (EmojiCatalog.Entry) -> Void

    static let rowWidth: CGFloat = 260
    static let rowHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 1
    static let inset: CGFloat = 6

    /// Fixed geometry, so the panel can be sized without asking SwiftUI (fittingSize is unreliable before first layout).
    static func size(rows: Int) -> NSSize {
        NSSize(width: rowWidth + inset * 2,
               height: CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * rowSpacing + inset * 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element) { i, e in
                HStack(spacing: 10) {
                    Text(e.emoji).font(.system(size: 17))
                    Text(":\(e.name):").font(.system(size: 13, weight: .medium, design: .monospaced))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(width: Self.rowWidth, height: Self.rowHeight, alignment: .leading)
                .foregroundStyle(i == selection ? Color.white : Color.primary)
                .background(i == selection ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
                .onHover { if $0 { onHover(i) } }
                .onTapGesture { onPick(e) }
            }
        }
        .padding(Self.inset)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.12)))
    }
}
