import SwiftUI

/// Editable post body embedded in a feed card. Same WYSIWYG engine as the Markdown view, styled like
/// the host platform and sized to its content; edits flow back into the shared document via `onChange`.
struct PostEditor: NSViewRepresentable {
    var text: String
    var theme: EditorTheme
    var documentURL: URL?
    var foldAfter: Int? = nil
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
        textView.revealsMarkersOnlyWhenFocused = true
        textView.topInset = 0
        textView.usesFindBar = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.delegate = context.coordinator
        textView.documentURL = documentURL
        textView.styler.theme = theme
        textView.foldAfterVisibleCharacters = foldAfter
        textView.takesFocusOnAppear = takesFocusOnAppear
        textView.string = text
        textView.restyleAndRelayout()
        context.coordinator.textView = textView
        return textView
    }

    func updateNSView(_ textView: EditorTextView, context: Context) {
        context.coordinator.parent = self
        textView.documentURL = documentURL
        textView.foldAfterVisibleCharacters = foldAfter
        // Thread segments arrive trimmed; don't yank a trailing newline the user just typed.
        let current = textView.string
        if current != text,
           current.trimmingCharacters(in: .whitespacesAndNewlines) != text.trimmingCharacters(in: .whitespacesAndNewlines) {
            let sel = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
            textView.restyleAndRelayout()
        }
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

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.onChange(textView.string)
        }

        func undoManager(for view: NSTextView) -> UndoManager? { parent.undoManager }
    }
}
