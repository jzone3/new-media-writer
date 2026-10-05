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
        for encoding in [String.Encoding.utf8, .windowsCP1252, .isoLatin1] {
            if let string = String(data: bytes, encoding: encoding) { return string }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
