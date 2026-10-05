import AppKit
import UniformTypeIdentifiers

final class ImageCache {
    static let shared = ImageCache()
    private var cache: [URL: NSImage] = [:]
    private var pending: Set<URL> = []
    private let lock = NSLock()

    /// Synchronous lookup for local files; remote images are fetched in the background and
    /// `onLoad` is called on the main thread once available.
    func image(for url: URL, onLoad: (() -> Void)? = nil) -> NSImage? {
        lock.lock()
        if let cached = cache[url] { lock.unlock(); return cached }
        lock.unlock()

        if url.isFileURL {
            guard let img = NSImage(contentsOf: url) else { return nil }
            lock.lock(); cache[url] = img; lock.unlock()
            return img
        }

        lock.lock()
        let alreadyPending = pending.contains(url)
        if !alreadyPending { pending.insert(url) }
        lock.unlock()
        guard !alreadyPending else { return nil }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            self.lock.lock()
            self.pending.remove(url)
            if let data, let img = NSImage(data: data) { self.cache[url] = img }
            self.lock.unlock()
            DispatchQueue.main.async { onLoad?() }
        }.resume()
        return nil
    }

    func invalidate(_ url: URL) {
        lock.lock(); cache[url] = nil; lock.unlock()
    }
}

enum ImagePathResolver {
    static func resolve(_ path: String, relativeTo base: URL?) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return URL(string: trimmed) }
        if trimmed.hasPrefix("file://") { return URL(string: trimmed) }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let decoded = expanded.removingPercentEncoding ?? expanded
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        guard let base else { return nil }
        return base.deletingLastPathComponent().appendingPathComponent(decoded).standardizedFileURL
    }
}

/// Copies pasted / dropped images into `assets/` beside the document and returns their markdown paths.
struct ImageStore {
    let documentURL: URL

    var assetsDirectory: URL {
        documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
    }

    func store(data: Data, preferredName: String, ext: String) throws -> String {
        let dir = assetsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = preferredName.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        var name = "\(safe).\(ext)"
        var n = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            n += 1
            name = "\(safe)-\(n).\(ext)"
        }
        let dest = dir.appendingPathComponent(name)
        try data.write(to: dest)
        return "assets/" + dest.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }

    func store(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let base = fileURL.deletingPathExtension().lastPathComponent
        return try store(data: data, preferredName: base, ext: fileURL.pathExtension.lowercased())
    }

    // MARK: - Pasteboards

    private static let imageFileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    /// True when the pasteboard carries image files or raw image data.
    static func hasImages(on pboard: NSPasteboard) -> Bool {
        pboard.canReadObject(forClasses: [NSURL.self], options: imageFileOptions)
            || pboard.availableType(from: [.png, .tiff]) != nil
    }

    /// Saves every image on the pasteboard (files first, then raw data); nil when there is nothing to save.
    func storeImages(from pboard: NSPasteboard) -> [String]? {
        var paths: [String] = []
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: Self.imageFileOptions) as? [URL], !urls.isEmpty {
            for url in urls {
                if let p = try? store(fileURL: url) { paths.append(p) }
            }
        } else if let data = pboard.data(forType: .png) {
            if let p = try? store(data: data, preferredName: Self.timestampName(), ext: "png") { paths.append(p) }
        } else if let data = pboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: data),
                  let png = rep.representation(using: .png, properties: [:]) {
            if let p = try? store(data: png, preferredName: Self.timestampName(), ext: "png") { paths.append(p) }
        }
        return paths.isEmpty ? nil : paths
    }

    /// One `![alt](path)` line per image, alt text taken from the file name.
    static func markdown(for paths: [String]) -> String {
        paths.map { path in
            let name = (path as NSString).lastPathComponent
            let alt = ((name.removingPercentEncoding ?? name) as NSString).deletingPathExtension
            return "![\(alt)](\(path))"
        }.joined(separator: "\n")
    }

    private static func timestampName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "image-" + f.string(from: Date())
    }

    /// Untitled documents have nowhere to keep assets, so ask to save instead of stashing images elsewhere.
    static func promptToSave(in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Save this document first so images can be stored next to it"
        alert.informativeText = "Images are copied into an assets folder beside the Markdown file."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            // Let the alert sheet finish closing before the save panel takes its place.
            DispatchQueue.main.async {
                let document = window.flatMap { NSDocumentController.shared.document(for: $0) } ?? NSDocumentController.shared.currentDocument
                document?.save(nil)
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }
}
