import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    var raw: Bool
    @Environment(\.undoManager) private var undoManager

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.documentURL = fileURL
        textView.takesFocusOnAppear = true
        textView.string = document.text
        context.coordinator.textView = textView
        applyMode(textView)

        scroll.documentView = textView
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        // The text view registers undo operations with itself as the unretained target; switching
        // views destroys it, so a later ⌘Z would message a freed object.
        guard let textView = scroll.documentView as? EditorTextView else { return }
        (textView.undoManager ?? coordinator.parent.undoManager)?.removeAllActions(withTarget: textView)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? EditorTextView else { return }
        context.coordinator.parent = self
        textView.documentURL = fileURL
        if textView.string != document.text {
            let sel = textView.selectedRange()
            textView.string = document.text
            textView.restyleAndRelayout()
            let loc = min(sel.location, (document.text as NSString).length)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
        }
        if textView.styler.raw != raw {
            applyMode(textView)
        }
    }

    private func applyMode(_ textView: EditorTextView) {
        textView.emojiPopup.hide()
        textView.styler.raw = raw
        textView.styler.theme = raw ? .raw : .wysiwyg
        textView.hideMarkers = !raw
        textView.maxColumnWidth = raw ? 760 : 720
        textView.restyleAndRelayout()
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: EditorTextView?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let s = textView.string
            if parent.document.text != s {
                parent.document.text = s
            }
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.undoManager
        }
    }
}
