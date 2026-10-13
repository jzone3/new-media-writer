import SwiftUI

/// Document editor text size (⌘+ / ⌘− / ⌘0), shared by all windows. Feed previews keep platform sizes.
enum EditorTextSize {
    static let key = "editorTextScale"
    static let steps: [Double] = [0.7, 0.8, 0.9, 1, 1.15, 1.3, 1.5, 1.75, 2, 2.5]

    static var scale: Double {
        get { UserDefaults.standard.object(forKey: key) as? Double ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var canGrow: Bool { scale < steps.last! - 0.001 }
    static var canShrink: Bool { scale > steps.first! + 0.001 }

    static func bigger() { scale = steps.first { $0 > scale + 0.001 } ?? steps.last! }
    static func smaller() { scale = steps.last { $0 < scale - 0.001 } ?? steps.first! }
    static func reset() { scale = 1 }
}

struct MarkdownEditor: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    var raw: Bool
    @AppStorage(EditorTextSize.key) private var textScale: Double = 1
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
        textView.handlesTextSizeKeys = true
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
        } else if abs(textView.styler.theme.scale - textScale) > 0.001 {
            applyMode(textView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }

    private func applyMode(_ textView: EditorTextView) {
        textView.emojiPopup.hide()
        textView.styler.raw = raw
        let scale = CGFloat(textScale)
        textView.styler.theme = (raw ? EditorTheme.raw : .wysiwyg).scaled(scale)
        textView.hideMarkers = !raw
        // The column grows with the text so a line holds about the same number of words.
        textView.maxColumnWidth = (raw ? 760 : 720) * scale
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
