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
                var a = MarkdownInline.attributedExposingLinks(t)
                a.inlinePresentationIntent = .stronglyEmphasized
                piece = a
            case .paragraph(let t):
                piece = MarkdownInline.attributedExposingLinks(t)
            case .quote(let lines):
                piece = MarkdownInline.attributedExposingLinks(lines.map { "“\($0)”" }.joined(separator: "\n"))
            case .code(_, let code):
                piece = AttributedString(code)
            case .list(let ordered, let items):
                var a = AttributedString()
                for (i, item) in items.enumerated() {
                    if i > 0 { a += AttributedString("\n") }
                    a += AttributedString(ordered ? "\(i + 1). " : "• ")
                    a += MarkdownInline.attributedExposingLinks(item)
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
            case .heading(_, let t): parts.append(MarkdownInline.plainExposingLinks(t))
            case .paragraph(let t): parts.append(MarkdownInline.plainExposingLinks(t))
            case .quote(let lines): parts.append(lines.map { "“\(MarkdownInline.plainExposingLinks($0))”" }.joined(separator: "\n"))
            case .code(_, let code): parts.append(code)
            case .list(let ordered, let items):
                parts.append(items.enumerated().map { i, item in
                    (ordered ? "\(i + 1). " : "• ") + MarkdownInline.plainExposingLinks(item)
                }.joined(separator: "\n"))
            case .image, .rule: break
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Characters as X counts them (twitter-text v3): any URL is 23, emoji are 2,
    /// CJK and most non-Latin scalars are 2, everything else is 1.
    static func xCount(_ text: String) -> Int {
        var total = 0
        var cursor = text.startIndex
        let ns = text as NSString
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let links = detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in links {
            guard let range = Range(match.range, in: text), range.lowerBound >= cursor else { continue }
            total += weightedLength(text[cursor..<range.lowerBound]) + 23
            cursor = range.upperBound
        }
        total += weightedLength(text[cursor...])
        return total
    }

    private static func weightedLength(_ text: Substring) -> Int {
        var total = 0
        for character in text {
            let scalars = character.unicodeScalars
            if scalars.count > 1 && scalars.contains(where: { $0.properties.isEmoji }) || scalars.first?.properties.isEmojiPresentation == true {
                total += 2
                continue
            }
            for scalar in scalars {
                switch scalar.value {
                case 0...4351, 8192...8205, 8208...8223, 8242...8247: total += 1
                default: total += 2
                }
            }
        }
        return total
    }
}

extension Int {
    var formattedCount: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
