import Foundation

// MARK: - ZoteroItemFieldUpdate

/// One field-level mutation inside a Zotero item's `data` object.
public struct ZoteroItemFieldUpdate: Hashable, Sendable {
    // MARK: Lifecycle

    public init(field: String, value: JSONValue?) {
        self.field = field
        self.value = value
    }

    // MARK: Public

    public let field: String
    public let value: JSONValue?
}

// MARK: - ZoteroItemEditingError

public enum ZoteroItemEditingError: Error, Equatable, Sendable {
    case identityMismatch
    case invalidField(String)
    case itemNotFound
    case malformedObject
    case schemaMismatch
}
