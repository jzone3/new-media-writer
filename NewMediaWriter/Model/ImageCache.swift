import AppKit

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

/// Copies pasted / dropped images next to the document and returns the markdown path.
struct ImageStore {
    let documentURL: URL?

    var assetsDirectory: URL {
        if let documentURL {
            return documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("New Media Writer/Untitled Assets", isDirectory: true)
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
        return markdownPath(for: dest)
    }

    func store(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let base = fileURL.deletingPathExtension().lastPathComponent
        return try store(data: data, preferredName: base, ext: fileURL.pathExtension.lowercased())
    }

    private func markdownPath(for dest: URL) -> String {
        if documentURL != nil {
            return "assets/" + dest.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        }
        return dest.path
    }
}
