import AppKit

extension NSAttributedString.Key {
    /// Syntax characters (`**`, `#`, `>` …) that are hidden unless the cursor is in the paragraph.
    static let mdMarker = NSAttributedString.Key("mdMarker")
    /// The `-` / `*` / `+` of an unordered list item; drawn as a bullet glyph.
    static let mdBullet = NSAttributedString.Key("mdBullet")
    /// Set on a standalone image paragraph; value is the markdown path string.
    static let mdImage = NSAttributedString.Key("mdImage")
    static let mdCodeBackground = NSAttributedString.Key("mdCodeBackground")
    static let mdQuote = NSAttributedString.Key("mdQuote")
    static let mdRule = NSAttributedString.Key("mdRule")
    /// First character of a fully hidden line; laid out as zero-width whitespace so the line keeps its height.
    static let mdKeepLine = NSAttributedString.Key("mdKeepLine")
}

struct EditorTheme {
    var body: NSFont
    var mono: NSFont
    var text: NSColor
    var secondary: NSColor
    var accent: NSColor
    var codeBackground: NSColor
    var lineHeightMultiple: CGFloat
    var paragraphSpacing: CGFloat = 10
    var headingFontOverride: ((Int) -> NSFont)? = nil
    /// False for platforms with no inline formatting (LinkedIn): markers still hide, but bold/italic/strike/code stay regular text.
    var rendersEmphasis = true

    static let wysiwyg = EditorTheme(
        body: .systemFont(ofSize: 17, weight: .regular),
        mono: .monospacedSystemFont(ofSize: 14.5, weight: .regular),
        text: .textColor,
        secondary: .tertiaryLabelColor,
        accent: .controlAccentColor,
        codeBackground: NSColor.labelColor.withAlphaComponent(0.055),
        lineHeightMultiple: 1.45
    )

    static let raw = EditorTheme(
        body: .monospacedSystemFont(ofSize: 14, weight: .regular),
        mono: .monospacedSystemFont(ofSize: 14, weight: .regular),
        text: .textColor,
        secondary: .secondaryLabelColor,
        accent: .controlAccentColor,
        codeBackground: .clear,
        lineHeightMultiple: 1.5
    )

    /// Compact theme for post bodies embedded in feed cards: platform font size, flat headings.
    static func post(size: CGFloat, text: NSColor, secondary: NSColor, accent: NSColor, codeBackground: NSColor,
                     lineHeightMultiple: CGFloat = 1.3) -> EditorTheme {
        EditorTheme(
            body: .systemFont(ofSize: size),
            mono: .monospacedSystemFont(ofSize: size - 1.5, weight: .regular),
            text: text,
            secondary: secondary,
            accent: accent,
            codeBackground: codeBackground,
            lineHeightMultiple: lineHeightMultiple,
            paragraphSpacing: 0,
            headingFontOverride: { _ in .systemFont(ofSize: size, weight: .bold) }
        )
    }

    func headingFont(level: Int) -> NSFont {
        if let headingFontOverride { return headingFontOverride(level) }
        switch level {
        case 1: return .systemFont(ofSize: 32, weight: .bold)
        case 2: return .systemFont(ofSize: 25, weight: .bold)
        case 3: return .systemFont(ofSize: 20, weight: .semibold)
        default: return .systemFont(ofSize: 17, weight: .semibold)
        }
    }
}

/// Applies markdown styling to an NSTextStorage in place. Never changes characters.
final class MarkdownStyler {
    var theme: EditorTheme = .wysiwyg
    var raw = false
    /// Returns the display height for an image path given the current column width.
    var imageHeight: (String) -> CGFloat = { _ in 0 }
    /// Document editor only: a local image that fails to load keeps its source line visible.
    var revealsBrokenImages = false

