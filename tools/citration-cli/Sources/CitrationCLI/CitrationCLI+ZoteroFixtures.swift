import Foundation

extension CitrationCLI {
    func captureZoteroFixtures(arguments: [String]) async throws {
        let options = try ZoteroFixtureOptions(arguments: arguments, repoRoot: repoRoot)
        let client = ZoteroFixtureClient(
            serverURL: options.serverURL,
            userID: options.userID,
            apiKey: options.apiKey
        )

        print("Reading Zotero API v3 objects from \(options.serverURL.absoluteString)")
        let capture = try await client.capture()
        let sanitizer = ZoteroFixtureSanitizer()
        let sanitized = try sanitizer.sanitize(capture: capture)
        try sanitized.write(to: options.outputDirectory)

        print("Wrote \(sanitized.fixtureCount) sanitized fixtures to \(options.outputDirectory.path)")
        print("Captured library version \(capture.libraryVersion)")
    }
}

// MARK: - ZoteroFixtureOptions

private struct ZoteroFixtureOptions {
    // MARK: Lifecycle

    init(arguments: [String], repoRoot: URL) throws {
        var server = ProcessInfo.processInfo.environment["ZOTERO_SERVER_URL"]
            ?? "https://zotero.peacockery.studio"
        var userID = ProcessInfo.processInfo.environment["ZOTERO_USER_ID"] ?? "1"
        var outputDirectory = repoRoot
            .appending(path: "packages/citration-core-swift/Tests/CitrationCoreTests/Fixtures/Zotero")

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--server":
                server = try Self.value(after: argument, arguments: arguments, index: &index)

            case "--user-id":
                userID = try Self.value(after: argument, arguments: arguments, index: &index)

            case "--output":
                let value = try Self.value(after: argument, arguments: arguments, index: &index)
                outputDirectory = URL(fileURLWithPath: value, isDirectory: true)

            default:
                throw Self.error("Unknown fixture-capture option: \(argument)")
            }
            index += 1
        }

        guard let serverURL = URL(string: server), serverURL.scheme == "https", serverURL.host != nil else {
            throw Self.error("--server must be an absolute HTTPS URL")
        }
        guard !userID.isEmpty, userID.allSatisfy(\.isNumber) else {
            throw Self.error("--user-id must be numeric")
        }
        guard
            let apiKey = ProcessInfo.processInfo.environment["ZOTERO_API_KEY"]
            ?? ProcessInfo.processInfo.environment["SELFHOST_API_KEY"],
            !apiKey.isEmpty
        else {
            throw Self.error("Set ZOTERO_API_KEY or SELFHOST_API_KEY in the process environment")
        }

        self.serverURL = serverURL
        self.userID = userID
        self.apiKey = apiKey
        self.outputDirectory = outputDirectory
    }

    // MARK: Internal

    let serverURL: URL
    let userID: String
    let apiKey: String
    let outputDirectory: URL

    // MARK: Private

    private static func value(after option: String, arguments: [String], index: inout Int) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw error("Missing value after \(option)")
        }
        return arguments[index]
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "CitrationCLI.ZoteroFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - ZoteroFixtureClient

private struct ZoteroFixtureClient {
    // MARK: Internal

    let serverURL: URL
    let userID: String
    let apiKey: String

