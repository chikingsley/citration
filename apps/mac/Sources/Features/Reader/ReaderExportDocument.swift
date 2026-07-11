import SwiftUI
import UniformTypeIdentifiers

struct ReaderExportDocument: FileDocument {
    // MARK: Lifecycle

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) {
        data = configuration.file.regularFileContents ?? Data()
    }

    // MARK: Internal

    static let readableContentTypes: [UTType] = [.json, .pdf]

    let data: Data

    func fileWrapper(configuration _: WriteConfiguration) -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
