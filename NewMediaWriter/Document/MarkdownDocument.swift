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
        text = String(decoding: data, as: UTF8.self)
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
