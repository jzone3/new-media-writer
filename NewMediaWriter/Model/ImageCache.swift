import AppKit
import AVFoundation
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
    private var posters: [URL: (identity: FileIdentity?, image: NSImage?)] = [:]
    private var posterWaiters: [URL: [() -> Void]] = [:]
    private let lock = NSLock()

    /// Synchronous lookup for local files; remote images and video poster frames are made in the
    /// background and `onLoad` is called on the main thread once available.
    func image(for url: URL, onLoad: (() -> Void)? = nil) -> NSImage? {
        if ImageStore.isVideo(url) { return poster(for: url, onLoad: onLoad) }
        if url.isFileURL {
            let identity = FileIdentity(url)
            lock.lock()
            // Failed loads are remembered too, so a file that isn't an image is read once, not on every keystroke.
            if let identity, identities[url] == identity { let cached = cache[url]; lock.unlock(); return cached }
            cache[url] = nil
            identities[url] = nil
            lock.unlock()
            guard let identity else { return nil }
            let img = NSImage(contentsOf: url)
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
        lock.lock(); cache[url] = nil; identities[url] = nil; posters[url] = nil; lock.unlock()
    }

    /// A video's first frame with a play badge, made off the main thread (never by reading the whole file).
    private func poster(for url: URL, onLoad: (() -> Void)?) -> NSImage? {
        let identity = url.isFileURL ? FileIdentity(url) : nil
        if url.isFileURL, identity == nil { return nil }
        lock.lock()
        if let entry = posters[url], entry.identity == identity { lock.unlock(); return entry.image }
        let alreadyPending = posterWaiters[url] != nil
        posterWaiters[url, default: []].append(onLoad ?? {})
        lock.unlock()
        guard !alreadyPending else { return nil }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.generateCGImageAsynchronously(for: .zero) { [weak self] cgImage, _, _ in
            guard let self else { return }
            let image = cgImage.map(Self.posterImage)
            self.lock.lock()
            self.posters[url] = (identity, image)
            let waiters = self.posterWaiters.removeValue(forKey: url) ?? []
            self.lock.unlock()
            DispatchQueue.main.async { waiters.forEach { $0() } }
        }
        return nil
    }

    private static func posterImage(_ frame: CGImage) -> NSImage {
        let size = NSSize(width: frame.width, height: frame.height)
        return NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.draw(frame, in: rect)
            let d = min(rect.width, rect.height) * 0.22
            let circle = NSRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: circle).fill()
            let t = d * 0.36
            let play = NSBezierPath()
            play.move(to: NSPoint(x: circle.midX - t * 0.4, y: circle.midY - t / 2))
            play.line(to: NSPoint(x: circle.midX - t * 0.4, y: circle.midY + t / 2))
            play.line(to: NSPoint(x: circle.midX + t * 0.55, y: circle.midY))
            play.close()
            NSColor.white.setFill()
            play.fill()
            return true
        }
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

/// Right-click menu shared by inline editor images and card media: Copy, Open, Show in Finder.
final class MediaMenu: NSObject {
    static let shared = MediaMenu()

    static func menu(for url: URL, onRemove: (() -> Void)? = nil) -> NSMenu {
        let menu = NSMenu()
        let video = ImageStore.isVideo(url)
        for (title, action) in [
            (video ? "Copy Video" : "Copy Image", #selector(copyMedia(_:))),
            (video ? "Open Video" : "Open Image", #selector(openMedia(_:))),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = shared
            item.representedObject = url
            menu.addItem(item)
        }
        if url.isFileURL {
            let item = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
            item.target = shared
            item.representedObject = url
            menu.addItem(item)
        }
        if let onRemove {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Remove from Post", action: #selector(MenuAction.fire), keyEquivalent: "")
            let action = MenuAction(onRemove)
            item.target = action
            item.representedObject = action
            menu.addItem(item)
        }
        return menu
    }

    /// Holds a closure for an NSMenuItem (kept alive through `representedObject`).
    private final class MenuAction: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    /// Puts the file and (for images) its bitmap on the clipboard in one item, so Finder pastes the file
    /// and image-taking apps (Slack, Messages, Preview) paste the picture.
    static func copy(_ url: URL) {
        let item = NSPasteboardItem()
        if url.isFileURL { item.setString(url.absoluteString, forType: .fileURL) }
        if !ImageStore.isVideo(url), let image = ImageCache.shared.image(for: url), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
            if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                item.setData(png, forType: .png)
            }
        }
        guard !item.types.isEmpty else { return }
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.writeObjects([item])
    }

    @objc private func copyMedia(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { Self.copy(url) }
    }

    @objc private func openMedia(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
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
