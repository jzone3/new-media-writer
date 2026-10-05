import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Makes a feed card a drop target for image files and image data. Dropped images are saved to `assets/`
    /// beside the document and appended to `markdown` as `![]()` lines through `onEdit`, so they show up in
    /// the card's media grid. Untitled documents get a "save first" prompt instead.
    func imageDrop(documentURL: URL?, markdown: String, accent: Color, cornerRadius: CGFloat = 12,
                   onEdit: @escaping (String) -> Void) -> some View {
        modifier(ImageDropModifier(documentURL: documentURL, markdown: markdown, accent: accent,
                                   cornerRadius: cornerRadius, onEdit: onEdit))
    }
}

private struct ImageDropModifier: ViewModifier {
    let documentURL: URL?
    let markdown: String
    let accent: Color
    let cornerRadius: CGFloat
    let onEdit: (String) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(accent, lineWidth: 2)
                        .padding(3)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL, .image],
                    delegate: ImageDropDelegate(documentURL: documentURL, markdown: markdown, onEdit: onEdit, targeted: $targeted))
    }
}

private struct ImageDropDelegate: DropDelegate {
    let documentURL: URL?
    let markdown: String
    let onEdit: (String) -> Void
    var targeted: Binding<Bool>

    private var pasteboard: NSPasteboard { NSPasteboard(name: .drag) }

    func validateDrop(info: DropInfo) -> Bool { ImageStore.hasImages(on: pasteboard) }
    func dropEntered(info: DropInfo) { targeted.wrappedValue = true }
    func dropExited(info: DropInfo) { targeted.wrappedValue = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        targeted.wrappedValue = false
        guard let documentURL else {
            // Dropping from Finder leaves us inactive with no key window: find the window under the drop.
            let mouse = NSEvent.mouseLocation
            let window = NSApp.orderedWindows.first { $0.isVisible && $0.frame.contains(mouse) }
            DispatchQueue.main.async {
                NSApp.activate()
                ImageStore.promptToSave(in: window)
            }
            return true
        }
        guard let paths = ImageStore(documentURL: documentURL).storeImages(from: pasteboard) else { return false }
        var text = markdown
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        onEdit(text + ImageStore.markdown(for: paths) + "\n")
        return true
    }
}