    func capture() async throws -> ZoteroFixtureCapture {
        let itemsResponse = try await paged(path: "/users/\(userID)/items")
        let collectionsResponse = try await paged(path: "/users/\(userID)/collections")
        let settingsResponse = try await request(path: "/users/\(userID)/settings")
        let deletedResponse = try await request(path: "/users/\(userID)/deleted", query: ["since": "0"])
        let fulltextInventoryResponse = try await request(path: "/users/\(userID)/fulltext", query: ["since": "0"])

        let items = try Self.objectArray(itemsResponse.value, endpoint: "items")
        let selectedItems = try ZoteroFixtureSelector.selectItems(from: items)
        let collections = try Self.objectArray(collectionsResponse.value, endpoint: "collections")
        let selectedCollections = ZoteroFixtureSelector.selectCollections(from: collections)

        let fulltextInventory = fulltextInventoryResponse.value as? [String: Any] ?? [:]
        guard
            let fulltextKey = ZoteroFixtureSelector.fulltextKey(
                selectedItems: selectedItems,
                inventory: fulltextInventory
            )
        else {
            throw Self.error("The live library did not expose a full-text fixture candidate")
        }
        let fulltextResponse = try await request(path: "/users/\(userID)/items/\(fulltextKey)/fulltext")

        let versions = [
            itemsResponse.libraryVersion,
            collectionsResponse.libraryVersion,
            settingsResponse.libraryVersion,
            deletedResponse.libraryVersion,
            fulltextInventoryResponse.libraryVersion,
            fulltextResponse.libraryVersion,
        ].compactMap(\.self)

        guard let libraryVersion = versions.max() else {
            throw Self.error("The server did not return Last-Modified-Version")
        }

        return ZoteroFixtureCapture(
            serverOrigin: serverURL.absoluteString,
            libraryVersion: libraryVersion,
            items: selectedItems,
            collections: selectedCollections,
            settings: settingsResponse.value,
            deleted: deletedResponse.value,
            fulltext: ["itemKey": fulltextKey, "data": fulltextResponse.value]
        )
    }

    // MARK: Private

