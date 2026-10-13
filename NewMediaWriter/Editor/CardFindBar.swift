import AppKit
import SwiftUI

/// The native find bar for the feed views. Feed cards aren't in an NSScrollView, so NSTextView's own
/// find bar has nowhere to go; one NSTextFinder per window searches the focused card instead and
/// shows its bar in `CardFindBar`, pinned above the feed.
final class CardFinder: NSObject, ObservableObject, NSTextFinderBarContainer {
    let finder = NSTextFinder()
    @Published fileprivate(set) var barHeight: CGFloat = 0
    private(set) weak var client: EditorTextView?
    // One client for the window's lifetime: setting finder.client to nil drops the All button.
    private let clientProxy = CardFinderClient()
    /// Where the bar is drawn. The finder's container is this object rather than the view: NSTextFinder
    /// doesn't retain its container, and SwiftUI rebuilds the view on every switch to and from Markdown.
    fileprivate weak var host: CardFindBarView? {
        didSet { host?.update() }
    }

    var findBarView: NSView? {
        didSet {
            if oldValue !== findBarView { oldValue?.removeFromSuperview() }
            host?.update()
        }
    }

    var isFindBarVisible = false {
        didSet { host?.update() }
    }

    func findBarViewDidChangeHeight() { host?.update() }

    func contentView() -> NSView? { client }

    override init() {
        super.init()
        finder.client = clientProxy
        finder.findBarContainer = self
        finder.isIncrementalSearchingEnabled = true
        finder.incrementalSearchingShouldDimContentView = true
    }

    var isBarVisible: Bool { isFindBarVisible }

    func attach(_ textView: EditorTextView) {
        guard client !== textView else { return }
        finder.cancelFindIndicator()
        client = textView
        clientProxy.textView = textView
        finder.noteClientStringWillChange()
    }

    /// A card going away must not stay the finder's (unretained) client.
    func detach(_ textView: EditorTextView) {
        guard client === textView else { return }
        if isBarVisible { finder.performAction(.hideFindInterface) }
        finder.cancelFindIndicator()
        clientProxy.textView = nil
        client = nil
    }

    func perform(_ sender: Any?, for textView: EditorTextView) {
        attach(textView)
        let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? NSTextFinder.Action.showFindInterface.rawValue
        guard let action = NSTextFinder.Action(rawValue: tag) else { return }
        finder.performAction(action)
    }

    func hideBar() { finder.performAction(.hideFindInterface) }

    func clientStringWillChange(_ textView: EditorTextView) {
        if client === textView { finder.noteClientStringWillChange() }
    }
}

extension EnvironmentValues {
    @Entry var cardFinder: CardFinder? = nil
}

/// Hosts the find bar; SwiftUI sizes it to `CardFinder.barHeight` (zero while hidden).
struct CardFindBar: NSViewRepresentable {
    let finder: CardFinder

    func makeNSView(context: Context) -> CardFindBarView {
        let view = CardFindBarView()
        view.owner = finder
        finder.host = view
        return view
    }

    func updateNSView(_ view: CardFindBarView, context: Context) {}

    static func dismantleNSView(_ view: CardFindBarView, coordinator: ()) {
        if view.owner?.host === view { view.owner?.host = nil }
    }
}

final class CardFindBarView: NSView {
    fileprivate weak var owner: CardFinder?

    override var isFlipped: Bool { true }

    /// The window has a hidden title bar, so the bar sits below the traffic lights, as in the Markdown view.
    private var titlebarHeight: CGFloat {
        guard let window else { return 0 }
        return max(0, window.frame.height - window.contentLayoutRect.height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        update()
    }

    override func layout() {
        super.layout()
        if let bar = owner?.findBarView, bar.superview === self {
            bar.frame = NSRect(x: 0, y: titlebarHeight, width: bounds.width, height: bar.frame.height)
        }
    }

    fileprivate func update() {
        guard let owner else { return }
        let visible = owner.isFindBarVisible
        if let bar = owner.findBarView, visible {
            if bar.superview !== self { addSubview(bar) }
            bar.frame = NSRect(x: 0, y: titlebarHeight, width: bounds.width, height: bar.frame.height)
        } else if owner.findBarView?.superview === self {
            owner.findBarView?.removeFromSuperview()
        }
        let height = visible ? titlebarHeight + (owner.findBarView?.frame.height ?? 0) : 0
        if owner.barHeight != height {
            DispatchQueue.main.async { [weak owner] in owner?.barHeight = height }
        }
    }
}

/// The finder's client for a card. Setting the NSTextView itself as the client left Replace disabled
/// (NSTextFinder wouldn't validate any action), so this forwards the client methods to it.
final class CardFinderClient: NSObject, NSTextFinderClient {
    weak var textView: NSTextView?
    var string: String { textView?.string ?? "" }
    var isSelectable: Bool { textView?.isSelectable ?? false }
    var isEditable: Bool { textView?.isEditable ?? false }
    var allowsMultipleSelection: Bool { false }
    var firstSelectedRange: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }
    var selectedRanges: [NSValue] {
        get { textView?.selectedRanges ?? [] }
        set { textView?.selectedRanges = newValue }
    }
    func scrollRangeToVisible(_ range: NSRange) { textView?.scrollRangeToVisible(range) }
    func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool {
        textView?.shouldChangeText(inRanges: ranges, replacementStrings: strings) ?? false
    }
    func replaceCharacters(in range: NSRange, with string: String) { textView?.textStorage?.replaceCharacters(in: range, with: string) }
    func didReplaceCharacters() { textView?.didChangeText() }
    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        outRange.pointee = NSRange(location: 0, length: (string as NSString).length)
        return textView ?? NSView()
    }
    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects: [NSValue] = []
        lm.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { r, _ in
            rects.append(NSValue(rect: r.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y)))
        }
        return rects
    }
    var visibleCharacterRanges: [NSValue] {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return [] }
        let glyphs = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        return [NSValue(range: lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))]
    }
    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        lm.drawBackground(forGlyphRange: glyphs, at: tv.textContainerOrigin)
        lm.drawGlyphs(forGlyphRange: glyphs, at: tv.textContainerOrigin)
    }
}
