import Foundation
import GRDB

extension CitrationDatabase {
    static func insertFieldsAndIdentifiers(
        object: ZoteroRawObject,
        libraryID: Int64,
        key: String,
        database: Database
    ) throws {
        for (fieldName, value) in object.data.sorted(by: { $0.key < $1.key }) {
            try database.execute(
                sql: """
                INSERT INTO item_fields (
                    library_id, item_key, field_name, value_kind, field_value,
                    text_value, integer_value, number_value, boolean_value
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    libraryID,
                    key,
                    fieldName,
                    value.kind,
                    ZoteroJSON.encode(value),
                    value.stringValue,
                    value.integerValue,
                    value.numberValue,
                    value.boolValue,
                ]
            )
        }

        let identifierFields = ["DOI", "ISBN", "ISSN", "PMID", "PMCID", "url"]
        var position = 0
        for fieldName in identifierFields {
            guard let value = object.data[fieldName]?.stringValue, !value.isEmpty else {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO item_identifiers (
                    library_id, item_key, position, identifier_type, identifier_value
                ) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [libraryID, key, position, fieldName, value]
            )
            position += 1
        }
    }

    static func fetchFields(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [String: JSONValue] {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT field_name, field_value FROM item_fields
            WHERE library_id = ? AND item_key = ?
            """,
            arguments: [libraryID, key]
        )
        return try Dictionary(uniqueKeysWithValues: rows.map { row in
            let fieldName: String = row["field_name"]
            let fieldValue: Data = row["field_value"]
            return try (fieldName, ZoteroJSON.decode(fieldValue))
        })
    }

    static func fetchIdentifiers(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [ZoteroProjectedIdentifier] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT identifier_type, identifier_value FROM item_identifiers
            WHERE library_id = ? AND item_key = ? ORDER BY position
            """,
            arguments: [libraryID, key]
        ).map { row in
            ZoteroProjectedIdentifier(type: row["identifier_type"], value: row["identifier_value"])
        }
    }
}
