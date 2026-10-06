import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?
    // Per-window; new windows start in the view used most recently.
    @State private var mode: ViewMode = .lastUsed
    @Environment(\.colorScheme) private var colorScheme
    @State private var pickerShown = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ViewSwitcher(mode: $mode)
                .padding(.top, 8)
                .padding(.trailing, 12)

            if mode.isEditor {
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
        .animation(.easeOut(duration: 0.15), value: mode)
        .onChange(of: mode) { _, new in ViewMode.lastUsed = new }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .markdown, .plaintext:
            MarkdownEditor(document: document, fileURL: fileURL, raw: mode == .plaintext)
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