    private static func objectArray(_ value: Any, endpoint: String) throws -> [[String: Any]] {
        guard let objects = value as? [[String: Any]] else {
            throw error("Expected an object array from \(endpoint)")
        }
        return objects
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "CitrationCLI.ZoteroFixtures", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func paged(path: String) async throws -> ZoteroFixtureResponse {
        var allObjects = [[String: Any]]()
        var start = 0
        var versions = [Int]()

        while true {
            let response = try await request(
                path: path,
                query: ["limit": "100", "start": String(start)]
            )
            let page = try Self.objectArray(response.value, endpoint: path)
            allObjects.append(contentsOf: page)
            if let version = response.libraryVersion {
                versions.append(version)
            }
            guard page.count == 100 else {
                break
            }
            start += page.count
        }

        return ZoteroFixtureResponse(value: allObjects, libraryVersion: versions.max())
    }

    private func request(path: String, query: [String: String] = [:]) async throws -> ZoteroFixtureResponse {
        var components = URLComponents(url: serverURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else {
            throw Self.error("Could not construct request URL for \(path)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw Self.error("The server returned a non-HTTP response for \(path)")
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw Self.error("GET \(path) returned HTTP \(response.statusCode)")
        }

        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let libraryVersion = response.value(forHTTPHeaderField: "Last-Modified-Version").flatMap(Int.init)
        return ZoteroFixtureResponse(value: value, libraryVersion: libraryVersion)
    }
}

// MARK: - ZoteroFixtureResponse

private struct ZoteroFixtureResponse {
    let value: Any
    let libraryVersion: Int?
}

// MARK: - ZoteroFixtureCapture

struct ZoteroFixtureCapture {
    let serverOrigin: String
    let libraryVersion: Int
    let items: [[String: Any]]
    let collections: [[String: Any]]
    let settings: Any
    let deleted: Any
    let fulltext: [String: Any]
}

// MARK: - ZoteroFixtureSelector

private enum ZoteroFixtureSelector {
    // MARK: Internal

    static func selectItems(from items: [[String: Any]]) throws -> [[String: Any]] {
        let requirements = [
            ItemRequirement(label: "book", field: "itemType", value: "book"),
            ItemRequirement(label: "preprint", field: "itemType", value: "preprint"),
            ItemRequirement(label: "journal-article", field: "itemType", value: "journalArticle"),
            ItemRequirement(label: "conference-paper", field: "itemType", value: "conferencePaper"),
            ItemRequirement(label: "note", field: "itemType", value: "note"),
            ItemRequirement(label: "attachment-pdf", field: "contentType", value: "application/pdf"),
            ItemRequirement(label: "attachment-epub", field: "contentType", value: "application/epub+zip"),
            ItemRequirement(label: "attachment-html", field: "contentType", value: "text/html"),
            ItemRequirement(label: "annotation-highlight", field: "annotationType", value: "highlight"),
            ItemRequirement(label: "annotation-underline", field: "annotationType", value: "underline"),
            ItemRequirement(label: "annotation-note", field: "annotationType", value: "note"),
            ItemRequirement(label: "annotation-ink", field: "annotationType", value: "ink"),
        ]

        var selected = [[String: Any]]()
        var selectedKeys = Set<String>()

        for requirement in requirements {
            guard let item = richestMatch(for: requirement, in: items) else {
                throw error("Missing required live fixture: \(requirement.label)")
            }
            append(item, to: &selected, keys: &selectedKeys)
        }

        for creatorRole in ["author", "editor", "contributor"] {
            guard let item = richestMatch(forCreatorRole: creatorRole, in: items) else {
                throw error("Missing required live creator role: \(creatorRole)")
            }
            append(item, to: &selected, keys: &selectedKeys)
        }

        let itemsByKey = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            objectKey(item).map { ($0, item) }
        })
        var selectedIndex = 0
        while selectedIndex < selected.count {
            if
                let parentKey = data(selected[selectedIndex])["parentItem"] as? String,
                let parent = itemsByKey[parentKey]
            {
                append(parent, to: &selected, keys: &selectedKeys)
            }
            selectedIndex += 1
        }

        return selected.sorted { objectKey($0) ?? "" < objectKey($1) ?? "" }
    }

    static func selectCollections(from collections: [[String: Any]]) -> [[String: Any]] {
        collections.sorted { objectKey($0) ?? "" < objectKey($1) ?? "" }
    }

    static func fulltextKey(selectedItems: [[String: Any]], inventory: [String: Any]) -> String? {
        let preferredKeys = selectedItems.compactMap { item -> String? in
            let itemData = data(item)
            guard itemData["contentType"] as? String == "application/pdf" else {
                return nil
            }
            return objectKey(item)
        }
        return preferredKeys.first(where: { inventory[$0] != nil }) ?? inventory.keys.min()
    }

    // MARK: Private

    private static func richestMatch(
        for requirement: ItemRequirement,
        in items: [[String: Any]]
    ) -> [String: Any]? {
        items
            .filter { data($0)[requirement.field] as? String == requirement.value }
            .max { lhs, rhs in
                let lhsScore = richness(lhs)
                let rhsScore = richness(rhs)
                if lhsScore == rhsScore {
                    return objectKey(lhs) ?? "" > objectKey(rhs) ?? ""
                }
                return lhsScore < rhsScore
            }
    }

    private static func richestMatch(forCreatorRole creatorRole: String, in items: [[String: Any]]) -> [String: Any]? {
        items
            .filter { item in
                let creators = data(item)["creators"] as? [[String: Any]] ?? []
                return creators.contains { $0["creatorType"] as? String == creatorRole }
            }
            .max { richness($0) < richness($1) }
    }

    private static func richness(_ object: [String: Any]) -> Int {
        let objectData = data(object)
        let creatorCount = (objectData["creators"] as? [Any])?.count ?? 0
        let tagCount = (objectData["tags"] as? [Any])?.count ?? 0
        let collectionCount = (objectData["collections"] as? [Any])?.count ?? 0
        return objectData.count + creatorCount * 3 + tagCount * 2 + collectionCount * 2
    }

    private static func append(
        _ item: [String: Any],
        to selected: inout [[String: Any]],
        keys: inout Set<String>
    ) {
        guard let key = objectKey(item), keys.insert(key).inserted else {
            return
        }
        selected.append(item)
    }

    private static func objectKey(_ object: [String: Any]) -> String? {
        object["key"] as? String ?? data(object)["key"] as? String
    }

    private static func data(_ object: [String: Any]) -> [String: Any] {
        object["data"] as? [String: Any] ?? [:]
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "CitrationCLI.ZoteroFixtures", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - ItemRequirement

private struct ItemRequirement {
    let label: String
    let field: String
    let value: String
}
