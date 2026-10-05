import AppKit

/// ⌘B / ⌘I / ⌘E / ⌘K toggle markdown markers around the selection instead of rich-text attributes.
/// All edits go through `insertText(_:replacementRange:)`, which runs shouldChangeText/didChangeText
/// and registers undo itself; calling shouldChangeText here as well would register the undo twice.
extension EditorTextView {
    @objc func toggleBoldface(_ sender: Any?) { toggleMarker("**") }
    @objc func toggleItalics(_ sender: Any?) { toggleMarker("*") }
    @objc func toggleInlineCode(_ sender: Any?) { toggleMarker("`") }

    @objc func insertLink(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        let selected = ns.substring(with: sel)
        guard selected.rangeOfCharacter(from: .newlines) == nil else { NSSound.beep(); return }
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = clip.hasPrefix("http://") || clip.hasPrefix("https://") ? clip : ""
        let text = "[\(selected)](\(url))"
        breakUndoCoalescing()
        insertText(text, replacementRange: sel)
        breakUndoCoalescing()
        // Caret goes to whichever slot is still empty: the label, else the URL.
        let caret = selected.isEmpty ? sel.location + 1 : sel.location + (selected as NSString).length + 3 + (url as NSString).length
        setSelectedRange(NSRange(location: caret, length: 0))
    }

    @objc func toggleBulletedList(_ sender: Any?) { toggleList(ordered: false) }
    @objc func toggleNumberedList(_ sender: Any?) { toggleList(ordered: true) }

    /// Enter inside a list item starts the next item; Enter on an empty item ends the list.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        guard sel.length == 0 else { super.insertNewline(sender); return }
        let para = ns.paragraphRange(for: sel)
        let line = ns.substring(with: para).trimmingCharacters(in: .newlines)
        let leading = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = String(line.dropFirst(leading.count))
        guard let item = MarkdownParser.listItem(rest) else { super.insertNewline(sender); return }
        let prefix = String(rest.prefix(rest.count - item.content.count))
        let contentStart = para.location + (leading as NSString).length + (prefix as NSString).length
        guard sel.location >= contentStart else { super.insertNewline(sender); return }

        if item.content.trimmingCharacters(in: .whitespaces).isEmpty {
            let markerRange = NSRange(location: para.location, length: contentStart - para.location)
            insertText("", replacementRange: markerRange)
            return
        }

        var next = prefix
        if item.ordered, let n = Int(prefix.prefix { $0.isNumber }) {
            next = "\(n + 1)" + prefix.drop { $0.isNumber }
        }
        let insert = "\n" + leading + next
        insertText(insert, replacementRange: sel)
    }

    /// Adds `- ` / `1. ` to every paragraph in the selection, or strips the markers when they are all already items.
    private func toggleList(ordered: Bool) {
        let ns = string as NSString
        let sel = selectedRange()
        let range = ns.paragraphRange(for: sel)
        let text = ns.substring(with: range)
        let trailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if trailingNewline { lines.removeLast() }
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allItems = !content.isEmpty && content.allSatisfy {
            MarkdownParser.listItem($0.trimmingCharacters(in: .whitespaces))?.ordered == ordered
        }
        var n = 1
        let out = lines.map { line -> String in
            let leading = String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = String(line.dropFirst(leading.count))
            if rest.isEmpty { return line }
            let body = MarkdownParser.listItem(rest)?.content ?? rest
            if allItems { return leading + body }
            defer { n += 1 }
            return leading + (ordered ? "\(n). " : "- ") + body
        }
        let newText = out.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        guard newText != text else { return }
        breakUndoCoalescing()
        insertText(newText, replacementRange: range)
        breakUndoCoalescing()
        if sel.length == 0, lines.count == 1 {
            let delta = (newText as NSString).length - (text as NSString).length
            setSelectedRange(NSRange(location: max(range.location, sel.location + delta), length: 0))
        } else {
            setSelectedRange(NSRange(location: range.location, length: (newText as NSString).length - (trailingNewline ? 1 : 0)))
        }
    }

    /// Wraps the selection in `marker`, or unwraps it when the markers are already there
    /// (inside or immediately around the selection). With no selection, inserts an empty pair.
    private func toggleMarker(_ marker: String) {
        let ns = string as NSString
        let sel = selectedRange()
        let m = marker.count

        func replace(_ range: NSRange, with text: String, select: NSRange) {
            breakUndoCoalescing()
            insertText(text, replacementRange: range)
            breakUndoCoalescing()
            setSelectedRange(select)
        }

        if sel.length == 0 {
            let before = NSRange(location: sel.location - m, length: m)
            let after = NSRange(location: sel.location, length: m)
            if before.location >= 0, NSMaxRange(after) <= ns.length,
               ns.substring(with: before) == marker, ns.substring(with: after) == marker {
                replace(NSUnionRange(before, after), with: "", select: NSRange(location: before.location, length: 0))
            } else {
                replace(sel, with: marker + marker, select: NSRange(location: sel.location + m, length: 0))
            }
            return
        }

        let selected = ns.substring(with: sel)
        if selected.count >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(m).dropLast(m))
            // `**one** and **two**` is two spans, not one wrapped selection.
            if !inner.contains(marker) {
                replace(sel, with: inner, select: NSRange(location: sel.location, length: (inner as NSString).length))
                return
            }
        }

        // Unwrap only when the run of marker characters hugging the selection is exactly `marker`,
        // so ⌘I on the word inside `**word**` adds italics instead of eating the bold markers.
        let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
        let markerChar = marker.first!
        if outer.location >= 0, NSMaxRange(outer) <= ns.length,
           ns.substring(with: NSRange(location: outer.location, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker,
           outer.location == 0 || Character(UnicodeScalar(ns.character(at: outer.location - 1))!) != markerChar,
           NSMaxRange(outer) == ns.length || Character(UnicodeScalar(ns.character(at: NSMaxRange(outer)))!) != markerChar {
            replace(outer, with: selected, select: NSRange(location: outer.location, length: sel.length))
            return
        }

        // Keep surrounding whitespace outside the markers so `** word**` never happens.
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let leadCount = selected.prefix { $0.isWhitespace || $0.isNewline }.count
        let lead = String(selected.prefix(leadCount))
        let trail = String(selected.suffix(selected.count - leadCount - trimmed.count))
        let text = lead + marker + trimmed + marker + trail
        let selStart = sel.location + (lead as NSString).length + m
        replace(sel, with: text, select: NSRange(location: selStart, length: (trimmed as NSString).length))
    }
}