    private static let inlineCode = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private static let boldItalic = try! NSRegularExpression(pattern: "(\\*\\*\\*|___)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(pattern: "(?<![\\w*_])(\\*|_)(?=\\S)([^*_\\n]+?)(?<=\\S)\\1(?!\\w)")
    private static let strike = try! NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let link = try! NSRegularExpression(pattern: "(?<!!)\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    private static let inlineImage = MarkdownParser.imageRegex

    /// Post themes render like the platforms do: blank lines are the only paragraph spacing, headings are plain bold lines.
    private var flat: Bool { theme.headingFontOverride != nil }

    func restyle(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let string = storage.string as NSString

        storage.beginEditing()
        defer { storage.endEditing() }

        let base = NSMutableParagraphStyle()
        base.lineHeightMultiple = theme.lineHeightMultiple
        base.paragraphSpacing = raw ? 0 : theme.paragraphSpacing
        storage.setAttributes([
            .font: theme.body,
            .foregroundColor: theme.text,
            .paragraphStyle: base,
        ], range: full)

        var inCode = false
        var codeLanguageLine = false
        string.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, paraRange, _, _ in
            let lineRange = paraRange
            let line = string.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCode.toggle()
                codeLanguageLine = inCode
                self.apply(storage, lineRange, font: self.theme.mono, color: self.theme.secondary)
                self.hiddenLine(storage, lineRange)
                storage.addAttribute(.mdCodeBackground, value: true, range: lineRange)
                self.paragraph(storage, lineRange) { p in
                    p.paragraphSpacing = 0
                    p.lineHeightMultiple = 1.2
                }
                return
            }
            if inCode {
                _ = codeLanguageLine
                self.apply(storage, lineRange, font: self.theme.mono, color: self.theme.text)
                storage.addAttribute(.mdCodeBackground, value: true, range: lineRange)
                self.paragraph(storage, lineRange) { p in
                    p.paragraphSpacing = 0
                    p.lineHeightMultiple = 1.3
                }
                return
            }

            if self.raw {
                self.styleRawLine(storage, lineRange, line: line, trimmed: trimmed)
                return
            }

            self.styleLine(storage, lineRange, line: line, trimmed: trimmed, string: string)
        }
    }

    // MARK: - Raw view: monospace with light syntax tinting.

