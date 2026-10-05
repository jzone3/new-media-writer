import SwiftUI

/// Flattens markdown blocks to the text form a given social network would display.
enum MarkdownRender {
    /// X supports bold/italic/strikethrough for Premium users but no headings, lists or code.
    static func xAttributed(_ text: String) -> AttributedString {
        let blocks = MarkdownParser.parse(text)
        var out = AttributedString()
        var first = true
        for block in blocks {
            var piece: AttributedString?
            switch block {
            case .heading(_, let t):
                var a = MarkdownInline.attributed(t)
                a.inlinePresentationIntent = .stronglyEmphasized
                piece = a
            case .paragraph(let t):
                piece = MarkdownInline.attributed(t)
            case .quote(let lines):
                piece = MarkdownInline.attributed(lines.map { "“\($0)”" }.joined(separator: "\n"))
            case .code(_, let code):
                piece = AttributedString(code)
            case .list(let ordered, let items):
                var a = AttributedString()
                for (i, item) in items.enumerated() {
                    if i > 0 { a += AttributedString("\n") }
                    a += AttributedString(ordered ? "\(i + 1). " : "• ")
                    a += MarkdownInline.attributed(item)
                }
                piece = a
            case .image, .rule:
                piece = nil
            }
            if let piece {
                if !first { out += AttributedString("\n\n") }
                out += piece
                first = false
            }
        }
        return out
    }

    /// LinkedIn has no formatting at all: bullets and line breaks survive, nothing else.
    static func plainText(_ text: String) -> String {
        let blocks = MarkdownParser.parse(text)
        var parts: [String] = []
        for block in blocks {
            switch block {
            case .heading(_, let t): parts.append(MarkdownInline.plain(t))
            case .paragraph(let t): parts.append(MarkdownInline.plain(t))
            case .quote(let lines): parts.append(lines.map { "“\(MarkdownInline.plain($0))”" }.joined(separator: "\n"))
            case .code(_, let code): parts.append(code)
            case .list(let ordered, let items):
                parts.append(items.enumerated().map { i, item in
                    (ordered ? "\(i + 1). " : "• ") + MarkdownInline.plain(item)
                }.joined(separator: "\n"))
            case .image, .rule: break
            }
        }
        return parts.joined(separator: "\n\n")
    }
}

extension Int {
    var formattedCount: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
