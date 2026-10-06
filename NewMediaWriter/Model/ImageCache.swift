import AppKit
import UniformTypeIdentifiers

/// What a local file is right now (inode, size, modification date), so a deleted or replaced file
/// at the same path is never confused with what used to be there.
struct FileIdentity: Hashable {
    let inode: UInt64
    let size: UInt64
    let modified: Date

    init?(_ url: URL) {
        guard url.isFileURL, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        modified = attrs[.modificationDate] as? Date ?? .distantPast
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private var cache: [URL: NSImage] = [:]
    private var identities: [URL: FileIdentity] = [:]
    private var pending: Set<URL> = []
    private let lock = NSLock()

    /// Synchronous lookup for local files; remote images are fetched in the background and
    /// `onLoad` is called on the main thread once available.
    func image(for url: URL, onLoad: (() -> Void)? = nil) -> NSImage? {
        if url.isFileURL {
            let identity = FileIdentity(url)
            lock.lock()
            if let identity, identities[url] == identity, let cached = cache[url] { lock.unlock(); return cached }
            cache[url] = nil
            identities[url] = nil
            lock.unlock()
            guard let identity, let img = NSImage(contentsOf: url) else { return nil }
            lock.lock(); cache[url] = img; identities[url] = identity; lock.unlock()
            return img
        }

        lock.lock()
        if let cached = cache[url] { lock.unlock(); return cached }
        lock.unlock()

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
        lock.lock(); cache[url] = nil; identities[url] = nil; lock.unlock()
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

/// Copies pasted / dropped images and videos into `assets/` beside the document and returns their markdown paths.
struct ImageStore {
    let documentURL: URL

    var assetsDirectory: URL {
        documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
    }

    /// A free `assets/<name>.<ext>` location (`name-2`, `name-3`, … when taken).
    private func destination(preferredName: String, ext: String) throws -> URL {
        let dir = assetsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = preferredName.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        var name = "\(safe).\(ext)"
        var n = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            n += 1
            name = "\(safe)-\(n).\(ext)"
        }
        return dir.appendingPathComponent(name)
    }

    private func markdownPath(_ dest: URL) -> String {
        "assets/" + dest.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }

    func store(data: Data, preferredName: String, ext: String) throws -> String {
        let dest = try destination(preferredName: preferredName, ext: ext)
        try data.write(to: dest)
        return markdownPath(dest)
    }

    /// Copies the file itself (videos can be large, so never read them into memory).
    func store(fileURL: URL) throws -> String {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let dest = try destination(preferredName: base, ext: fileURL.pathExtension.lowercased())
        try FileManager.default.copyItem(at: fileURL, to: dest)
        return markdownPath(dest)
    }

    // MARK: - Pasteboards

    private static let mediaFileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier, UTType.movie.identifier],
    ]

    /// True when the pasteboard carries image or video files, or raw image data.
    static func hasMedia(on pboard: NSPasteboard) -> Bool {
        pboard.canReadObject(forClasses: [NSURL.self], options: mediaFileOptions)
            || pboard.availableType(from: [.png, .tiff]) != nil
    }

    /// Saves every image/video on the pasteboard (files first, then raw image data); nil when there is nothing to save.
    func storeMedia(from pboard: NSPasteboard) -> [String]? {
        var paths: [String] = []
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: Self.mediaFileOptions) as? [URL], !urls.isEmpty {
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

    /// One `![alt](path)` line per file (videos too, so the reference stays plain Markdown), alt text from the file name.
    static func markdown(for paths: [String]) -> String {
        paths.map { path in
            let name = (path as NSString).lastPathComponent
            let alt = ((name.removingPercentEncoding ?? name) as NSString).deletingPathExtension
            return "![\(alt)](\(path))"
        }.joined(separator: "\n")
    }

    /// Videos are referenced with image syntax; the file extension tells them apart.
    static func isVideo(_ url: URL?) -> Bool {
        guard let ext = url?.pathExtension, !ext.isEmpty, let type = UTType(filenameExtension: ext.lowercased()) else { return false }
        return type.conforms(to: .movie)
    }

    private static func timestampName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "image-" + f.string(from: Date())
    }

    /// Untitled documents have nowhere to keep assets, so ask to save instead of stashing media elsewhere.
    static func promptToSave(in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Save this document first so images and videos can be stored next to it"
        alert.informativeText = "Images and videos are copied into an assets folder beside the Markdown file."
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
