import AppKit
import SwiftUI

/// Asks before reopening last session's files. macOS's own window restoration brings them back
/// silently, so a file that hangs or crashes the app comes straight back on every launch with no
/// way out. Document windows opt out of it here and the app keeps its own list of open files,
/// which is offered on the next launch behind a Reopen / Don't Reopen choice.
enum SessionRestore {
    static let filesKey = "session.openFiles"
    /// Files open when the app last ran, read before any window of this run can overwrite the list.
    private static var lastSession: [URL] = []
    private static var observers: [NSObjectProtocol] = []
    private static var quitting = false

    static func install() {
        lastSession = (UserDefaults.standard.stringArray(forKey: filesKey) ?? []).map { URL(fileURLWithPath: $0) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, NSDocumentController.shared.document(for: window) != nil else { return }
            window.isRestorable = false
            record()
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, let closing = NSDocumentController.shared.document(for: window) else { return }
            record(excluding: closing)
        })
    }

    /// Quit closes every window in turn; recording through that would leave nothing to offer next time.
    static func appWillQuit() {
        record()
        quitting = true
    }

    static func record(excluding closing: NSDocument? = nil) {
        guard !quitting else { return }
        let paths = NSDocumentController.shared.documents
            .filter { $0 !== closing }
            .compactMap { $0.fileURL?.path }
        UserDefaults.standard.set(paths, forKey: filesKey)
    }

    /// Last session's files that are still on disk and not already open in this run.
    static var pendingFiles: [URL] {
        let open = Set(NSDocumentController.shared.documents.compactMap { $0.fileURL?.standardizedFileURL })
        return lastSession.filter { FileManager.default.fileExists(atPath: $0.path) && !open.contains($0.standardizedFileURL) }
    }

    static func promptIfNeeded(then next: @escaping () -> Void) {
        let files = pendingFiles
        lastSession = []
        guard !files.isEmpty else { return next() }

        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        sheet.isReleasedWhenClosed = false
        var reopen = false
        let host = NSHostingController(rootView: ReopenView(files: files) { [weak sheet] choice in
            reopen = choice
            guard let sheet else { return }
            if let parent = sheet.sheetParent {
                parent.endSheet(sheet)
            } else {
                sheet.orderOut(nil)
                finish(reopen: choice, files: files, then: next)
            }
        })
        host.sizingOptions = [.preferredContentSize]
        sheet.contentViewController = host
        sheet.setContentSize(host.view.fittingSize)

        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible, window.attachedSheet == nil {
            window.beginSheet(sheet) { _ in
                DispatchQueue.main.async { finish(reopen: reopen, files: files, then: next) }
            }
        } else {
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
        }
    }

    private static func finish(reopen: Bool, files: [URL], then next: @escaping () -> Void) {
        guard reopen else { return next() }
        // The launch Untitled window goes away once the first file is back, so the reopened
        // files don't sit behind an empty one; it stays if nothing could be opened.
        let blank = NSDocumentController.shared.documents.first { $0.fileURL == nil && !$0.isDocumentEdited }
        var closedBlank = false
        for url in files {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
                guard document != nil, !closedBlank, let blank, blank.windowControllers.first?.window?.attachedSheet == nil else { return }
                closedBlank = true
                blank.close()
            }
        }
        next()
    }
}

private struct ReopenView: View {
    let files: [URL]
    let done: (Bool) -> Void

    private var shown: [URL] { Array(files.prefix(5)) }

    var body: some View {
        VStack(spacing: 0) {
            Text(files.count == 1 ? "Reopen the file you had open?" : "Reopen the files you had open?")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 13))
                }
                if files.count > shown.count {
                    Text("and \(files.count - shown.count) more")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 12)
            Text("If one of them keeps crashing the app, choose Don't Reopen. They stay in File > Open Recent.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            HStack(spacing: 10) {
                pill("Don't Reopen", filled: false) { done(false) }
                pill("Reopen", filled: true) { done(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 32)
        .padding(.bottom, 28)
        .frame(width: 400)
        .background(Button("Close") { done(false) }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(filled ? Color.primary : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(filled ? 0 : 0.25), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
