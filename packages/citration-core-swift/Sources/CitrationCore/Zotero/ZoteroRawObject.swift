import Foundation

// MARK: - JSONValue

/// A lossless representation of a JSON value used at the Zotero compatibility boundary.
///
/// Typed projections may understand only part of a Zotero object. Keeping the complete
/// value prevents an older Citration build from discarding fields added by Zotero later.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Public

    public var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    public var integerValue: Int64? {
        guard case let .integer(value) = self else {
            return nil
        }
        return value
    }
}

// MARK: Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

// MARK: - ZoteroRawObject

/// The complete API v3 representation of one versioned Zotero object.
public struct ZoteroRawObject: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(rawValue: JSONValue) throws {
        guard rawValue.objectValue != nil else {
            throw ZoteroRawObjectError.expectedObject
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        try self.init(rawValue: JSONValue(from: decoder))
    }

    // MARK: Public

    public let rawValue: JSONValue

    public var key: String? {
        root["key"]?.stringValue ?? data["key"]?.stringValue
    }

    public var version: Int64? {
        root["version"]?.integerValue ?? data["version"]?.integerValue
    }

    public var itemType: String? {
        data["itemType"]?.stringValue
    }

    public var data: [String: JSONValue] {
        root["data"]?.objectValue ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        try rawValue.encode(to: encoder)
    }

    // MARK: Private

    private var root: [String: JSONValue] {
        rawValue.objectValue ?? [:]
    }
}

// MARK: - ZoteroRawObjectError

public enum ZoteroRawObjectError: Error, Equatable, Sendable {
    case expectedObject
}

// MARK: - ZoteroJSON

public enum ZoteroJSON {
    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func encode(_ value: JSONValue, prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
