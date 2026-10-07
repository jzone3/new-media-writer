import AppKit

// Run with scripts/test-export.sh. Covers copy payload spacing for Slack and LinkedIn
// and pins X output so spacing changes can't leak into it.

var failures = 0

func expect(_ name: String, _ actual: String?, _ expected: String) {
    guard actual != expected else { return print("ok   \(name)") }
    failures += 1
    print("FAIL \(name)\n  expected: \(expected.debugDescription)\n  actual:   \((actual ?? "nil").debugDescription)")
}

func doc(_ body: String) -> String {
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
}

let source = "Line one\nline two\n\n**Bold** and _it_\n\n\n\nAfter three blanks\n- a\n- b\n\n> quote\n\n```\ncode\n\nmore\n```\nEnd"
let br = "<div><br></div>"

let slack = Exporter.slack(source)
expect("slack plain keeps line breaks, blank lines and mrkdwn", slack.plain,
       "Line one\nline two\n\n*Bold* and _it_\n\n\n\nAfter three blanks\n\n• a\n• b\n\n> quote\n\n```\ncode\n\nmore\n```\n\nEnd")
expect("slack html: <br> per newline, blocks on their own lines", slack.html, doc(
    "Line one<br>line two<br><br><b>Bold</b> and <i>it</i><br><br><br><br>"
    + "After three blanks<br><ul><li>a</li><li>b</li></ul><br>"
    + "<blockquote>quote</blockquote><br><pre><code>code\n\nmore</code></pre><br>End"))
expect("slack plain-only matches slack plain", Exporter.slackPlain(source).plain, slack.plain)

let linkedIn = Exporter.linkedIn(source)
expect("linkedin plain keeps blank lines", linkedIn.plain,
       "Line one\nline two\n\nBold and it\n\n\n\nAfter three blanks\n\n• a\n• b\n\n“quote”\n\ncode\n\nmore\n\nEnd")
expect("linkedin html is one unformatted div per line", linkedIn.html, doc(
    "<div>Line one</div><div>line two</div>\(br)<div>Bold and it</div>\(br)\(br)\(br)<div>After three blanks</div>\(br)"
    + "<div>• a</div><div>• b</div>\(br)<div>“quote”</div>\(br)<div>code</div>\(br)<div>more</div>\(br)<div>End</div>"))
expect("linkedin escapes html", Exporter.linkedIn("a < b & c").html, doc("<div>a &lt; b &amp; c</div>"))

expect("linkedin html keeps repeated and leading spaces", Exporter.linkedIn("a  b").html, doc("<div>a &nbsp;b</div>"))
expect("slack html keeps blank lines inside quotes", Exporter.slack("> first\n>\n> last").html,
       doc("<blockquote>first<br><br>last</blockquote>"))
expect("slack html: two blocks in a row", Exporter.slack("> q\n\n- a").html, doc("<blockquote>q</blockquote><br><ul><li>a</li></ul>"))

expect("x copy keeps an autolinked bare URL as just the URL", Exporter.xPost("Try www.newmediawriter.app today").plain,
       "Try www.newmediawriter.app today")
expect("x copy keeps a bare https URL as just the URL", Exporter.xPost("https://newmediawriter.app/").plain, "https://newmediawriter.app/")
expect("x copy still exposes a titled link's URL", Exporter.xPost("[the app](https://newmediawriter.app)").plain,
       "the app (https://newmediawriter.app)")

expect("leading, trailing and skipped-block blank lines", Exporter.slack("\n\nA\n\n---\n\n\nB\n\n\n").plain, "A\n\n\nB")

let longPost = String(repeating: "a", count: 300)
expect("x fold after the 280th character", MarkdownRender.xFoldOffset(in: longPost, limit: 280).map(String.init) ?? "none", "279")
expect("x fold: exactly 280 characters need no fold", MarkdownRender.xFoldOffset(in: String(repeating: "a", count: 280), limit: 280).map(String.init) ?? "none", "none")
expect("x fold counts emoji as 2", MarkdownRender.xFoldOffset(in: String(repeating: "😀", count: 150), limit: 280).map(String.init) ?? "none", "279")
let withURL = String(repeating: "a", count: 270) + " https://newmediawriter.app/some/very/long/path/that/x/shortens tail"
expect("x fold counts a URL as 23 and shows it whole", MarkdownRender.xFoldOffset(in: withURL, limit: 280).map(String.init) ?? "none",
       String((withURL as NSString).range(of: " tail").location - 1))
expect("x fold: a 23-weight URL fits where its letters would not", MarkdownRender.xFoldOffset(in: String(repeating: "a", count: 256) + " https://newmediawriter.app/some/very/long/path", limit: 280).map(String.init) ?? "none", "none")

let x = Exporter.xThread(source)
expect("x plain unchanged", x.plain,
       "Line one\nline two\n\nBold and it\n\nAfter three blanks\n\n• a\n• b\n\n“quote”\n\ncode\n\nmore\n\nEnd")
expect("x html unchanged", x.html, doc(
    "<p>Line one<br>line two</p><p><b>Bold</b> and <i>it</i></p><p>After three blanks</p><p>• a<br>• b</p>"
    + "<p>“quote”</p><p>code</p><p>more</p><p>End</p>"))

// PDF document render: block structure as text (attachments are U+FFFC), images resolved through the caller.
let pdfSource = "# Title\n\nPara **bold** [link](https://x.y)\nsoft break\n\n- a\n- b\n\n1. one\n\n> q1\n> q2\n\n```\ncode\n```\n\n![alt](assets/missing.png)\n\n---\n\nEnd"
let pdf = PDFRender.attributed(pdfSource, contentWidth: 468) { _ in nil }
expect("pdf render keeps block order and list markers", pdf.string,
       "Title\nPara bold link\u{2028}soft break\n•\ta\n•\tb\n1.\tone\nq1\u{2028}q2\ncode\nalt\n\u{FFFC}\nEnd")
var sawH1 = false, sawLink = false, sawMono = false
pdf.enumerateAttributes(in: NSRange(location: 0, length: pdf.length)) { attrs, range, _ in
    let s = (pdf.string as NSString).substring(with: range)
    if s.hasPrefix("Title"), let f = attrs[.font] as? NSFont, f.pointSize == 24 { sawH1 = true }
    if s == "link", attrs[.link] != nil { sawLink = true }
    if s.hasPrefix("code"), let f = attrs[.font] as? NSFont, f.fontDescriptor.symbolicTraits.contains(.monoSpace) { sawMono = true }
}
expect("pdf render styles heading, link and code", "\(sawH1) \(sawLink) \(sawMono)", "true true true")

let tallPNG = FileManager.default.temporaryDirectory.appendingPathComponent("nmw-tall.png")
let tall = NSImage(size: NSSize(width: 200, height: 2000), flipped: false) { r in NSColor.black.setFill(); r.fill(); return true }
try! NSBitmapImageRep(data: tall.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: tallPNG)
let tallDoc = PDFRender.attributed("![t](tall.png)", contentWidth: 468, contentHeight: 648) { _ in tallPNG }
let bounds = (tallDoc.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.bounds ?? .zero
expect("pdf render fits a tall image on one page", "\(Int(bounds.width))x\(Int(bounds.height))", "62x628")

if failures > 0 {
    print("\(failures) failed")
    exit(1)
}
print("all passed")
