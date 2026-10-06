import AppKit
import SwiftUI

/// Builds the clipboard payload for each target so pasting into the real composer "just works".
enum Exporter {
    struct Payload {
        var plain: String
        var html: String? = nil
        var rich: NSAttributedString? = nil

        func copy() {
            let pb = NSPasteboard.general
            pb.clearContents()
            var types: [NSPasteboard.PasteboardType] = [.string]
            if html != nil { types.append(.html) }
            if rich != nil { types.append(.rtf) }
            pb.declareTypes(types, owner: nil)
            pb.setString(plain, forType: .string)
            if let html { pb.setData(Data(html.utf8), forType: .html) }
            if let rich, let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length),
                                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                pb.setData(rtf, forType: .rtf)
            }
        }
    }

    // MARK: Markdown

    static func markdown(_ text: String) -> Payload {
        Payload(plain: text)
    }

    // MARK: X

    /// Rich text (RTF + HTML) so bold/italic/strikethrough survive in the Premium composer; plain text fallback.
    static func xPost(_ segment: String) -> Payload {
        let attributed = MarkdownRender.xAttributed(segment)
        return Payload(plain: String(attributed.characters),
                       html: document(inlineHTML(attributed, paragraphs: true)),
                       rich: nsAttributed(attributed, baseFont: .systemFont(ofSize: 15)))
    }

    static func xThread(_ text: String) -> Payload {
        let segments = MarkdownParser.threadSegments(text)
        let attributed = segments.map { MarkdownRender.xAttributed($0) }
        let rich = NSMutableAttributedString()
        for (i, a) in attributed.enumerated() {
            if i > 0 { rich.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 15)])) }
            rich.append(nsAttributed(a, baseFont: .systemFont(ofSize: 15)))
        }
        return Payload(plain: attributed.map { String($0.characters) }.joined(separator: "\n\n"),
                       html: document(attributed.map { inlineHTML($0, paragraphs: true) }.joined(separator: "<p>&nbsp;</p>")),
                       rich: rich)
    }

    // MARK: LinkedIn

    /// Plain text plus line-per-`<div>` HTML: LinkedIn's rich composer drops the plain flavor's blank lines.
    static func linkedIn(_ text: String) -> Payload {
        let plain = MarkdownRender.plainText(text)
        return Payload(plain: plain, html: document(lineDivs(plain)))
    }

    // MARK: Slack

    /// mrkdwn as the plain flavor (what Slack parses when you paste text) plus HTML for the rich composer.
    static func slack(_ text: String) -> Payload {
        let blocks = MarkdownParser.parseSpaced(text)
        return Payload(plain: mrkdwn(blocks), html: slackHTML(blocks))
    }

    static func slackPlain(_ text: String) -> Payload {
        Payload(plain: mrkdwn(MarkdownParser.parseSpaced(text)))
    }

    static func mrkdwn(_ blocks: [(block: MDBlock, blankLinesBefore: Int)]) -> String {
        MarkdownRender.joinBlocks(blocks, separator: MarkdownRender.blankLines) { block in
            switch block {
            case .heading(_, let t):
                "*\(MarkdownInline.plain(t))*"
            case .paragraph(let t):
                inlineMrkdwn(t)
            case .quote(let lines):
                lines.map { "> " + inlineMrkdwn($0) }.joined(separator: "\n")
            case .code(_, let code):
                "```\n\(code)\n```"
            case .list(let ordered, let items):
                items.enumerated().map { i, item in
                    (ordered ? "\(i + 1). " : "• ") + inlineMrkdwn(item)
                }.joined(separator: "\n")
            case .image, .rule:
                nil
            }
        }
    }

    static func inlineMrkdwn(_ text: String) -> String {
        var out = ""
        let attributed = MarkdownInline.attributed(text)
        for run in attributed.runs {
            let s = String(attributed[run.range].characters)
            guard !s.isEmpty else { continue }
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { out += wrap(s, "`"); continue }
            var piece = s
            if let link = run.link {
                piece = MarkdownInline.isBareURL(piece, link) ? link.absoluteString : "<\(link.absoluteString)|\(piece)>"
            }
            if intent.contains(.strikethrough) { piece = wrap(piece, "~") }
            if intent.contains(.emphasized) { piece = wrap(piece, "_") }
            if intent.contains(.stronglyEmphasized) { piece = wrap(piece, "*") }
            out += piece
        }
        return out
    }

    /// Wraps the trimmed content so the markers hug the word (Slack ignores `* bold *`).
    private static func wrap(_ s: String, _ marker: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return s }
        let lead = s.prefix { $0 == " " }
        let trail = s.reversed().prefix { $0 == " " }
        return String(lead) + marker + trimmed + marker + String(trail)
    }

    // MARK: HTML

    /// Explicit UTF-8 charset: without it TextEdit & co. decode the HTML flavor as Latin-1 (“â€¢”).
    private static func document(_ body: String) -> String {
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
    }

    /// Rich composers like Slack's map each block element to one line and ignore `<p>` margins,
    /// so every blank line is spelled out as an empty `<div><br></div>`.
    static func slackHTML(_ blocks: [(block: MDBlock, blankLinesBefore: Int)]) -> String {
        let body = MarkdownRender.joinBlocks(blocks, separator: { String(repeating: emptyLine, count: $0) }) { block in
            switch block {
            case .heading(_, let t):
                "<div><b>\(inlineHTML(MarkdownInline.attributed(t), paragraphs: false))</b></div>"
            case .paragraph(let t):
                "<div>\(inlineHTML(MarkdownInline.attributed(t), paragraphs: false).replacingOccurrences(of: "\n", with: "<br>"))</div>"
            case .quote(let lines):
                "<blockquote>" + lines.map { "<div>\(inlineHTML(MarkdownInline.attributed($0), paragraphs: false))</div>" }.joined() + "</blockquote>"
            case .code(_, let code):
                "<pre><code>\(escape(code))</code></pre>"
            case .list(let ordered, let items):
                "<\(ordered ? "ol" : "ul")>" + items.map { "<li>\(inlineHTML(MarkdownInline.attributed($0), paragraphs: false))</li>" }.joined() + "</\(ordered ? "ol" : "ul")>"
            case .image, .rule:
                nil
            }
        }
        return document(body)
    }

    private static let emptyLine = "<div><br></div>"

    /// One `<div>` per line of plain text; empty lines become `<div><br></div>`.
    static func lineDivs(_ plain: String) -> String {
        plain.components(separatedBy: "\n").map { $0.isEmpty ? emptyLine : "<div>\(escape($0))</div>" }.joined()
    }

    static func inlineHTML(_ attributed: AttributedString, paragraphs: Bool) -> String {
        var out = ""
        for run in attributed.runs {
            var piece = escape(String(attributed[run.range].characters))
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { piece = "<code>\(piece)</code>" }
            if intent.contains(.stronglyEmphasized) { piece = "<b>\(piece)</b>" }
            if intent.contains(.emphasized) { piece = "<i>\(piece)</i>" }
            if intent.contains(.strikethrough) { piece = "<s>\(piece)</s>" }
            if let link = run.link { piece = "<a href=\"\(escape(link.absoluteString))\">\(piece)</a>" }
            out += piece
        }
        guard paragraphs else { return out }
        return out.components(separatedBy: "\n\n").map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }.joined()
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: RTF

    static func nsAttributed(_ attributed: AttributedString, baseFont: NSFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
        for run in attributed.runs {
            let s = String(attributed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var font = baseFont
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if intent.contains(.code) {
                font = mono
            } else if !traits.isEmpty {
                font = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(traits), size: baseFont.pointSize) ?? baseFont
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attrs[.link] = link }
            out.append(NSAttributedString(string: s, attributes: attrs))
        }
        return out
    }
}
