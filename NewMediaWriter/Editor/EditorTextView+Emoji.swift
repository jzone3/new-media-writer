import AppKit

/// `:fi` pops a Slack-style emoji list under the caret; `:fire:` typed in full converts on the closing colon.
extension EditorTextView {
    private static let nameChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_+-"))

    /// The `:query` run ending at the caret, if the caret sits inside one.
    private func emojiTrigger() -> (range: NSRange, query: String, closed: Bool)? {
        let sel = selectedRange()
        guard sel.length == 0 else { return nil }
        let ns = string as NSString
        let para = ns.paragraphRange(for: sel)
        let before = ns.substring(with: NSRange(location: para.location, length: sel.location - para.location))
        var closed = false
        var body = Substring(before)
        if body.hasSuffix(":") { closed = true; body = body.dropLast() }
        guard let colon = body.lastIndex(of: ":") else { return nil }
        let name = body[body.index(after: colon)...]
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ Self.nameChars.contains($0) }) else { return nil }
        if colon > body.startIndex {
            let prev = body[body.index(before: colon)]
            guard !(prev.isLetter || prev.isNumber) else { return nil }
        }
        let start = para.location + (String(body[..<colon]) as NSString).length
        return (NSRange(location: start, length: sel.location - start), String(name), closed)
    }

    func updateEmojiSuggestions() {
        guard let trigger = emojiTrigger(), let window else { emojiPopup.hide(); return }
        if trigger.closed {
            emojiPopup.hide()
            if let hit = EmojiCatalog.exact(trigger.query.lowercased()) {
                replace(trigger.range, with: hit.emoji)
            }
            return
        }
        guard trigger.query.count >= 2 else { emojiPopup.hide(); return }
        let items = EmojiCatalog.search(trigger.query)
        guard !items.isEmpty else { emojiPopup.hide(); return }
        emojiPopup.onPick = { [weak self] entry in self?.insertEmoji(entry) }
        emojiPopup.show(items, below: caretScreenRect(), in: window)
    }

    private func insertEmoji(_ entry: EmojiCatalog.Entry) {
        emojiPopup.hide()
        guard let trigger = emojiTrigger() else { return }
        replace(trigger.range, with: entry.emoji + " ")
    }

    /// Own undo step, so ⌘Z brings the shortcode back instead of also eating the words typed before it.
    private func replace(_ range: NSRange, with text: String) {
        breakUndoCoalescing()
        insertText(text, replacementRange: range)
        breakUndoCoalescing()
    }

    /// Arrow keys, Return/Tab and Escape drive the popup while it is showing.
    func handleEmojiCommand(_ selector: Selector) -> Bool {
        guard emojiPopup.isVisible else { return false }
        switch selector {
        case #selector(moveDown(_:)): emojiPopup.move(1)
        case #selector(moveUp(_:)): emojiPopup.move(-1)
        case #selector(insertNewline(_:)), #selector(insertTab(_:)): emojiPopup.pickSelected()
        case #selector(cancelOperation(_:)): emojiPopup.hide()
        default: return false
        }
        return true
    }

    private func caretScreenRect() -> NSRect {
        firstRect(forCharacterRange: NSRange(location: selectedRange().location, length: 0), actualRange: nil)
    }
}
