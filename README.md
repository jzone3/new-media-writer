# New Media Writer

A minimalist, focus-first Markdown writing app for macOS. Write once in Markdown, then preview the same file as it would appear in the feed:

- **Markdown** — Typora-style WYSIWYG (syntax hides when the cursor leaves the line) or raw source.
- **X** — post (threads split on `---`, Premium 25k counter, bold/italic preserved) or long-form **Article**.
- **LinkedIn** — full post with the "…more" fold marked at ~210 chars, 3,000 cap.
- **Slack** — channel view with mrkdwn-style rendering.

Images pasted or dropped into the editor are copied to an `assets/` folder next to the document and inserted as relative Markdown links; they render inline in the editor and as media in every preview.

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
| Markdown / Raw | ⌘1 / ⇧⌘1 |
| X post / X article | ⌘2 / ⇧⌘2 |
| LinkedIn | ⌘3 |
| Slack | ⌘4 |

Set your name, handle, headline, avatar and Slack channel in **Settings (⌘,)** so previews look like you.
