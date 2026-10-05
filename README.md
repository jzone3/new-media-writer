# New Media Writer

A minimalist, focus-first Markdown writing app for macOS. Write once in Markdown, then preview the same file as it would appear in the feed:

- **Plaintext** — the raw Markdown source.
- **Markdown** — Typora-style WYSIWYG (syntax hides when the cursor leaves the line).
- **X** — post (threads split on `---`, Premium 25k counter, bold/italic preserved).
- **LinkedIn** — full post with the "…more" fold marked at ~210 chars, 3,000 cap.
- **Slack** — channel view with mrkdwn-style rendering.

Images pasted or dropped into the editor are copied to an `assets/` folder next to the document and inserted as relative Markdown links; they render inline in the editor and as media in every preview.

Every view has a **Copy** button (⇧⌘C) that puts the document on the clipboard in the format that view's composer expects: raw Markdown, rich text for X (per-post for threads), plain text for LinkedIn, and Slack mrkdwn (`*bold*`, `_italic_`, `•` bullets, `>` quotes, fenced code) plus an HTML flavor for Slack's rich composer.

## Build

Requires Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project NewMediaWriter.xcodeproj -scheme NewMediaWriter -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open "build/Build/Products/Debug/New Media Writer.app"
```

Or open `NewMediaWriter.xcodeproj` in Xcode and run.

## Shortcuts

| Action | Keys |
| --- | --- |
| Plaintext | ⌘1 |
| Markdown | ⌘2 |
| X | ⌘3 |
| LinkedIn | ⌘4 |
| Slack | ⌘5 |
| Copy for current view | ⇧⌘C |

Set your name, handle, headline, avatar and Slack channel in **Settings (⌘,)** so previews look like you.
