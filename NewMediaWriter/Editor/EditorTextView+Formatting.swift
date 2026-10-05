import AppKit

/// ⌘B / ⌘I / ⌘E / ⌘K toggle markdown markers around the selection instead of rich-text attributes.
extension EditorTextView {
    @objc func toggleBoldface(_ sender: Any?) { toggleMarker("**") }
    @objc func toggleItalics(_ sender: Any?) { toggleMarker("*") }
    @objc func toggleInlineCode(_ sender: Any?) { toggleMarker("`") }

    @objc func insertLink(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        let selected = ns.substring(with: sel)
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = clip.hasPrefix("http://") || clip.hasPrefix("https://") ? clip : ""
        let text = "[\(selected)](\(url))"
        guard shouldChangeText(in: sel, replacementString: text) else { return }
        insertText(text, replacementRange: sel)
        // Caret goes to whichever slot is still empty: the label, else the URL.
        let caret = selected.isEmpty ? sel.location + 1 : sel.location + (selected as NSString).length + 3 + (url as NSString).length
        setSelectedRange(NSRange(location: caret, length: 0))
    }

    /// Wraps the selection in `marker`, or unwraps it when the markers are already there
    /// (inside or immediately around the selection). With no selection, inserts an empty pair.
    private func toggleMarker(_ marker: String) {
        let ns = string as NSString
        let sel = selectedRange()
        let m = marker.count

        func replace(_ range: NSRange, with text: String, select: NSRange) {
            guard shouldChangeText(in: range, replacementString: text) else { return }
            insertText(text, replacementRange: range)
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
            replace(sel, with: inner, select: NSRange(location: sel.location, length: (inner as NSString).length))
            return
        }

        let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
        if outer.location >= 0, NSMaxRange(outer) <= ns.length,
           ns.substring(with: NSRange(location: outer.location, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker {
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
