import Foundation
import GRDB

extension CitrationDatabase {
    public func fetchProjectedItem(libraryID: Int64, key: String) throws -> ZoteroProjectedItem? {
        try databaseQueue.read { database -> ZoteroProjectedItem? in
            guard
                let item = try Row.fetchOne(
                    database,
                    sql: "SELECT * FROM item_projections WHERE library_id = ? AND item_key = ?",
                    arguments: [libraryID, key]
                )
            else {
                return nil
            }

            return try ZoteroProjectedItem(
                key: key,
                itemType: item["item_type"],
                title: item["title"],
                abstractNote: item["abstract_note"],
                date: item["date_text"],
                publicationTitle: item["publication_title"],
                doi: item["doi"],
                isbn: item["isbn"],
                issn: item["issn"],
                url: item["url"],
                language: item["language"],
                rights: item["rights"],
                extra: item["extra"],
                fields: Self.fetchFields(libraryID: libraryID, key: key, database: database),
                identifiers: Self.fetchIdentifiers(libraryID: libraryID, key: key, database: database),
                parentItemKey: item["parent_item_key"],
                noteHTML: item["note_html"],
                creators: Self.fetchCreators(libraryID: libraryID, key: key, database: database),
                tags: Self.fetchTags(libraryID: libraryID, key: key, database: database),
                collectionKeys: Self.fetchCollectionKeys(libraryID: libraryID, key: key, database: database),
                attachment: Self.fetchAttachment(libraryID: libraryID, key: key, database: database),
                annotation: Self.fetchAnnotation(libraryID: libraryID, key: key, database: database)
            )
        }
    }

