import AppKit
import UniformTypeIdentifiers

/// NSTextView that keeps a centred reading column, hides markdown syntax away from the cursor,
/// renders images below their `![]()` line and stores pasted/dropped images in `assets/`.
/// How the timeline fold is drawn. The marker is an overlay: it never changes line or paragraph spacing.
struct FoldMarkerStyle {
    var label = "…more"
    /// nil falls back to the theme's secondary colour.
    var labelColor: NSColor? = nil
    /// Hairline across the column at the fold (X); nil draws no line (LinkedIn shows only the label).
    var lineColor: NSColor? = nil
    /// Fill behind the label so it sits on top of the text; match the card colour.
    var labelBackground: NSColor = .textBackgroundColor
}

final class EditorTextView: NSTextView, NSLayoutManagerDelegate, NSTextStorageDelegate {
    let emojiPopup = EmojiPopup()

    var overlayTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installOverlayCursorTracking()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        _ = updateCursorForOverlays(event)
    }

    override func cursorUpdate(with event: NSEvent) {
        if updateCursorForOverlays(event) { return }
        super.cursorUpdate(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            emojiPopup.hide()
            // NSTextView's typing-undo operations keep unretained references to this view and its layout
            // manager (and are not registered with the view as target), so a ⌘Z after a view switch would
            // message freed objects. The window is still reachable here: clear the undo stack.
            undoManager?.removeAllActions()
            window?.undoManager?.removeAllActions()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    /// The editor claims keyboard focus when it appears (new window, view switch) so typing and ⌘V work without
    /// a click first. Set on the document editor and on each feed's primary post editor; extra thread posts
    /// only take it when they were just added.
    var takesFocusOnAppear = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesFocusOnAppear, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            // The outgoing view's card editor (or the closing ⌘K picker) may still hold focus here; take it anyway.
            guard let self, let window, self.window === window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    override func doCommand(by selector: Selector) {
        if handleEmojiCommand(selector) { return }
        super.doCommand(by: selector)
    }

    let styler = MarkdownStyler()
    var documentURL: URL? {
        didSet { if documentURL != oldValue, textStorage?.length ?? 0 > 0 { restyleAndRelayout() } }
    }
    var onImageInserted: (() -> Void)?

    var maxColumnWidth: CGFloat = 720
    var topInset: CGFloat = 56
    /// Embedded in a feed card: no centred column, text spans the full frame width.
    var fillsWidth = false
    var placeholder: String? { didSet { needsDisplay = true } }
    /// Feed cards show media in their own grid, so the editor skips inline image rendering.
    var showsImages = true { didSet { styler.revealsBrokenImages = showsImages } }
    /// Overlays a fold marker after this many visible (non-marker) characters.
    var foldAfterVisibleCharacters: Int? { didSet { if oldValue != foldAfterVisibleCharacters { refreshFold() } } }
    var foldStyle = FoldMarkerStyle() { didSet { needsDisplay = true } }
    /// Embedded editors only reveal syntax in the cursor's paragraph while they have keyboard focus.
    var revealsMarkersOnlyWhenFocused = false

    private var revealsActiveParagraph: Bool {
        !revealsMarkersOnlyWhenFocused || window?.firstResponder === self
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, revealsMarkersOnlyWhenFocused { invalidateGlyphs(in: activeParagraph) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        emojiPopup.hide()
        let ok = super.resignFirstResponder()
        if ok, revealsMarkersOnlyWhenFocused {
            let range = activeParagraph
            DispatchQueue.main.async { [weak self] in self?.invalidateGlyphs(in: range); self?.needsDisplay = true }
        }
        return ok
    }
    var hideMarkers = true { didSet { invalidateAllGlyphs() } }

    private var activeParagraph = NSRange(location: 0, length: 0)
    private var imageViews: [NSRange: NSImageView] = [:]
    private var lastColumnWidth: CGFloat = 0

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Accessing layoutManager forces TextKit 1, which we rely on for glyph hiding.
        guard let layoutManager, let textStorage else { return }
        layoutManager.delegate = self
        layoutManager.allowsNonContiguousLayout = false
        textStorage.delegate = self

        isRichText = true
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        usesFontPanel = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        smartInsertDeleteEnabled = false
        drawsBackground = false
        insertionPointColor = .controlAccentColor
        textContainer?.widthTracksTextView = false
        textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = true
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        styler.imageHeight = { [weak self] path in self?.displayHeight(forImagePath: path) ?? 0 }
        styler.revealsBrokenImages = showsImages
    }

    // MARK: - Column layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateColumn(width: newSize.width)
        layoutImages()
    }

    private func updateColumn(width: CGFloat) {
        let column = fillsWidth ? max(width, 10) : min(max(width - 96, 240), maxColumnWidth)
        let inset = fillsWidth ? 0 : max((width - column) / 2, 0)
        textContainerInset = NSSize(width: inset, height: topInset)
        textContainer?.containerSize = NSSize(width: column, height: CGFloat.greatestFiniteMagnitude)
        if abs(column - lastColumnWidth) > 0.5 {
            lastColumnWidth = column
            if let textStorage, textStorage.length > 0 {
                styler.restyle(textStorage)
            }
        }
    }

    var columnWidth: CGFloat { textContainer?.containerSize.width ?? maxColumnWidth }

    override var textContainerOrigin: NSPoint {
        var origin = super.textContainerOrigin
        origin.x = textContainerInset.width
        return origin
    }

    // MARK: - Styling pipeline

    // Restyling happens here, after the edit has been processed, as an attribute-only pass. Doing it inside
    // `willProcessEditing` widened the character-edit range to the whole document, which made NSTextView
    // move the insertion point to the end of the text after every keystroke.
    override func didChangeText() {
        super.didChangeText()
        if let textStorage { styler.restyle(textStorage) }
        matchEmptyCaretToPlaceholder()
        updateActiveParagraph(invalidate: true)
        if foldAfterVisibleCharacters != nil { refreshFold() }
        needsImageLayout = true
        // Deferred: the popup queries layout, which must not happen while the edit is still being processed.
        DispatchQueue.main.async { [weak self] in self?.layoutImages(); self?.updateEmojiSuggestions() }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateActiveParagraph(invalidate: true)
        if emojiPopup.isVisible && !stillSelecting {
            DispatchQueue.main.async { [weak self] in self?.updateEmojiSuggestions() }
        }
    }

    private func updateActiveParagraph(invalidate: Bool) {
        guard let textStorage else { return }
        let string = textStorage.string as NSString
        let sel = selectedRange()
        let loc = min(sel.location, string.length)
        var newRange = string.length == 0 ? NSRange(location: 0, length: 0) : string.paragraphRange(for: NSRange(location: loc, length: 0))
        if sel.length > 0 {
            let end = string.paragraphRange(for: NSRange(location: min(sel.location + sel.length, string.length), length: 0))
            newRange = NSUnionRange(newRange, end)
        }
        guard newRange != activeParagraph else { return }
        let old = activeParagraph
        activeParagraph = newRange
        if invalidate {
            invalidateGlyphs(in: old)
            invalidateGlyphs(in: newRange)
        }
    }

    private func invalidateGlyphs(in range: NSRange) {
        guard let layoutManager, let textStorage else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard clamped.length > 0 else { return }
        layoutManager.invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        layoutManager.invalidateDisplay(forCharacterRange: clamped)
    }

    private func invalidateAllGlyphs() {
        guard let textStorage else { return }
        invalidateGlyphs(in: NSRange(location: 0, length: textStorage.length))
    }

    // MARK: - NSLayoutManagerDelegate: hide syntax markers

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard hideMarkers, let storage = layoutManager.textStorage else { return 0 }
        var newProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var changed = false
        for i in 0..<glyphRange.length {
            let charIndex = charIndexes[i]
            guard charIndex < storage.length else { continue }
            if storage.attribute(.mdBullet, at: charIndex, effectiveRange: nil) != nil,
               let bullet = Self.bulletGlyph(in: aFont) {
                newGlyphs[i] = bullet
                changed = true
                continue
            }
            if revealsActiveParagraph, NSLocationInRange(charIndex, activeParagraph) { continue }
            if storage.attribute(.mdMarker, at: charIndex, effectiveRange: nil) != nil {
                newProps[i] = storage.attribute(.mdKeepLine, at: charIndex, effectiveRange: nil) != nil ? .controlCharacter : .null
                changed = true
            }
        }
        guard changed else { return 0 }
        newProps.withUnsafeBufferPointer { propBuf in
            newGlyphs.withUnsafeBufferPointer { glyphBuf in
                layoutManager.setGlyphs(glyphBuf.baseAddress!, properties: propBuf.baseAddress!, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            }
        }
        return glyphRange.length
    }

    private static var bulletGlyphCache: [NSFont: CGGlyph] = [:]
    private static func bulletGlyph(in font: NSFont) -> CGGlyph? {
        if let cached = bulletGlyphCache[font] { return cached == 0 ? nil : cached }
        var chars: [UniChar] = [0x2022]
        var glyph: [CGGlyph] = [0]
        CTFontGetGlyphsForCharacters(font, &chars, &glyph, 1)
        bulletGlyphCache[font] = glyph[0]
        return glyph[0] == 0 ? nil : glyph[0]
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if let storage = layoutManager.textStorage, charIndex < storage.length,
           storage.attribute(.mdKeepLine, at: charIndex, effectiveRange: nil) != nil,
           !(revealsActiveParagraph && NSLocationInRange(charIndex, activeParagraph)) {
            return .whitespace
        }
        return action
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: glyphPosition.x, y: proposedRect.minY, width: 0, height: proposedRect.height)
    }

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        if layoutFinishedFlag { layoutImages() }
    }

    // MARK: - Decorations (code background, quote bars, rules)

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer, let textStorage, !styler.raw else { return }
        let origin = textContainerOrigin
        let full = NSRange(location: 0, length: textStorage.length)

        textStorage.enumerateAttribute(.mdQuote, in: full) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var r = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            r.origin.x = origin.x + 4
            r.origin.y += origin.y
            r.size.width = 3
            styler.theme.secondary.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
        }

        textStorage.enumerateAttribute(.mdRule, in: full) { value, range, _ in
            guard value != nil, !(revealsActiveParagraph && NSLocationInRange(range.location, activeParagraph)) else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var r = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            r.origin.y += origin.y
            let y = r.midY
            if styler.theme.rulesAsContinuationDots {
                styler.theme.secondary.withAlphaComponent(0.6).setFill()
                let d: CGFloat = 3, gap: CGFloat = 5
                let midX = origin.x + textContainer.containerSize.width / 2
                for i in -1...1 {
                    let x = midX + CGFloat(i) * (d + gap) - d / 2
                    NSBezierPath(ovalIn: NSRect(x: x, y: y - d / 2, width: d, height: d)).fill()
                }
                return
            }
            let line = NSRect(x: origin.x, y: y, width: textContainer.containerSize.width, height: 1)
            styler.theme.secondary.withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: line).fill()
        }

        drawFoldLine()

        textStorage.enumerateAttribute(.mdCodeBackground, in: full) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let isBlock = (textStorage.string as NSString).paragraphRange(for: range) == range
                || (textStorage.string as NSString).paragraphRange(for: range).length - range.length <= 1
            var r = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            r.origin.x += origin.x
            r.origin.y += origin.y
            if isBlock {
                r.origin.x = origin.x - 12
                r.size.width = textContainer.containerSize.width + 24
                let fill = NSBezierPath(rect: r)
                styler.theme.codeBackground.setFill()
                fill.fill()
            } else {
                r = r.insetBy(dx: -3, dy: 1)
                let fill = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
                styler.theme.codeBackground.setFill()
                fill.fill()
            }
        }
    }

    // MARK: - Fold marker (LinkedIn "…more", X "Show more")

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder {
            let origin = textContainerOrigin
            (placeholder as NSString).draw(
                with: NSRect(x: origin.x, y: origin.y, width: columnWidth, height: bounds.height - origin.y),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: placeholderAttributes
            )
        }
        drawFoldMarker()
    }

    func placeholderHeight(for width: CGFloat) -> CGFloat {
        guard let placeholder else { return 0 }
        return ceil((placeholder as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: placeholderAttributes
        ).height)
    }

    private var placeholderAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = styler.theme.lineHeightMultiple
        return [
            .font: styler.theme.body,
            .foregroundColor: styler.theme.secondary,
            .paragraphStyle: paragraph,
        ]
    }

    private var foldLabel: NSString { foldStyle.label as NSString }
    private var foldLabelAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 10, weight: .semibold),
         .foregroundColor: foldStyle.labelColor ?? styler.theme.secondary]
    }

    /// Index of the last character shown above the fold, if the text runs past `foldAfterVisibleCharacters`.
    private func foldCharacterIndex() -> Int? {
        if let cached = foldIndexCache { return cached }
        let index = computeFoldCharacterIndex()
        foldIndexCache = .some(index)
        return index
    }

    private var foldIndexCache: Int?? = nil

    private func computeFoldCharacterIndex() -> Int? {
        guard let fold = foldAfterVisibleCharacters, fold > 0, let textStorage, textStorage.length > 0 else { return nil }
        var visible = 0
        var lastShown: Int?
        var i = 0
        while i < textStorage.length {
            var effective = NSRange()
            let isMarker = textStorage.attribute(.mdMarker, at: i, effectiveRange: &effective) != nil
            if !isMarker {
                if lastShown == nil, visible + effective.length >= fold { lastShown = i + (fold - visible) - 1 }
                visible += effective.length
            }
            i = effective.location + effective.length
        }
        return visible > fold ? lastShown : nil
    }

    /// Fold moved, appeared or vanished: only repaint. The marker is drawn over the text, so layout never changes.
    private func refreshFold() {
        foldIndexCache = nil
        needsDisplay = true
    }

    /// Where the marker goes, in view coordinates. `y` is the middle of the gap under the line holding the last
    /// shown character (where the X hairline runs). The label sits at the trailing edge: on the folded line when
    /// that line ends early enough, otherwise centred in the gap between the two lines' glyphs.
    private func foldGeometry() -> (y: CGFloat, label: NSRect)? {
        guard let layoutManager, let textContainer, let foldIndex = foldCharacterIndex() else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: foldIndex)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        let origin = textContainerOrigin
        let boundary = origin.y + fragment.maxY
        let size = foldLabel.size(withAttributes: foldLabelAttributes)
        let width = ceil(size.width) + 12, height = ceil(size.height) + 1
        let right = origin.x + textContainer.containerSize.width
        let font = styler.theme.body
        let descent = -font.descender
        let extra = max(0, fragment.height - (font.ascender - font.descender + font.leading))
        let gap = ((boundary - descent) + (boundary + extra + font.ascender - font.capHeight)) / 2
        let fitsOnLine = origin.x + used.maxX + 8 <= right - width
        let centre = fitsOnLine ? boundary - descent - font.capHeight / 2 : gap
        return (gap.rounded(), NSRect(x: right - width, y: (centre - height / 2).rounded(), width: width, height: height))
    }

    /// Bottom edge of the fold label in text-container coordinates, so hosts sizing to content can reserve room for it.
    var foldMarkerBottom: CGFloat? {
        guard let geometry = foldGeometry() else { return nil }
        return geometry.label.maxY - textContainerOrigin.y
    }

    /// Hairline under the text (drawn from `drawBackground`) so glyphs stay on top of it.
    private func drawFoldLine() {
        guard let color = foldStyle.lineColor, let geometry = foldGeometry() else { return }
        color.setFill()
        let x = textContainerOrigin.x
        NSBezierPath(rect: NSRect(x: x, y: geometry.y - 0.5, width: geometry.label.minX - 6 - x, height: 1)).fill()
    }

    private func drawFoldMarker() {
        guard let geometry = foldGeometry() else { return }
        foldStyle.labelBackground.setFill()
        NSBezierPath(roundedRect: geometry.label, xRadius: geometry.label.height / 2, yRadius: geometry.label.height / 2).fill()
        foldLabel.draw(at: NSPoint(x: geometry.label.minX + 6, y: geometry.label.minY + 0.5), withAttributes: foldLabelAttributes)
    }

    // MARK: - Images

    private var needsImageLayout = false

    func displayHeight(forImagePath path: String) -> CGFloat {
        guard showsImages, let url = ImagePathResolver.resolve(path, relativeTo: documentURL),
              let image = ImageCache.shared.image(for: url, onLoad: { [weak self] in self?.restyleAndRelayout() }) else {
            return 0
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 0 }
        let width = min(size.width, columnWidth)
        let height = width * size.height / size.width
        return min(height, 480)
    }

    func restyleAndRelayout() {
        guard let textStorage else { return }
        styler.restyle(textStorage)
        matchEmptyCaretToPlaceholder()
        foldIndexCache = nil
        needsImageLayout = true
        layoutImages()
    }

    /// An empty view has no text to carry the theme's font/line height, so the caret would use the
    /// system defaults and sit above the placeholder.
    private func matchEmptyCaretToPlaceholder() {
        guard string.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = styler.theme.lineHeightMultiple
        typingAttributes = [.font: styler.theme.body, .foregroundColor: styler.theme.text, .paragraphStyle: paragraph]
    }

    private var isLayingOutImages = false

    private func layoutImages() {
        guard showsImages, !isLayingOutImages, let layoutManager, let textContainer, let textStorage else { return }
        isLayingOutImages = true
        defer { isLayingOutImages = false }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        var seen: Set<NSRange> = []
        let full = NSRange(location: 0, length: textStorage.length)

        var spacingStale = false
        textStorage.enumerateAttribute(.mdImage, in: full) { value, range, _ in
            guard let path = value as? String else { return }
            let height = displayHeight(forImagePath: path)
            let spacing = (textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing ?? 0
            if abs(spacing - (height + 16)) > 0.5 { spacingStale = true }
        }
        if spacingStale {
            styler.restyle(textStorage)
            layoutManager.ensureLayout(for: textContainer)
        }

        textStorage.enumerateAttribute(.mdImage, in: full) { value, range, _ in
            guard let path = value as? String else { return }
            guard let url = ImagePathResolver.resolve(path, relativeTo: documentURL),
                  let image = ImageCache.shared.image(for: url) else { return }
            let height = displayHeight(forImagePath: path)
            guard height > 0 else { return }
            let width = height * image.size.width / image.size.height

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var line = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            if line.height == 0 {
                line = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            }
            let frame = NSRect(x: origin.x, y: origin.y + line.maxY + 8, width: width, height: height)

            let view: NSImageView
            if let existing = imageViews[range] {
                view = existing
            } else {
                view = PassThroughImageView()
                view.imageScaling = .scaleProportionallyUpOrDown
                view.wantsLayer = true
                view.layer?.cornerRadius = 8
                view.layer?.masksToBounds = true
                addSubview(view)
                imageViews[range] = view
            }
            view.image = image
            if view.frame != frame { view.frame = frame }
            seen.insert(range)
        }

        for (range, view) in imageViews where !seen.contains(range) {
            view.removeFromSuperview()
            imageViews[range] = nil
        }
        needsImageLayout = false
    }

    // MARK: - Paste & drop

    // Rich types are listed so Paste validates (and ⌘V fires) for an RTF/HTML-only pasteboard;
    // they are pasted as their plain text, see `plainText(on:)`.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .png, .tiff, .string, .rtf, .rtfd, .html]
    }

    /// Feed cards take image drops anywhere on the card, so their editors only accept text drags.
    var acceptsImageDrops = true { didSet { updateDragTypeRegistration() } }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        acceptsImageDrops ? [.fileURL, .png, .tiff, .string] : [.string]
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // A drag carrying both text and an image still reaches a card editor; append the image like the card does.
        if !acceptsImageDrops, ImageStore.hasMedia(on: pboard) {
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
        if insertImages(from: pboard) { return true }
        if [.string, .rtf, .rtfd, .html].contains(type), let s = EditorTextView.plainText(on: pboard) {
            insertText(s, replacementRange: selectedRange())
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    // NSTextView.pasteAsPlainText silently did nothing here, so paste the string ourselves.
    override func paste(_ sender: Any?) {
        if insertImages(from: .general) { return }
        if let s = EditorTextView.plainText(on: .general) {
            insertText(s, replacementRange: selectedRange())
        }
    }

    /// Plain text for a paste; falls back to the text of rich (RTF/HTML) content when no plain-text type is present.
    static func plainText(on pboard: NSPasteboard) -> String? {
        if let s = pboard.string(forType: .string) { return s }
        if let rich = pboard.readObjects(forClasses: [NSAttributedString.self], options: nil)?.first as? NSAttributedString {
            return rich.string
        }
        if let data = pboard.data(forType: .rtf), let rtf = NSAttributedString(rtf: data, documentAttributes: nil) {
            return rtf.string
        }
        if let data = pboard.data(forType: .html), let html = NSAttributedString(html: data, documentAttributes: nil) {
            return html.string
        }
        return nil
    }

    /// The first editor under `root` that is actually on screen (not hidden, not scrolled out of view),
    /// used to route ⌘V when nothing in the window has focus. Falls back to the first editor at all.
    static func firstVisible(in root: NSView) -> EditorTextView? {
        var all: [EditorTextView] = []
        collectEditors(in: root, into: &all)
        // SwiftUI's ScrollView clips without NSClipView, so `visibleRect` is useless here; test the
        // editor's frame in the window's content coordinates instead (convert accounts for scrolling).
        let onScreen = all.first { editor in
            let frame = editor.convert(editor.bounds, to: root)
            return frame.intersects(root.bounds) && frame.height > 0
        }
        return onScreen ?? all.first
    }

    private static func collectEditors(in view: NSView, into result: inout [EditorTextView]) {
        if let editor = view as? EditorTextView, !editor.isHiddenOrHasHiddenAncestor { result.append(editor) }
        for sub in view.subviews { collectEditors(in: sub, into: &result) }
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }

    @discardableResult
    private func insertImages(from pboard: NSPasteboard) -> Bool {
        guard ImageStore.hasMedia(on: pboard) else { return false }
        guard let documentURL else {
            ImageStore.promptToSave(in: window)
            return true
        }
        guard let paths = ImageStore(documentURL: documentURL).storeMedia(from: pboard) else { return false }
        insertImageMarkdown(paths: paths)
        return true
    }

    func insertImageMarkdown(paths: [String]) {
        let string = self.string as NSString
        let sel = selectedRange()
        var prefix = ""
        if sel.location > 0, string.character(at: sel.location - 1) != 10 { prefix = "\n" }
        var suffix = "\n"
        if sel.location + sel.length < string.length, string.character(at: sel.location + sel.length) == 10 { suffix = "" }
        insertText(prefix + ImageStore.markdown(for: paths) + suffix, replacementRange: sel)
        onImageInserted?()
    }
}

private final class PassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
