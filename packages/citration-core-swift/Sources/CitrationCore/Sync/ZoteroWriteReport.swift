import Foundation

// MARK: - ZoteroWriteFailure

public struct ZoteroWriteFailure: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(key: String? = nil, code: Int, message: String) {
        self.key = key
        self.code = code
        self.message = message
    }

    // MARK: Public

    public let key: String?
    public let code: Int
    public let message: String
}

// MARK: - ZoteroWriteReport

public struct ZoteroWriteReport: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        success: [String: String] = [:],
        successful: [String: ZoteroRawObject] = [:],
        unchanged: [String: String] = [:],
        failed: [String: ZoteroWriteFailure] = [:]
    ) {
        self.success = success
        self.successful = successful
        self.unchanged = unchanged
        self.failed = failed
    }

    // MARK: Public

    public let success: [String: String]
    public let successful: [String: ZoteroRawObject]
    public let unchanged: [String: String]
    public let failed: [String: ZoteroWriteFailure]
}
