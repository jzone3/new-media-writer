import Foundation

enum MDBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote([String])
    case code(language: String?, code: String)
    case list(ordered: Bool, items: [String])
    case image(alt: String, path: String)
    case rule
}

struct MDImage: Equatable, Hashable {
    let alt: String
    let path: String
}

/// A small, forgiving Markdown block parser. Inline formatting is left as-is in the
/// block text and handled by `MarkdownInline`.
enum MarkdownParser {
    static func parse(_ text: String) -> [MDBlock] {
        parseSpaced(text).map(\.block)
    }

    /// Blocks plus the number of blank source lines in front of each, so exports can keep
    /// deliberate extra spacing that `parse` throws away.
    static func parseSpaced(_ text: String) -> [(block: MDBlock, blankLinesBefore: Int)] {
        var blocks: [(block: MDBlock, blankLinesBefore: Int)] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []
        var blank = 0
        var paragraphBlank = 0

        func append(_ block: MDBlock) {
            blocks.append((block, blank))
            blank = 0
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append((.paragraph(paragraph.joined(separator: "\n")), paragraphBlank))
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                blank += 1
                i += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1
                append(.code(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                append(.rule)
                i += 1
                continue
            }

            if let (level, content) = heading(trimmed) {
                flushParagraph()
                append(.heading(level: level, text: content))
                i += 1
                continue
            }

            if let img = standaloneImage(trimmed) {
                flushParagraph()
                append(.image(alt: img.alt, path: img.path))
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var content = String(t.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoteLines.append(content)
                    i += 1
                }
                append(.quote(quoteLines))
                continue
            }

            if let first = listItem(trimmed) {
                flushParagraph()
                var items: [String] = [first.content]
                let ordered = first.ordered
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let item = listItem(t), item.ordered == ordered {
                        items.append(item.content)
                        i += 1
                    } else if !t.isEmpty, lines[i].hasPrefix("  "), !items.isEmpty {
                        items[items.count - 1] += " " + t
                        i += 1
                    } else {
                        break
                    }
                }
                append(.list(ordered: ordered, items: items))
                continue
            }

            if paragraph.isEmpty {
                paragraphBlank = blank
                blank = 0
            }
            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    /// Splits the document into thread segments on horizontal rules (`---`).
    struct ThreadSegment {
        /// Everything between the surrounding `---` lines (untrimmed), in UTF-16 units of the source.
        var range: NSRange
        var text: String
    }

    /// `keepTrailingEmpty` keeps an empty post after a final `---` so the X view can show it as a composer.
    static func thread(_ text: String, keepTrailingEmpty: Bool = false) -> [ThreadSegment] {
        let ns = text as NSString
        var raw: [NSRange] = []
        var inCode = false
        var start = 0
        var offset = 0
        for line in text.components(separatedBy: "\n") {
            let len = (line as NSString).length
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { inCode.toggle() }
            if !inCode, isRule(t) {
                raw.append(NSRange(location: start, length: offset - start))
                start = min(offset + len + 1, ns.length)
            }
            offset += len + 1
        }
        raw.append(NSRange(location: start, length: ns.length - start))
        let segments = raw.map {
            ThreadSegment(range: $0, text: ns.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var nonEmpty = segments.filter { !$0.text.isEmpty }
        if keepTrailingEmpty, !nonEmpty.isEmpty, let last = segments.last, last.text.isEmpty { nonEmpty.append(last) }
        return nonEmpty.isEmpty ? [ThreadSegment(range: NSRange(location: 0, length: ns.length), text: "")] : nonEmpty
    }

    static func threadSegments(_ text: String) -> [String] { thread(text).map(\.text) }

    static func isRule(_ t: String) -> Bool {
        guard t.count >= 3 else { return false }
        let set = Set(t.replacingOccurrences(of: " ", with: ""))
        return set.count == 1 && (set.first == "-" || set.first == "*" || set.first == "_") && t.replacingOccurrences(of: " ", with: "").count >= 3
    }

    static func heading(_ t: String) -> (Int, String)? {
        var level = 0
        var idx = t.startIndex
        while idx < t.endIndex, t[idx] == "#", level < 6 {
            level += 1
            idx = t.index(after: idx)
        }
        guard level > 0, idx < t.endIndex, t[idx] == " " else { return nil }
        var content = String(t[idx...]).trimmingCharacters(in: .whitespaces)
        while content.hasSuffix("#") { content.removeLast() }
        return (level, content.trimmingCharacters(in: .whitespaces))
    }

    static let imageRegex = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)

    static func standaloneImage(_ t: String) -> MDImage? {
        let range = NSRange(t.startIndex..., in: t)
        guard let m = imageRegex.firstMatch(in: t, range: range), m.range == range else { return nil }
        return MDImage(alt: String(t[Range(m.range(at: 1), in: t)!]), path: String(t[Range(m.range(at: 2), in: t)!]))
    }

    static func images(in text: String) -> [MDImage] {
        let ns = text as NSString
        return imageRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            MDImage(alt: ns.substring(with: $0.range(at: 1)), path: ns.substring(with: $0.range(at: 2)))
        }
    }

    /// Removes the `index`-th `![]()` reference (in `images(in:)` order); a line left blank is removed with it.
    static func removingImage(at index: Int, from text: String) -> String {
        let ns = text as NSString
        let matches = imageRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.indices.contains(index) else { return text }
        let match = matches[index].range
        let line = ns.lineRange(for: match)
        let rest = (ns.substring(with: line) as NSString)
            .replacingCharacters(in: NSRange(location: match.location - line.location, length: match.length), with: "")
        let cut = rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? line : match
        return ns.replacingCharacters(in: cut, with: "")
    }

    static func listItem(_ t: String) -> (ordered: Bool, content: String)? {
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
            return (false, String(t.dropFirst(2)))
        }
        var digits = ""
        var idx = t.startIndex
        while idx < t.endIndex, t[idx].isNumber { digits.append(t[idx]); idx = t.index(after: idx) }
        if !digits.isEmpty, idx < t.endIndex, t[idx] == "." || t[idx] == ")" {
            let after = t.index(after: idx)
            if after < t.endIndex, t[after] == " " {
                return (true, String(t[t.index(after: after)...]))
            }
        }
        return nil
    }

    /// First H1 in the document, used as the title for article-style previews.
    static func title(in blocks: [MDBlock]) -> String? {
        for case let .heading(level, text) in blocks where level == 1 {
            return MarkdownInline.plain(text)
        }
        return nil
    }
}
