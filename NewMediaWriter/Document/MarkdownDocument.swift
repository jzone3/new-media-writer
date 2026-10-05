import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDoc = UTType(importedAs: "net.daringfireball.markdown")
}

final class MarkdownDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.markdownDoc, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDoc, .plainText] }

    @Published var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = Self.decode(data)
    }

    /// UTF-8 without a leading BOM (which would otherwise break the first line's markdown), falling back
    /// to Windows-1252 / Latin-1 so legacy files don't open as U+FFFD.
    static func decode(_ data: Data) -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let utf8 = String(data: bytes, encoding: .utf8) { return utf8 }
        // Mostly valid UTF-8 with a few bad bytes stays UTF-8 (bad bytes become U+FFFD) rather than
        // turning every multibyte character into mojibake; only text whose high bytes are mostly
        // invalid as UTF-8 is treated as legacy single-byte Latin text.
        let lossy = String(decoding: bytes, as: UTF8.self)
        let replacements = lossy.unicodeScalars.filter { $0 == "\u{FFFD}" }.count
        let highBytes = bytes.filter { $0 >= 0x80 }.count
        if replacements * 2 <= highBytes { return lossy }
        return String(data: bytes, encoding: .windowsCP1252)
            ?? String(data: bytes, encoding: .isoLatin1)
            ?? lossy
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
