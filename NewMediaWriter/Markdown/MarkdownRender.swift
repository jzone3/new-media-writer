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
    /// Deliberate extra blank lines between blocks are kept, as the feed shows them.
    static func plainText(_ text: String) -> String {
        joinBlocks(MarkdownParser.parseSpaced(text), separator: blankLines) { block in
            switch block {
            case .heading(_, let t): MarkdownInline.plainExposingLinks(t)
            case .paragraph(let t): MarkdownInline.plainExposingLinks(t)
            case .quote(let lines): lines.map { "“\(MarkdownInline.plainExposingLinks($0))”" }.joined(separator: "\n")
            case .code(_, let code): code
            case .list(let ordered, let items):
                items.enumerated().map { i, item in
                    (ordered ? "\(i + 1). " : "• ") + MarkdownInline.plainExposingLinks(item)
                }.joined(separator: "\n")
            case .image, .rule: nil
            }
        }
    }

    /// "\n" plus one more "\n" per blank line.
    static func blankLines(_ count: Int) -> String {
        String(repeating: "\n", count: count + 1)
    }

    /// Joins rendered blocks, putting `separator(n)` between them where n is the number of blank
    /// source lines (at least one) before the next rendered block. Skipped blocks (nil) keep the larger gap.
    static func joinBlocks(_ spaced: [(block: MDBlock, blankLinesBefore: Int)],
                           separator: (Int) -> String,
                           render: (MDBlock) -> String?) -> String {
        var out = ""
        var gap = 0
        var first = true
        for (block, before) in spaced {
            gap = max(gap, before)
            guard let piece = render(block) else { continue }
            if !first { out += separator(max(1, gap)) }
            out += piece
            first = false
            gap = 0
        }
        return out
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
            total += weightedLength(text[cursor..<range.lowerBound]) + xURLWeight
            cursor = range.upperBound
        }
        total += weightedLength(text[cursor...])
        return total
    }

    private static func weightedLength(_ text: Substring) -> Int {
        text.reduce(0) { $0 + xWeight(of: $1) }
    }

    /// X's weight of one character outside a URL: emoji 2, CJK and most non-Latin scalars 2, everything else 1.
    static func xWeight(of character: Character) -> Int {
        let scalars = character.unicodeScalars
        if scalars.count > 1 && scalars.contains(where: { $0.properties.isEmoji }) || scalars.first?.properties.isEmojiPresentation == true {
            return 2
        }
        var total = 0
        for scalar in scalars {
            switch scalar.value {
            case 0...4351, 8192...8205, 8208...8223, 8242...8247: total += 1
            default: total += 2
            }
        }
        return total
    }

    static let xURLWeight = 23

    /// UTF-16 offset of the last character X shows above its "Show more" fold, or nil when the text
    /// weighs `limit` or less. A URL straddling the limit is shown whole.
    static func xFoldOffset(in text: String, limit: Int) -> Int? {
        let ns = text as NSString
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let links = detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
        var total = 0
        var lastShown: Int?
        var i = 0
        var nextLink = 0
        while i < ns.length {
            while nextLink < links.count, links[nextLink].location < i { nextLink += 1 }
            let range: NSRange
            if nextLink < links.count, links[nextLink].location == i {
                range = links[nextLink]
                total += xURLWeight
            } else {
                range = ns.rangeOfComposedCharacterSequence(at: i)
                total += ns.substring(with: range).reduce(0) { $0 + xWeight(of: $1) }
            }
            if lastShown == nil, total >= limit { lastShown = NSMaxRange(range) - 1 }
            i = NSMaxRange(range)
        }
        return total > limit ? lastShown : nil
    }
}

extension Int {
    var formattedCount: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
