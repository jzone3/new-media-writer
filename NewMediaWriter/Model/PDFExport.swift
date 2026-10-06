import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File ▸ Export as PDF…: the Markdown as a clean paginated document, saved where the user picks.
enum PDFExport {
    static func run(text: String, fileURL: URL?, window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".pdf"
        if let fileURL { panel.directoryURL = fileURL.deletingLastPathComponent() }
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(text: text, baseURL: fileURL, to: url)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn't export the PDF."
                if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    struct ExportError: LocalizedError {
        var errorDescription: String? { "The PDF could not be written." }
    }

    /// Prints an offscreen text view to disk; NSTextView paginates without cutting lines in half.
    static func write(text: String, baseURL: URL?, to url: URL) throws {
        let info = NSPrintInfo()
        info.topMargin = 72; info.bottomMargin = 72; info.leftMargin = 72; info.rightMargin = 72
        info.horizontalPagination = .clip
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let height = info.paperSize.height - info.topMargin - info.bottomMargin
        let rendered = PDFRender.attributed(text, contentWidth: width, contentHeight: height) {
            ImagePathResolver.resolve($0, relativeTo: baseURL)
        }
        let storage = NSTextStorage(attributedString: rendered)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10), textContainer: container)
        view.textContainerInset = .zero
        view.isEditable = false
        view.backgroundColor = .white
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.minSize = CGSize(width: width, height: 0)
        view.maxSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        view.frame.size.height = ceil(layout.usedRect(for: container).height)

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: url.path) else { throw ExportError() }
    }
}

struct PDFExportContext {
    let document: MarkdownDocument
    let fileURL: URL?
}

struct PDFExportFocusedKey: FocusedValueKey {
    typealias Value = PDFExportContext
}

extension FocusedValues {
    var pdfExport: PDFExportContext? {
        get { self[PDFExportFocusedKey.self] }
        set { self[PDFExportFocusedKey.self] = newValue }
    }
}

struct ExportCommands: Commands {
    @FocusedValue(\.pdfExport) private var context

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Export as PDF…") {
                guard let context else { return }
                PDFExport.run(text: context.document.text, fileURL: context.fileURL, window: NSApp.keyWindow)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(context == nil)
        }
    }
}