    private func styleRawLine(_ storage: NSTextStorage, _ range: NSRange, line: String, trimmed: String) {
        if MarkdownParser.heading(trimmed) != nil {
            apply(storage, range, font: .monospacedSystemFont(ofSize: theme.body.pointSize, weight: .bold), color: theme.text)
        }
        if MarkdownParser.isRule(trimmed) || trimmed.hasPrefix(">") {
            apply(storage, range, font: theme.mono, color: theme.secondary)
        }
        for regex in [Self.inlineCode, Self.boldItalic, Self.bold, Self.italic, Self.strike, Self.link, Self.inlineImage] {
            regex.enumerateMatches(in: storage.string, range: range) { m, _, _ in
                guard let m else { return }
                let r = m.range
                if regex === Self.bold || regex === Self.boldItalic {
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: self.theme.body.pointSize, weight: .bold), range: r)
                } else if regex === Self.link || regex === Self.inlineImage {
                    storage.addAttribute(.foregroundColor, value: self.theme.accent, range: m.range(at: regex === Self.link ? 2 : 2))
                } else {
                    storage.addAttribute(.foregroundColor, value: self.theme.secondary, range: NSRange(location: r.location, length: regex === Self.inlineCode ? 1 : (regex === Self.strike ? 2 : m.range(at: 1).length)))
                }
            }
        }
    }

    // MARK: - WYSIWYG

    private func styleLine(_ storage: NSTextStorage, _ range: NSRange, line: String, trimmed: String, string: NSString) {
        let leading = line.count - line.drop(while: { $0 == " " || $0 == "\t" }).count

        if let (level, _) = MarkdownParser.heading(trimmed) {
            let font = theme.headingFont(level: level)
            apply(storage, range, font: font, color: theme.text)
            let markerLen = level + 1
            marker(storage, NSRange(location: range.location + leading, length: min(markerLen, range.length - leading)))
            paragraph(storage, range) { p in
                p.lineHeightMultiple = self.flat ? self.theme.lineHeightMultiple : 1.2
                p.paragraphSpacingBefore = self.flat ? 0 : (level == 1 ? 14 : 10)
                p.paragraphSpacing = self.flat ? self.theme.paragraphSpacing : 6
            }
            inline(storage, range)
            return
        }

        if MarkdownParser.isRule(trimmed) {
            apply(storage, range, font: theme.mono.withSize(13), color: theme.secondary)
            hiddenLine(storage, range)
            storage.addAttribute(.mdRule, value: true, range: range)
            paragraph(storage, range) { p in
                p.alignment = .center
                p.paragraphSpacing = self.flat ? 0 : 14
                p.paragraphSpacingBefore = self.flat ? 0 : 6
            }
            return
        }

        if let img = MarkdownParser.standaloneImage(trimmed) {
            apply(storage, range, font: theme.mono.withSize(12), color: theme.secondary)
            let h = imageHeight(img.path)
            // A local file that failed to load keeps its source line visible instead of vanishing silently.
            let isRemote = img.path.hasPrefix("http://") || img.path.hasPrefix("https://")
            if h > 0 || isRemote || !revealsBrokenImages { hiddenLine(storage, range) }
            storage.addAttribute(.mdImage, value: img.path, range: range)
            paragraph(storage, range) { p in
                p.paragraphSpacing = h + 16
                p.lineHeightMultiple = 1.2
            }
            return
        }

        if trimmed.hasPrefix(">") {
            var markerLen = 1
            if trimmed.count > 1, trimmed[trimmed.index(after: trimmed.startIndex)] == " " { markerLen = 2 }
            marker(storage, NSRange(location: range.location + leading, length: min(markerLen, range.length - leading)))
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            // Starts after the (hidden) marker: a zero-width glyph at the paragraph start is laid out on the
            // previous line, which drags the quote bar one line up.
            // An empty `>` line has nothing after the marker, so the bar is hung on its newline instead.
            let markerEnd = min(range.location + leading + markerLen, NSMaxRange(range))
            let quoteLength = min(max(NSMaxRange(range) - markerEnd, 1), storage.length - markerEnd)
            if quoteLength > 0 {
                storage.addAttribute(.mdQuote, value: true, range: NSRange(location: markerEnd, length: quoteLength))
            }
            paragraph(storage, range) { p in
                p.headIndent = 22
                p.firstLineHeadIndent = 22
                p.paragraphSpacing = self.flat ? 0 : 4
            }
            inline(storage, range)
            return
        }

        // Left-trim only, so an empty item (`- ` with nothing after it) still counts as a list line.
        let leftTrimmed = String(line.dropFirst(leading)).trimmingCharacters(in: .newlines)
        if let item = MarkdownParser.listItem(leftTrimmed) {
            let prefixLen = leftTrimmed.count - item.content.count
            let markerRange = NSRange(location: range.location + leading, length: min(prefixLen, range.length - leading))
            storage.addAttribute(.foregroundColor, value: item.ordered ? theme.accent : theme.text, range: markerRange)
            if !item.ordered, !raw, markerRange.length > 0 {
                storage.addAttribute(.mdBullet, value: true, range: NSRange(location: markerRange.location, length: 1))
            }
            let indent = CGFloat(leading) * 10
            paragraph(storage, range) { p in
                p.firstLineHeadIndent = indent
                p.headIndent = indent + (item.ordered ? 24 : 18)
                p.paragraphSpacing = self.flat ? 0 : 3
            }
            inline(storage, range)
            return
        }

        inline(storage, range)
    }

    private func inline(_ storage: NSTextStorage, _ range: NSRange) {
        let text = storage.string

        Self.inlineCode.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m else { return }
            self.marker(storage, NSRange(location: m.range.location, length: 1))
            self.marker(storage, NSRange(location: m.range.location + m.range.length - 1, length: 1))
            guard self.theme.rendersEmphasis else { return }
            storage.addAttribute(.font, value: self.theme.mono, range: m.range(at: 1))
            storage.addAttribute(.mdCodeBackground, value: true, range: m.range(at: 1))
        }

        var boldItalicRanges: [NSRange] = []
        Self.boldItalic.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m else { return }
            boldItalicRanges.append(m.range)
            self.marker(storage, NSRange(location: m.range.location, length: 3))
            self.marker(storage, NSRange(location: m.range.location + m.range.length - 3, length: 3))
            if self.theme.rendersEmphasis {
                self.addTrait(storage, m.range(at: 2), trait: .boldFontMask)
                self.addTrait(storage, m.range(at: 2), trait: .italicFontMask)
            }
        }
        // `***x***` also matches the bold regex (as `**` + `*x` + `**`); leave those to the pass above.
        func insideBoldItalic(_ r: NSRange) -> Bool {
            boldItalicRanges.contains { NSIntersectionRange($0, r).length > 0 }
        }

        Self.bold.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m, !insideBoldItalic(m.range) else { return }
            self.marker(storage, NSRange(location: m.range.location, length: 2))
            self.marker(storage, NSRange(location: m.range.location + m.range.length - 2, length: 2))
            if self.theme.rendersEmphasis { self.addTrait(storage, m.range(at: 2), trait: .boldFontMask) }
        }

        Self.italic.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m, !insideBoldItalic(m.range) else { return }
            self.marker(storage, NSRange(location: m.range.location, length: 1))
            self.marker(storage, NSRange(location: m.range.location + m.range.length - 1, length: 1))
            if self.theme.rendersEmphasis { self.addTrait(storage, m.range(at: 2), trait: .italicFontMask) }
        }

        Self.strike.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m else { return }
            self.marker(storage, NSRange(location: m.range.location, length: 2))
            self.marker(storage, NSRange(location: m.range.location + m.range.length - 2, length: 2))
            guard self.theme.rendersEmphasis else { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: self.theme.secondary, range: m.range(at: 1))
        }

        Self.link.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m else { return }
            self.marker(storage, NSRange(location: m.range.location, length: 1))
            let textRange = m.range(at: 1)
            let tail = NSRange(location: textRange.location + textRange.length, length: m.range.location + m.range.length - (textRange.location + textRange.length))
            self.marker(storage, tail)
            storage.addAttribute(.foregroundColor, value: self.theme.accent, range: textRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            storage.addAttribute(.underlineColor, value: self.theme.accent.withAlphaComponent(0.4), range: textRange)
        }

        Self.inlineImage.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: self.theme.secondary, range: m.range)
            storage.addAttribute(.font, value: self.theme.mono.withSize(13), range: m.range)
        }
    }

    // MARK: - Helpers

    private func apply(_ storage: NSTextStorage, _ range: NSRange, font: NSFont, color: NSColor) {
        storage.addAttribute(.font, value: font, range: range)
        storage.addAttribute(.foregroundColor, value: color, range: range)
    }

    private func marker(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0, range.location + range.length <= storage.length else { return }
        storage.addAttribute(.mdMarker, value: true, range: range)
        storage.addAttribute(.foregroundColor, value: theme.secondary, range: range)
    }

    /// Hides a whole line but keeps its first glyph as zero-width whitespace so the typesetter still
    /// produces a real line fragment; an all-null-glyph paragraph collapses into the previous line.
    private func hiddenLine(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        marker(storage, range)
        storage.addAttribute(.mdKeepLine, value: true, range: NSRange(location: range.location, length: 1))
    }

    private func paragraph(_ storage: NSTextStorage, _ range: NSRange, _ edit: (NSMutableParagraphStyle) -> Void) {
        let existing = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle.default
        let p = existing.mutableCopy() as! NSMutableParagraphStyle
        edit(p)
        storage.addAttribute(.paragraphStyle, value: p, range: range)
    }

    private func addTrait(_ storage: NSTextStorage, _ range: NSRange, trait: NSFontTraitMask) {
        storage.enumerateAttribute(.font, in: range) { value, r, _ in
            let font = (value as? NSFont) ?? theme.body
            let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: r)
        }
    }
}
