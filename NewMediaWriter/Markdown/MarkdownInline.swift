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

    static func stripImages(_ text: String) -> String {
        let ns = NSMutableString(string: text)
        MarkdownParser.imageRegex.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return (ns as String).replacingOccurrences(of: "\n\n\n", with: "\n\n")
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