    static func fetchCreators(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [ZoteroProjectedCreator] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT position, creator_type, first_name, last_name, literal_name
            FROM item_creators WHERE library_id = ? AND item_key = ? ORDER BY position
            """,
            arguments: [libraryID, key]
        ).map { row in
            ZoteroProjectedCreator(
                position: row["position"],
                creatorType: row["creator_type"],
                firstName: row["first_name"],
                lastName: row["last_name"],
                literalName: row["literal_name"]
            )
        }
    }

    static func fetchTags(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [ZoteroProjectedTag] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT position, tag, tag_type
            FROM item_tags WHERE library_id = ? AND item_key = ? ORDER BY position
            """,
            arguments: [libraryID, key]
        ).map { row in
            ZoteroProjectedTag(position: row["position"], value: row["tag"], type: row["tag_type"])
        }
    }

    static func fetchCollectionKeys(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> [String] {
        try String.fetchAll(
            database,
            sql: """
            SELECT collection_key FROM collection_items
            WHERE library_id = ? AND item_key = ? ORDER BY position
            """,
            arguments: [libraryID, key]
        )
    }

    static func upsertCollectionProjection(
        object: ZoteroRawObject,
        libraryID: Int64,
        database: Database
    ) throws {
        guard let key = object.key else {
            throw CitrationDatabaseError.missingObjectKey
        }
        try database.execute(
            sql: """
            INSERT INTO collection_projections (
                library_id, collection_key, collection_version, name, parent_collection_key
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (library_id, collection_key) DO UPDATE SET
                collection_version = excluded.collection_version,
                name = excluded.name,
                parent_collection_key = excluded.parent_collection_key
            """,
            arguments: [
                libraryID,
                key,
                object.version ?? 0,
                string("name", in: object.data),
                optionalString("parentCollection", in: object.data),
            ]
        )
        try database.execute(
            sql: "DELETE FROM library_search WHERE library_id = ? AND object_key = ? AND object_kind = 'collection'",
            arguments: [libraryID, key]
        )
        try database.execute(
            sql: """
            INSERT INTO library_search (
                library_id, object_key, object_kind, title, creators, tags,
                note_text, annotation_text, fulltext
            ) VALUES (?, ?, 'collection', ?, '', '', '', '', '')
            """,
            arguments: [libraryID, key, string("name", in: object.data)]
        )
    }

    static func replaceItemProjection(
        object: ZoteroRawObject,
        libraryID: Int64,
        database: Database
    ) throws {
        guard let key = object.key, let itemType = object.itemType else {
            throw CitrationDatabaseError.missingObjectKey
        }

        try database.cachedStatement(
            sql: """
            INSERT INTO item_projections (
                library_id, item_key, item_type, title, abstract_note, date_text,
                publication_title, doi, isbn, issn, url, language, rights, extra,
                parent_item_key, note_html
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (library_id, item_key) DO UPDATE SET
                item_type = excluded.item_type,
                title = excluded.title,
                abstract_note = excluded.abstract_note,
                date_text = excluded.date_text,
                publication_title = excluded.publication_title,
                doi = excluded.doi,
                isbn = excluded.isbn,
                issn = excluded.issn,
                url = excluded.url,
                language = excluded.language,
                rights = excluded.rights,
                extra = excluded.extra,
                parent_item_key = excluded.parent_item_key,
                note_html = excluded.note_html
            """
        ).execute(arguments: [
            libraryID,
            key,
            itemType,
            string("title", in: object.data),
            string("abstractNote", in: object.data),
            string("date", in: object.data),
            string("publicationTitle", in: object.data),
            string("DOI", in: object.data),
            string("ISBN", in: object.data),
            string("ISSN", in: object.data),
            string("url", in: object.data),
            string("language", in: object.data),
            string("rights", in: object.data),
            string("extra", in: object.data),
            optionalString("parentItem", in: object.data),
            itemType == "note" ? string("note", in: object.data) : nil,
        ])

        try clearChildProjections(libraryID: libraryID, key: key, database: database)
        try Self.insertFieldsAndIdentifiers(object: object, libraryID: libraryID, key: key, database: database)
        try insertCreators(object: object, libraryID: libraryID, key: key, database: database)
        try insertTags(object: object, libraryID: libraryID, key: key, database: database)
        try insertCollectionMemberships(object: object, libraryID: libraryID, key: key, database: database)
        try insertAttachment(object: object, libraryID: libraryID, key: key, database: database)
        try insertAnnotation(object: object, libraryID: libraryID, key: key, database: database)
        try replaceSearchProjection(object: object, libraryID: libraryID, key: key, database: database)
    }

    private static func clearChildProjections(libraryID: Int64, key: String, database: Database) throws {
        for table in [
            "item_fields", "item_identifiers", "item_creators", "item_tags", "collection_items",
            "annotation_projections",
        ] {
            try database.cachedStatement(
                sql: "DELETE FROM \(table) WHERE library_id = ? AND item_key = ?"
            ).execute(arguments: [libraryID, key])
        }
    }

    private static func insertCreators(
        object: ZoteroRawObject,
        libraryID: Int64,
        key: String,
        database: Database
    ) throws {
        let creators = object.data["creators"]?.arrayValue ?? []
        let statement = try database.cachedStatement(sql: """
        INSERT INTO item_creators (
            library_id, item_key, position, creator_type,
            first_name, last_name, literal_name, raw_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """)
        for (position, creator) in creators.enumerated() {
            let creatorData = creator.objectValue ?? [:]
            try statement.execute(arguments: [
                libraryID,
                key,
                position,
                string("creatorType", in: creatorData),
                optionalString("firstName", in: creatorData),
                optionalString("lastName", in: creatorData),
                optionalString("name", in: creatorData),
                ZoteroJSON.encode(creator),
            ])
        }
    }

    private static func insertTags(
        object: ZoteroRawObject,
        libraryID: Int64,
        key: String,
        database: Database
    ) throws {
        let tags = object.data["tags"]?.arrayValue ?? []
        let statement = try database.cachedStatement(sql: """
        INSERT INTO item_tags (library_id, item_key, position, tag, tag_type, raw_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """)
        for (position, tag) in tags.enumerated() {
            let tagData = tag.objectValue ?? [:]
            try statement.execute(arguments: [
                libraryID,
                key,
                position,
                string("tag", in: tagData),
                tagData["type"]?.integerValue,
                ZoteroJSON.encode(tag),
            ])
        }
    }

    private static func insertCollectionMemberships(
        object: ZoteroRawObject,
        libraryID: Int64,
        key: String,
        database: Database
    ) throws {
        let collections = object.data["collections"]?.arrayValue ?? []
        for (position, collection) in collections.enumerated() {
            guard let collectionKey = collection.stringValue else {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO collection_items (library_id, collection_key, item_key, position)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [libraryID, collectionKey, key, position]
            )
            try database.execute(
                sql: """
                INSERT INTO app_collection_memberships (
                    library_id, collection_key, item_key, membership_uuid, created_at
                ) VALUES (?, ?, ?, ?, unixepoch('subsec'))
                ON CONFLICT (library_id, collection_key, item_key) DO NOTHING
                """,
                arguments: [libraryID, collectionKey, key, UUID().uuidString]
            )
        }
        try database.cachedStatement(
            sql: """
            DELETE FROM app_collection_memberships
            WHERE library_id = ? AND item_key = ?
              AND collection_key NOT IN (
                  SELECT collection_key FROM collection_items
                  WHERE library_id = ? AND item_key = ?
              )
            """
        ).execute(arguments: [libraryID, key, libraryID, key])
    }

    private static func insertAttachment(
        object: ZoteroRawObject,
        libraryID: Int64,
        key: String,
        database: Database
    ) throws {
        guard object.itemType == "attachment" else {
            try database.cachedStatement(
                sql: "DELETE FROM attachment_projections WHERE library_id = ? AND item_key = ?"
            ).execute(arguments: [libraryID, key])
            return
        }
        try database.execute(
            sql: """
            INSERT INTO attachment_projections (
                library_id, item_key, parent_item_key, link_mode, content_type,
                charset, filename, remote_url, remote_md5, remote_mtime
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (library_id, item_key) DO UPDATE SET
                parent_item_key = excluded.parent_item_key,
                link_mode = excluded.link_mode,
                content_type = excluded.content_type,
                charset = excluded.charset,
                filename = excluded.filename,
                remote_url = excluded.remote_url,
                remote_md5 = excluded.remote_md5,
                remote_mtime = excluded.remote_mtime,
                cache_state = CASE
                    WHEN attachment_projections.remote_md5 IS NOT excluded.remote_md5
                     AND attachment_projections.verified_md5 IS NOT excluded.remote_md5
                     AND attachment_projections.local_path IS NOT NULL
                    THEN 'stale'
                    ELSE attachment_projections.cache_state
                END
            """,
            arguments: [
                libraryID,
                key,
                optionalString("parentItem", in: object.data),
                string("linkMode", in: object.data),
                string("contentType", in: object.data),
                string("charset", in: object.data),
                string("filename", in: object.data),
                string("url", in: object.data),
                optionalString("md5", in: object.data),
                object.data["mtime"]?.integerValue,
            ]
        )
    }

    private static func insertAnnotation(
        object: ZoteroRawObject,
        libraryID: Int64,
        key: String,
        database: Database
    ) throws {
        guard object.itemType == "annotation", let parentKey = optionalString("parentItem", in: object.data) else {
            return
        }
        try database.execute(
            sql: """
            INSERT INTO annotation_projections (
                library_id, item_key, parent_item_key, annotation_type, color,
                page_label, sort_index, annotation_text, annotation_comment, position_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                libraryID,
                key,
                parentKey,
                string("annotationType", in: object.data),
                string("annotationColor", in: object.data),
                string("annotationPageLabel", in: object.data),
                string("annotationSortIndex", in: object.data),
                string("annotationText", in: object.data),
                string("annotationComment", in: object.data),
                string("annotationPosition", in: object.data),
            ]
        )
    }

    private static func replaceSearchProjection(
        object: ZoteroRawObject,
        libraryID: Int64,
        key: String,
        database: Database
    ) throws {
        let creatorNames = (object.data["creators"]?.arrayValue ?? []).compactMap { creator -> String? in
            let data = creator.objectValue ?? [:]
            return optionalString("name", in: data)
                ?? [optionalString("firstName", in: data), optionalString("lastName", in: data)]
                .compactMap(\.self)
                .joined(separator: " ")
        }
        let tagNames = (object.data["tags"]?.arrayValue ?? []).compactMap {
            optionalString("tag", in: $0.objectValue ?? [:])
        }

        try database.cachedStatement(
            sql: "DELETE FROM library_search WHERE library_id = ? AND object_key = ? AND object_kind = 'item'"
        ).execute(arguments: [libraryID, key])
        try database.cachedStatement(
            sql: """
            INSERT INTO library_search (
                library_id, object_key, object_kind, title, creators, tags,
                note_text, annotation_text, fulltext
            ) VALUES (?, ?, 'item', ?, ?, ?, ?, ?, '')
            """
        ).execute(arguments: [
            libraryID,
            key,
            string("title", in: object.data),
            creatorNames.joined(separator: " "),
            tagNames.joined(separator: " "),
            string("note", in: object.data),
            [string("annotationText", in: object.data), string("annotationComment", in: object.data)]
                .joined(separator: " "),
        ])
    }

    private static func fetchAttachment(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> ZoteroProjectedAttachment? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM attachment_projections WHERE library_id = ? AND item_key = ?",
                arguments: [libraryID, key]
            )
        else {
            return nil
        }
        return ZoteroProjectedAttachment(
            linkMode: row["link_mode"],
            contentType: row["content_type"],
            charset: row["charset"],
            filename: row["filename"],
            remoteURL: row["remote_url"],
            remoteMD5: row["remote_md5"],
            remoteMTime: row["remote_mtime"]
        )
    }

    private static func fetchAnnotation(
        libraryID: Int64,
        key: String,
        database: Database
    ) throws -> ZoteroProjectedAnnotation? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM annotation_projections WHERE library_id = ? AND item_key = ?",
                arguments: [libraryID, key]
            )
        else {
            return nil
        }
        return ZoteroProjectedAnnotation(
            type: row["annotation_type"],
            color: row["color"],
            pageLabel: row["page_label"],
            sortIndex: row["sort_index"],
            text: row["annotation_text"],
            comment: row["annotation_comment"],
            positionJSON: row["position_json"]
        )
    }

    static func string(_ key: String, in object: [String: JSONValue]) -> String {
        object[key]?.stringValue ?? ""
    }

    private static func optionalString(_ key: String, in object: [String: JSONValue]) -> String? {
        object[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }
}
