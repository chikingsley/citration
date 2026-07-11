import Foundation

// MARK: - ZoteroMergeResult

enum ZoteroMergeResult: Equatable, Sendable {
    case merged(JSONValue)
    case conflict(fields: [String])
}

// MARK: - ZoteroThreeWayMerge

enum ZoteroThreeWayMerge {
    // MARK: Internal

    static func merge(base: JSONValue, local: JSONValue, remote: JSONValue) -> ZoteroMergeResult {
        guard
            let baseData = editableData(base),
            let localData = editableData(local),
            let remoteData = editableData(remote),
            var remoteEnvelope = remote.objectValue
        else {
            return .conflict(fields: ["<object>"])
        }

        var mergedData = remoteData
        var conflicts = [String]()
        let fields = Set(baseData.keys).union(localData.keys).union(remoteData.keys)
        for field in fields.sorted() {
            switch field {
            case "key",
                 "version",
                 "dateAdded":
                assign(remoteData[field], to: field, in: &mergedData)

            case "dateModified":
                assign(latestDate(localData[field], remoteData[field]), to: field, in: &mergedData)

            default:
                let baseValue = baseData[field]
                let localValue = localData[field]
                let remoteValue = remoteData[field]
                if localValue == remoteValue {
                    assign(localValue, to: field, in: &mergedData)
                } else if localValue == baseValue {
                    assign(remoteValue, to: field, in: &mergedData)
                } else if remoteValue == baseValue {
                    assign(localValue, to: field, in: &mergedData)
                } else {
                    conflicts.append(field)
                }
            }
        }
        guard conflicts.isEmpty else {
            return .conflict(fields: conflicts)
        }
        remoteEnvelope["data"] = .object(mergedData)
        return .merged(.object(remoteEnvelope))
    }

    // MARK: Private

    private static func editableData(_ value: JSONValue) -> [String: JSONValue]? {
        let object = value.objectValue
        return object?["data"]?.objectValue ?? object
    }

    private static func assign(
        _ value: JSONValue?,
        to field: String,
        in object: inout [String: JSONValue]
    ) {
        if let value {
            object[field] = value
        } else {
            object.removeValue(forKey: field)
        }
    }

    private static func latestDate(_ first: JSONValue?, _ second: JSONValue?) -> JSONValue? {
        guard let first else {
            return second
        }
        guard let second else {
            return first
        }
        guard let firstText = first.stringValue, let secondText = second.stringValue else {
            return second
        }
        return firstText >= secondText ? first : second
    }
}
