import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    // Per-window; new windows start in the view used most recently.
    @State private var mode: ViewMode = .lastUsed
    // The view actually on screen. Feed previews are expensive to build (one text view per post),
    // so a switch first draws the pill, background and a skeleton, then builds the view a frame later.
    @State private var shownMode: ViewMode = .lastUsed
    @Environment(\.colorScheme) private var colorScheme
    @State private var pickerShown = false
    @StateObject private var cardFinder = CardFinder()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ViewSwitcher(mode: $mode)
                .padding(.top, 8)
                .padding(.trailing, 12)

            if shownMode.isEditor, mode == shownMode {
                CopyButton(payload: { Exporter.markdown(document.text) })
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            if pickerShown {
                ViewPicker(mode: $mode, shown: $pickerShown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .background(background)
        .ignoresSafeArea()
        .focusedSceneValue(\.viewMode, $mode)
        .focusedSceneValue(\.viewPickerShown, $pickerShown)
        .focusedSceneValue(\.pdfExport, PDFExportContext(document: document, fileURL: fileURL))
        .animation(.easeOut(duration: 0.12), value: pickerShown)
        // Nothing animates on `mode`: the pill and the skeleton must cut over in the same frame, because the
        // main thread stalls right after while the feed builds and a crossfade would freeze part-way.
        // Only the skeleton -> real view hand-off fades, on `shownMode`.
        .animation(.easeOut(duration: 0.15), value: shownMode)
        .onChange(of: mode) { _, new in
            ViewMode.lastUsed = new
            if new.isEditor && shownMode.isEditor {
                // Markdown ↔ Plaintext restyle the same text view; nothing heavy to defer.
                shownMode = new
                return
            }
            // Let the frame with the moved pill and the skeleton reach the screen before the
            // heavy view is built. The main thread blocks during that build, so anything shown
            // meanwhile must be static (a spinner would freeze).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                shownMode = mode
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if mode != shownMode {
            ViewSkeleton(mode: mode)
        } else if shownMode.isEditor {
            MarkdownEditor(document: document, fileURL: fileURL, raw: shownMode == .plaintext)
        } else {
            VStack(spacing: 0) {
                CardFindBar(finder: cardFinder)
                    .frame(height: cardFinder.barHeight)
                feed
            }
            .environment(\.cardFinder, cardFinder)
        }
    }

    @ViewBuilder
    private var feed: some View {
        switch shownMode {
        case .markdown, .plaintext:
            EmptyView()
        case .xPost:
            ProfileReader { profile in XPostFeedView(document: document, baseURL: fileURL, profile: profile) }
        case .linkedin:
            ProfileReader { profile in LinkedInFeedView(document: document, baseURL: fileURL, profile: profile) }
        case .slack:
            ProfileReader { profile in SlackView(document: document, baseURL: fileURL, profile: profile) }
        }
    }

    private var background: Color {
        switch mode {
        case .markdown, .plaintext: Color(nsColor: .textBackgroundColor)
        case .xPost: Color.adaptive(light: 0xFFFFFF, dark: 0x000000)
        case .linkedin: Color.adaptive(light: 0xF4F2EE, dark: 0x000000)
        case .slack: Color.adaptive(light: 0xFFFFFF, dark: 0x1A1D21)
        }
    }
}

/// Static stand-in drawn for the one frame between a view switch and the real view being built:
/// a faint column of ghost posts shaped like the target feed. Editors get the bare page.
struct ViewSkeleton: View {
    let mode: ViewMode

    var body: some View {
        switch mode {
        case .markdown, .plaintext:
            Color.clear
        case .xPost:
            column(width: XTheme.columnWidth, avatar: 40, rows: 4, border: XTheme.border)
        case .linkedin:
            column(width: LinkedInTheme.columnWidth, avatar: 48, rows: 3, border: nil)
        case .slack:
            HStack(spacing: 0) {
                Color.primary.opacity(0.04).frame(width: 260)
                column(width: nil, avatar: 36, rows: 5, border: nil)
            }
        }
    }

    private func column(width: CGFloat?, avatar: CGFloat, rows: Int, border: Color?) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    GhostCircle(size: avatar, cornerRadius: mode == .slack ? 8 : nil)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            GhostBar(width: 110, height: 12)
                            GhostBar(width: 70, height: 10)
                        }
                        GhostParagraph(lines: i % 2 == 0 ? 3 : 2, seed: i)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                if let border { border.frame(height: 1) }
            }
            Spacer(minLength: 0)
        }
        .frame(width: width)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 44)
        .opacity(0.55)
    }
}
