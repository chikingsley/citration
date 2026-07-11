import Foundation
import GRDB

public extension CitrationDatabase {
    func loadZoteroConnectionProfile() throws -> ZoteroConnectionProfile? {
        try databaseQueue.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM zotero_connection_profile WHERE id = 1") else {
                return nil
            }
            let serverURLValue: String = row["server_url"]
            guard let serverURL = URL(string: serverURLValue) else {
                throw ZoteroTransportError.invalidServerURL
            }
            return ZoteroConnectionProfile(
                serverURL: serverURL,
                userID: row["user_id"],
                username: row["username"],
                displayName: row["display_name"],
                canWrite: row["can_write"],
                canAccessFiles: row["can_access_files"]
            )
        }
    }

    func saveZoteroConnectionProfile(_ profile: ZoteroConnectionProfile) throws {
        let libraryID = try upsertLibrary(
            identity: profile.libraryIdentity,
            name: profile.displayName
        )
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO zotero_connection_profile (
                    id, server_url, user_id, username, display_name, can_write,
                    can_access_files, library_id, created_at, updated_at
                ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    server_url = excluded.server_url,
                    user_id = excluded.user_id,
                    username = excluded.username,
                    display_name = excluded.display_name,
                    can_write = excluded.can_write,
                    can_access_files = excluded.can_access_files,
                    library_id = excluded.library_id,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    profile.serverURL.absoluteString,
                    profile.userID,
                    profile.username,
                    profile.displayName,
                    profile.canWrite,
                    profile.canAccessFiles,
                    libraryID,
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ]
            )
        }
    }

    func clearZoteroConnectionProfile() throws {
        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM zotero_connection_profile WHERE id = 1")
        }
    }
}
