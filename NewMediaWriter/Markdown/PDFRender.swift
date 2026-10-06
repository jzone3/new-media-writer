import AppKit

/// Lays the Markdown out as a plain printed document: black system type on white,
/// real headings, lists, quotes, code and images. Nothing platform-specific.
enum PDFRender {
    static let bodySize: CGFloat = 12

    /// `resolveImage` turns a Markdown image path into a local file URL (nil to skip).
    static func attributed(_ text: String, contentWidth: CGFloat, resolveImage: (String) -> URL?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let blocks = MarkdownParser.parse(text)
        for block in blocks {
            let piece = render(block, contentWidth: contentWidth, resolveImage: resolveImage)
            guard piece.length > 0 else { continue }
            if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: lastAttributes(of: out))) }
            out.append(piece)
        }
        return out
    }

    // MARK: Blocks

    private static func render(_ block: MDBlock, contentWidth: CGFloat, resolveImage: (String) -> URL?) -> NSAttributedString {
        switch block {
        case .heading(let level, let t):
            let size: CGFloat = switch level { case 1: 24; case 2: 18; case 3: 14.5; default: bodySize }
            let style = paragraph(spacingBefore: level == 1 ? 6 : 14, spacing: 6)
            return inline(t, font: .systemFont(ofSize: size, weight: .bold), style: style)
        case .paragraph(let t):
            return inline(softBreaks(t), font: body, style: paragraph(spacing: 10))
        case .quote(let lines):
            let style = paragraph(spacing: 10)
            style.headIndent = 18
            style.firstLineHeadIndent = 18
            return inline(lines.joined(separator: lineSeparator), font: body, style: style, color: .init(white: 0.35, alpha: 1))
        case .code(_, let code):
            let style = paragraph(spacing: 10)
            style.headIndent = 12
            style.firstLineHeadIndent = 12
            style.lineSpacing = 1
            return NSAttributedString(string: softBreaks(code), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: bodySize - 1.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.25, alpha: 1),
                .paragraphStyle: style
            ])
        case .list(let ordered, let items):
            let out = NSMutableAttributedString()
            for (i, item) in items.enumerated() {
                let style = paragraph(spacing: i == items.count - 1 ? 10 : 3)
                style.headIndent = 22
                style.firstLineHeadIndent = 4
                style.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
                let marker = NSAttributedString(string: (ordered ? "\(i + 1)." : "•") + "\t",
                                                attributes: [.font: body, .foregroundColor: NSColor.black, .paragraphStyle: style])
                if i > 0 { out.append(NSAttributedString(string: "\n", attributes: [.font: body, .paragraphStyle: style])) }
                out.append(marker)
                out.append(inline(item, font: body, style: style))
            }
            return out
        case .image(let alt, let path):
            guard let url = resolveImage(path), url.isFileURL, let image = NSImage(contentsOf: url), image.size.width > 0 else {
                return alt.isEmpty ? NSAttributedString() : inline(alt, font: body, style: paragraph(spacing: 10), color: .init(white: 0.5, alpha: 1))
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            let scale = min(1, contentWidth / image.size.width)
            attachment.bounds = CGRect(x: 0, y: 0, width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            let out = NSMutableAttributedString(attachment: attachment)
            out.addAttributes([.paragraphStyle: paragraph(spacing: 10), .font: body], range: NSRange(location: 0, length: out.length))
            return out
        case .rule:
            let attachment = NSTextAttachment()
            attachment.image = NSImage(size: CGSize(width: contentWidth, height: 1), flipped: false) { rect in
                NSColor(white: 0.8, alpha: 1).setFill()
                rect.fill()
                return true
            }
            attachment.bounds = CGRect(x: 0, y: 4, width: contentWidth, height: 1)
            let out = NSMutableAttributedString(attachment: attachment)
            out.addAttributes([.paragraphStyle: paragraph(spacingBefore: 6, spacing: 14), .font: body], range: NSRange(location: 0, length: out.length))
            return out
        }
    }

    // MARK: Inline

    /// Line breaks inside one block stay in the same paragraph (no paragraph spacing between them).
    private static let lineSeparator = "\u{2028}"

    private static func softBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: lineSeparator)
    }

    private static var body: NSFont { .systemFont(ofSize: bodySize) }

    private static func inline(_ text: String, font: NSFont, style: NSParagraphStyle, color: NSColor = .black) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let attributed = MarkdownInline.attributed(text)
        let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1.5, weight: .regular)
        for run in attributed.runs {
            let s = String(attributed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if intent.contains(.code) {
                runFont = mono
            } else if !traits.isEmpty {
                runFont = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color, .paragraphStyle: style]
            if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link {
                attrs[.link] = link
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: s, attributes: attrs))
        }
        return out
    }

    private static func paragraph(spacingBefore: CGFloat = 0, spacing: CGFloat) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2.5
        p.paragraphSpacingBefore = spacingBefore
        p.paragraphSpacing = spacing
        return p
    }

    private static func lastAttributes(of s: NSAttributedString) -> [NSAttributedString.Key: Any] {
        guard s.length > 0 else { return [:] }
        var attrs = s.attributes(at: s.length - 1, effectiveRange: nil)
        attrs[.link] = nil
        attrs[.underlineStyle] = nil
        attrs[.attachment] = nil
        return attrs
    }
}
