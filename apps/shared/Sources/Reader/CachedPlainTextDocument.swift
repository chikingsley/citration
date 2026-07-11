import Foundation

struct CachedPlainTextDocument: Equatable {
    // MARK: Lifecycle

    init(fileURL: URL) throws {
        var encoding: UInt = 0
        text = try NSString(contentsOf: fileURL, usedEncoding: &encoding) as String
    }

    // MARK: Internal

    let text: String
}
