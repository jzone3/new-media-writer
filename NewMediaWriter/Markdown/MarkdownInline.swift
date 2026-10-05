import SwiftUI

enum MarkdownInline {
    /// Attributed string with inline presentation intents (bold, italic, code, strikethrough, links).
    static func attributed(_ text: String) -> AttributedString {
        let withoutImages = stripImages(text)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let parsed = try? AttributedString(markdown: withoutImages, options: options) {
            return parsed
        }
        return AttributedString(withoutImages)
    }

    /// Plain text with all inline syntax removed.
    static func plain(_ text: String) -> String {
        String(attributed(text).characters)
    }

    /// Like `attributed`, but `[title](url)` becomes "title (url)" so the destination survives
    /// on services that render plain text.
    static func attributedExposingLinks(_ text: String) -> AttributedString {
        let source = attributed(text)
        var out = AttributedString()
        var linkText = ""
        let runs = Array(source.runs)
        for (i, run) in runs.enumerated() {
            var piece = AttributedString(source[run.range])
            if let link = run.link {
                // A label with inline formatting spans several runs; append the URL once, after the last.
                linkText += String(piece.characters)
                let next = i + 1 < runs.count ? runs[i + 1].link : nil
                if next != link {
                    if !isBareURL(linkText, link) {
                        piece += AttributedString(" (\(link.absoluteString))")
                    }
                    linkText = ""
                }
                piece.link = nil
            }
            out += piece
        }
        return out
    }

    /// Plain text where links keep their URL.
    static func plainExposingLinks(_ text: String) -> String {
        String(attributedExposingLinks(text).characters)
    }

    /// True when the visible text already is the URL (autolinked bare URL).
    static func isBareURL(_ shown: String, _ link: URL) -> Bool {
        let a = shown.trimmingCharacters(in: .whitespaces)
        let b = link.absoluteString
        return a == b || a + "/" == b || a == b + "/"
    }

    static func stripImages(_ text: String) -> String {
        let ns = NSMutableString(string: text)
        MarkdownParser.imageRegex.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return (ns as String)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
    }
}

extension AttributedString {
    /// Apply a base font while keeping bold/italic/code intents from markdown.
    func styled(baseFont: Font, color: Color, codeFont: Font? = nil, linkColor: Color? = nil) -> AttributedString {
        var out = self
        out.font = baseFont
        out.foregroundColor = color
        for run in out.runs {
            guard let intent = run.inlinePresentationIntent else {
                if run.link != nil, let linkColor { out[run.range].foregroundColor = linkColor }
                continue
            }
            var font = baseFont
            if intent.contains(.stronglyEmphasized) { font = font.bold() }
            if intent.contains(.emphasized) { font = font.italic() }
            if intent.contains(.code) { font = codeFont ?? .system(.body, design: .monospaced) }
            out[run.range].font = font
            if intent.contains(.strikethrough) { out[run.range].strikethroughStyle = .single }
            if run.link != nil, let linkColor { out[run.range].foregroundColor = linkColor }
        }
        return out
    }
}
