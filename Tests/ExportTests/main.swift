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
expect("slack html spells out every blank line", slack.html, doc(
    "<div>Line one<br>line two</div>\(br)<div><b>Bold</b> and <i>it</i></div>\(br)\(br)\(br)"
    + "<div>After three blanks</div>\(br)<ul><li>a</li><li>b</li></ul>\(br)"
    + "<blockquote><div>quote</div></blockquote>\(br)<pre><code>code\n\nmore</code></pre>\(br)<div>End</div>"))
expect("slack plain-only matches slack plain", Exporter.slackPlain(source).plain, slack.plain)

let linkedIn = Exporter.linkedIn(source)
expect("linkedin plain keeps blank lines", linkedIn.plain,
       "Line one\nline two\n\nBold and it\n\n\n\nAfter three blanks\n\n• a\n• b\n\n“quote”\n\ncode\n\nmore\n\nEnd")
expect("linkedin html is one unformatted div per line", linkedIn.html, doc(
    "<div>Line one</div><div>line two</div>\(br)<div>Bold and it</div>\(br)\(br)\(br)<div>After three blanks</div>\(br)"
    + "<div>• a</div><div>• b</div>\(br)<div>“quote”</div>\(br)<div>code</div>\(br)<div>more</div>\(br)<div>End</div>"))
expect("linkedin escapes html", Exporter.linkedIn("a < b & c").html, doc("<div>a &lt; b &amp; c</div>"))

expect("leading, trailing and skipped-block blank lines", Exporter.slack("\n\nA\n\n---\n\n\nB\n\n\n").plain, "A\n\n\nB")

let x = Exporter.xThread(source)
expect("x plain unchanged", x.plain,
       "Line one\nline two\n\nBold and it\n\nAfter three blanks\n\n• a\n• b\n\n“quote”\n\ncode\n\nmore\n\nEnd")
expect("x html unchanged", x.html, doc(
    "<p>Line one<br>line two</p><p><b>Bold</b> and <i>it</i></p><p>After three blanks</p><p>• a<br>• b</p>"
    + "<p>“quote”</p><p>code</p><p>more</p><p>End</p>"))

if failures > 0 {
    print("\(failures) failed")
    exit(1)
}
print("all passed")
