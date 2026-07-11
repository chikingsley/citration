import GRDB

extension CitrationDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_zotero_raw_store") { database in
            try database.execute(sql: """
            CREATE TABLE libraries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                remote_type TEXT NOT NULL,
                remote_id INTEGER NOT NULL,
                name TEXT,
                current_version INTEGER NOT NULL DEFAULT 0 CHECK (current_version >= 0),
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE (remote_type, remote_id)
            );

            CREATE TABLE zotero_objects (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                object_kind TEXT NOT NULL,
                object_key TEXT NOT NULL,
                object_version INTEGER NOT NULL CHECK (object_version >= 0),
                object_type TEXT,
                current_json BLOB NOT NULL,
                pristine_json BLOB NOT NULL,
                sync_state TEXT NOT NULL CHECK (sync_state IN ('synced', 'dirty', 'deleted', 'failed')),
                is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
                failure_message TEXT,
                updated_at REAL NOT NULL,
                PRIMARY KEY (library_id, object_kind, object_key)
            ) WITHOUT ROWID;

            CREATE INDEX zotero_objects_by_type
                ON zotero_objects(library_id, object_kind, object_type);
            CREATE INDEX zotero_objects_by_state
                ON zotero_objects(library_id, sync_state, is_deleted);
            """)
        }
        migrator.registerMigration("v2_create_projections_and_local_state") { database in
            try database.execute(sql: """
            CREATE TABLE item_projections (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                item_type TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                abstract_note TEXT NOT NULL DEFAULT '',
                date_text TEXT NOT NULL DEFAULT '',
                publication_title TEXT NOT NULL DEFAULT '',
                doi TEXT NOT NULL DEFAULT '',
                isbn TEXT NOT NULL DEFAULT '',
                issn TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL DEFAULT '',
                language TEXT NOT NULL DEFAULT '',
                rights TEXT NOT NULL DEFAULT '',
                extra TEXT NOT NULL DEFAULT '',
                parent_item_key TEXT,
                note_html TEXT,
                PRIMARY KEY (library_id, item_key)
            ) WITHOUT ROWID;

            CREATE INDEX item_projections_by_type
                ON item_projections(library_id, item_type, title);
            CREATE INDEX item_projections_by_parent
                ON item_projections(library_id, parent_item_key);

            CREATE TABLE item_creators (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                position INTEGER NOT NULL CHECK (position >= 0),
                creator_type TEXT NOT NULL,
                first_name TEXT,
                last_name TEXT,
                literal_name TEXT,
                raw_json BLOB NOT NULL,
                PRIMARY KEY (library_id, item_key, position),
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;

            CREATE TABLE item_tags (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                position INTEGER NOT NULL CHECK (position >= 0),
                tag TEXT NOT NULL,
                tag_type INTEGER,
                raw_json BLOB NOT NULL,
                PRIMARY KEY (library_id, item_key, position),
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;

            CREATE INDEX item_tags_by_value ON item_tags(library_id, tag);

            CREATE TABLE collection_projections (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                collection_key TEXT NOT NULL,
                collection_version INTEGER NOT NULL CHECK (collection_version >= 0),
                name TEXT NOT NULL,
                parent_collection_key TEXT,
                PRIMARY KEY (library_id, collection_key),
                FOREIGN KEY (library_id, parent_collection_key)
                    REFERENCES collection_projections(library_id, collection_key)
                    ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
            ) WITHOUT ROWID;

            CREATE INDEX collections_by_parent
                ON collection_projections(library_id, parent_collection_key, name);

            CREATE TABLE collection_items (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                collection_key TEXT NOT NULL,
                item_key TEXT NOT NULL,
                position INTEGER NOT NULL CHECK (position >= 0),
                PRIMARY KEY (library_id, collection_key, item_key),
                FOREIGN KEY (library_id, collection_key)
                    REFERENCES collection_projections(library_id, collection_key) ON DELETE CASCADE,
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;

            CREATE INDEX collection_items_by_item
                ON collection_items(library_id, item_key, collection_key);

            CREATE TABLE attachment_projections (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                parent_item_key TEXT,
                link_mode TEXT NOT NULL,
                content_type TEXT NOT NULL DEFAULT '',
                charset TEXT NOT NULL DEFAULT '',
                filename TEXT NOT NULL DEFAULT '',
                remote_url TEXT NOT NULL DEFAULT '',
                remote_md5 TEXT,
                remote_mtime INTEGER,
                cache_state TEXT NOT NULL DEFAULT 'notDownloaded'
                    CHECK (cache_state IN ('notDownloaded', 'downloading', 'downloaded', 'failed', 'stale')),
                local_path TEXT,
                verified_sha256 TEXT,
                downloaded_at REAL,
                PRIMARY KEY (library_id, item_key),
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;

            CREATE INDEX attachments_by_parent
                ON attachment_projections(library_id, parent_item_key, content_type);
            CREATE INDEX attachments_by_cache_state
                ON attachment_projections(library_id, cache_state);

            CREATE TABLE annotation_projections (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                parent_item_key TEXT NOT NULL,
                annotation_type TEXT NOT NULL,
                color TEXT NOT NULL DEFAULT '',
                page_label TEXT NOT NULL DEFAULT '',
                sort_index TEXT NOT NULL DEFAULT '',
                annotation_text TEXT NOT NULL DEFAULT '',
                annotation_comment TEXT NOT NULL DEFAULT '',
                position_json TEXT NOT NULL,
                PRIMARY KEY (library_id, item_key),
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;

            CREATE INDEX annotations_by_parent
                ON annotation_projections(library_id, parent_item_key, sort_index);

            CREATE TABLE fulltext_content (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                object_version INTEGER NOT NULL CHECK (object_version >= 0),
                content TEXT NOT NULL DEFAULT '',
                content_type TEXT NOT NULL DEFAULT '',
                charset TEXT NOT NULL DEFAULT '',
                indexed_pages INTEGER,
                total_pages INTEGER,
                updated_at REAL NOT NULL,
                PRIMARY KEY (library_id, item_key)
            ) WITHOUT ROWID;

            CREATE TABLE synchronization_failures (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                object_kind TEXT NOT NULL,
                object_key TEXT NOT NULL,
                operation TEXT NOT NULL,
                message TEXT NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
                next_retry_at REAL,
                created_at REAL NOT NULL,
                resolved_at REAL
            );

            CREATE INDEX synchronization_failures_pending
                ON synchronization_failures(library_id, resolved_at, next_retry_at);

            CREATE TABLE reader_state (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                locator_json BLOB,
                fraction_complete REAL NOT NULL DEFAULT 0
                    CHECK (fraction_complete >= 0 AND fraction_complete <= 1),
                selected_page INTEGER,
                updated_at REAL NOT NULL,
                PRIMARY KEY (library_id, item_key)
            ) WITHOUT ROWID;

            CREATE VIRTUAL TABLE library_search USING fts5(
                library_id UNINDEXED,
                object_key UNINDEXED,
                object_kind UNINDEXED,
                title,
                creators,
                tags,
                note_text,
                annotation_text,
                fulltext,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            """)
        }
        migrator.registerMigration("v3_create_complete_item_field_projections") { database in
            try database.execute(sql: """
            CREATE TABLE item_fields (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                field_name TEXT NOT NULL,
                value_kind TEXT NOT NULL
                    CHECK (value_kind IN ('null', 'boolean', 'integer', 'number', 'string', 'array', 'object')),
                field_value BLOB NOT NULL,
                text_value TEXT,
                integer_value INTEGER,
                number_value REAL,
                boolean_value INTEGER CHECK (boolean_value IS NULL OR boolean_value IN (0, 1)),
                PRIMARY KEY (library_id, item_key, field_name),
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;

            CREATE INDEX item_fields_by_name_text
                ON item_fields(library_id, field_name, text_value);

            CREATE TABLE item_identifiers (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                position INTEGER NOT NULL CHECK (position >= 0),
                identifier_type TEXT NOT NULL,
                identifier_value TEXT NOT NULL,
                PRIMARY KEY (library_id, item_key, position),
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;

            CREATE INDEX item_identifiers_by_value
                ON item_identifiers(library_id, identifier_type, identifier_value);
            """)
        }
        migrator.registerMigration("v4_create_legacy_migration_state") { database in
            try database.execute(sql: """
            CREATE TABLE legacy_migration_runs (
                migration_name TEXT PRIMARY KEY,
                source_fingerprint TEXT NOT NULL,
                status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
                backup_path TEXT NOT NULL,
                report_json BLOB,
                error_message TEXT,
                started_at REAL NOT NULL,
                completed_at REAL
            ) WITHOUT ROWID;

            CREATE TABLE legacy_records (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                entity_kind TEXT NOT NULL,
                legacy_id TEXT NOT NULL,
                payload_json BLOB NOT NULL,
                migrated_object_kind TEXT,
                migrated_object_key TEXT,
                PRIMARY KEY (library_id, entity_kind, legacy_id)
            ) WITHOUT ROWID;

            CREATE TABLE app_relationships (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                relationship_id TEXT NOT NULL,
                source_item_key TEXT NOT NULL,
                target_item_key TEXT NOT NULL,
                relationship_kind TEXT NOT NULL,
                confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
                note TEXT,
                raw_json BLOB NOT NULL,
                PRIMARY KEY (library_id, relationship_id)
            ) WITHOUT ROWID;

            CREATE INDEX app_relationships_by_source
                ON app_relationships(library_id, source_item_key, relationship_kind);
            CREATE INDEX app_relationships_by_target
                ON app_relationships(library_id, target_item_key, relationship_kind);
            """)
        }
        migrator.registerMigration("v5_create_app_object_identity") { database in
            try database.execute(sql: """
            CREATE TABLE app_object_identity (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                object_kind TEXT NOT NULL,
                object_key TEXT NOT NULL,
                app_uuid TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (library_id, object_kind, object_key),
                UNIQUE (library_id, app_uuid)
            ) WITHOUT ROWID;

            CREATE INDEX app_object_identity_by_uuid
                ON app_object_identity(library_id, app_uuid);

            CREATE TABLE app_collection_memberships (
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                collection_key TEXT NOT NULL,
                item_key TEXT NOT NULL,
                membership_uuid TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY (library_id, collection_key, item_key),
                UNIQUE (library_id, membership_uuid),
                FOREIGN KEY (library_id, collection_key)
                    REFERENCES collection_projections(library_id, collection_key) ON DELETE CASCADE,
                FOREIGN KEY (library_id, item_key)
                    REFERENCES item_projections(library_id, item_key) ON DELETE CASCADE
            ) WITHOUT ROWID;
            """)
        }
        migrator.registerMigration("v6_create_zotero_connection_profile") { database in
            try database.execute(sql: """
            CREATE TABLE zotero_connection_profile (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                server_url TEXT NOT NULL,
                user_id INTEGER NOT NULL CHECK (user_id >= 0),
                username TEXT NOT NULL,
                display_name TEXT NOT NULL,
                can_write INTEGER NOT NULL CHECK (can_write IN (0, 1)),
                can_access_files INTEGER NOT NULL CHECK (can_access_files IN (0, 1)),
                library_id INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """)
        }
        migrator.registerMigration("v7_add_synchronization_failure_details") { database in
            try database.execute(sql: """
            ALTER TABLE synchronization_failures ADD COLUMN details_json BLOB;
            ALTER TABLE synchronization_failures ADD COLUMN last_attempt_at REAL;
            CREATE INDEX synchronization_failures_by_object
                ON synchronization_failures(library_id, object_kind, object_key, operation, resolved_at);
            """)
        }
        migrator.registerMigration("v8_preserve_attachment_transfer_state") { database in
            try database.execute(sql: """
            ALTER TABLE attachment_projections ADD COLUMN verified_md5 TEXT;
            ALTER TABLE attachment_projections ADD COLUMN transfer_error TEXT;
            ALTER TABLE attachment_projections ADD COLUMN transfer_attempted_at REAL;
            """)
        }
        return migrator
    }
}
