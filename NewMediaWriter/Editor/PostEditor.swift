import SwiftUI

/// Editable post body embedded in a feed card. Same WYSIWYG engine as the Markdown view, styled like
/// the host platform and sized to its content; edits flow back into the shared document via `onChange`.
struct PostEditor: NSViewRepresentable {
    var text: String
    var theme: EditorTheme
    var documentURL: URL?
    var placeholder: String? = nil
    var foldAfter: Int? = nil
    var foldStyle = FoldMarkerStyle()
    var takesFocusOnAppear = false
    var onChange: (String) -> Void
    @Environment(\.undoManager) private var undoManager

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> EditorTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.fillsWidth = true
        textView.showsImages = false
        textView.acceptsImageDrops = false
        textView.revealsMarkersOnlyWhenFocused = true
        textView.topInset = 0
        textView.usesFindBar = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.delegate = context.coordinator
        textView.documentURL = documentURL
        textView.placeholder = placeholder
        textView.styler.theme = theme
        textView.foldAfterVisibleCharacters = foldAfter
        textView.foldStyle = foldStyle
        textView.takesFocusOnAppear = takesFocusOnAppear
        textView.string = text
        textView.restyleAndRelayout()
        context.coordinator.textView = textView
        return textView
    }

    static func dismantleNSView(_ textView: EditorTextView, coordinator: Coordinator) {
        // Text views register undo operations with themselves as the unretained target; switching
        // views destroys the text view, so a later ⌘Z would message a freed object.
        (textView.undoManager ?? coordinator.parent.undoManager)?.removeAllActions(withTarget: textView)
    }

    func updateNSView(_ textView: EditorTextView, context: Context) {
        context.coordinator.parent = self
        textView.documentURL = documentURL
        textView.placeholder = placeholder
        textView.foldAfterVisibleCharacters = foldAfter
        textView.foldStyle = foldStyle
        let current = textView.string
        guard current != text else { return }
        // While the user is typing, SwiftUI can call this with a value one keystroke behind the text
        // view (a newline grows the card, which triggers an extra layout pass). Echoes of our own
        // edits must never overwrite what has been typed since; thread segments also arrive trimmed,
        // so compare loosely. Edits from elsewhere (Markdown view, undo, Add another post) only
        // happen while the card is not focused and always win.
        let isTyping = textView.window?.firstResponder === textView
        if isTyping, context.coordinator.isEcho(text) { return }
        context.coordinator.sentTexts.removeAll()
        let sel = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        textView.restyleAndRelayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: EditorTextView, context: Context) -> CGSize? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? container.containerSize.width
        if abs(container.containerSize.width - width) > 0.5 {
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let minHeight = theme.body.pointSize * theme.lineHeightMultiple
        let foldBottom = textView.foldMarkerBottom ?? 0
        return CGSize(width: width, height: max(ceil(used.height), minHeight, ceil(foldBottom)) + 2)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PostEditor
        weak var textView: EditorTextView?

        init(_ parent: PostEditor) { self.parent = parent }

        /// Recent strings reported through `onChange`, so stale re-renders of them are recognised.
        var sentTexts: [String] = []

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            sentTexts.append(textView.string)
            if sentTexts.count > 16 { sentTexts.removeFirst(sentTexts.count - 16) }
            parent.onChange(textView.string)
        }

        func isEcho(_ text: String) -> Bool {
            let incoming = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return sentTexts.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == incoming }
        }

        func textDidEndEditing(_ notification: Notification) {
            sentTexts.removeAll()
        }

        func undoManager(for view: NSTextView) -> UndoManager? { parent.undoManager }
    }
}
