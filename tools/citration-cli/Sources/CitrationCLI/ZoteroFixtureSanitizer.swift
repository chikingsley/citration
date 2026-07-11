import Foundation

// MARK: - ZoteroFixtureSanitizer

final class ZoteroFixtureSanitizer {
    // MARK: Internal

    func sanitize(capture: ZoteroFixtureCapture) throws -> SanitizedFixtureSet {
        keyMap.removeAll()
        stringCounter = 0
        dateCounter = 0
        unsafeOriginalStrings.removeAll()
        preservedOriginalStrings.removeAll()

        let fixtures: [String: Any] = [
            "items.json": sanitize(capture.items, field: "items"),
            "collections.json": sanitize(capture.collections, field: "collections"),
            "settings.json": sanitize(capture.settings, field: "settings"),
            "deleted.json": sanitize(capture.deleted, field: "deleted"),
            "fulltext.json": sanitize(capture.fulltext, field: "fulltext"),
        ]

        let manifest: [String: Any] = [
            "apiVersion": 3,
            "capturedOn": "2026-07-10",
            "fixtureFiles": fixtures.keys.sorted(),
            "libraryVersion": capture.libraryVersion,
            "provenance": "Read-only capture from \(capture.serverOrigin)",
            "sanitizerVersion": 1,
            "serverSoftware": "Zotero Self-Host Server",
            "selection": [
                "Richest live object for each required item, attachment, and annotation type",
                "Related parent objects required to preserve parent-child structure",
                "Complete collection hierarchy plus one complete full-text response",
            ],
        ]

        let result = SanitizedFixtureSet(fixtures: fixtures, manifest: manifest)
        try assertNoPrivateStrings(in: result)
        return result
    }

    // MARK: Private

    private var keyMap: [String: String] = [:]
    private var stringCounter = 0
    private var dateCounter = 0
    private var unsafeOriginalStrings: Set<String> = []
    private var preservedOriginalStrings: Set<String> = []

    private let structuralFields: Set<String> = [
        "annotationColor", "annotationPosition", "annotationSortIndex", "annotationType", "charset", "contentType",
        "creatorType", "itemType", "linkMode", "type",
    ]

    private func sanitize(_ value: Any, field: String) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().reduce(into: [String: Any]()) { result, key in
                result[sanitizeDictionaryKey(key)] = sanitize(dictionary[key] as Any, field: key)
            }
        }
        if let array = value as? [Any] {
            return array.map { sanitize($0, field: field) }
        }
        if let string = value as? String {
            return sanitize(string, field: field)
        }
        if value is NSNull {
            return NSNull()
        }
        if let number = value as? NSNumber {
            if field == "id" || field == "userID" {
                return 1
            }
            return number
        }
        return value
    }

    private func sanitize(_ value: String, field: String) -> String {
        guard !value.isEmpty else {
            return value
        }
        if structuralFields.contains(field) {
            preservedOriginalStrings.insert(value)
            return value
        }
        if field == "key" || field == "parentItem" || field == "parentCollection" || isZoteroKey(value) {
            return mappedKey(value)
        }

        unsafeOriginalStrings.insert(value)

        if field.hasPrefix("date") || field == "accessDate" {
            dateCounter += 1
            return String(format: "2024-01-%02dT12:00:00Z", (dateCounter - 1) % 28 + 1)
        }
        if field == "filename" {
            let fileExtension = URL(fileURLWithPath: value).pathExtension.lowercased()
            return fileExtension.isEmpty ? "fixture-document" : "fixture-document.\(fileExtension)"
        }
        if field == "md5" {
            return "00000000000000000000000000000000"
        }
        if field == "DOI" {
            stringCounter += 1
            return "10.0000/fixture.\(stringCounter)"
        }
        if field == "ISBN" {
            return "9780000000002"
        }
        if field == "ISSN" {
            return "0000-0000"
        }
        if field == "PMID" {
            return "10000000"
        }
        if field == "PMCID" {
            return "PMC1000000"
        }
        if field == "annotationPageLabel" {
            return "1"
        }
        if field == "href" || field == "url" || value.hasPrefix("http://") || value.hasPrefix("https://") {
            stringCounter += 1
            return "https://example.invalid/fixture/\(stringCounter)"
        }
        if field == "tag" {
            stringCounter += 1
            return "Fixture Tag \(stringCounter)"
        }
        if field == "name" {
            return "Sanitized Library"
        }

        stringCounter += 1
        let normalizedField = field
            .replacingOccurrences(of: #"[^A-Za-z0-9-]"#, with: "-", options: .regularExpression)
            .lowercased()
        return "fixture-\(normalizedField)-\(stringCounter)"
    }

    private func mappedKey(_ value: String) -> String {
        if let mapped = keyMap[value] {
            return mapped
        }
        unsafeOriginalStrings.insert(value)
        let mapped = String(format: "A%07d", keyMap.count + 1)
        keyMap[value] = mapped
        return mapped
    }

    private func isZoteroKey(_ value: String) -> Bool {
        value.range(of: #"^[A-Z0-9]{8}$"#, options: .regularExpression) != nil
    }

    private func sanitizeDictionaryKey(_ key: String) -> String {
        if isZoteroKey(key) {
            return mappedKey(key)
        }
        if key.hasPrefix("http://") || key.hasPrefix("https://") {
            unsafeOriginalStrings.insert(key)
            stringCounter += 1
            return "https://example.invalid/relation/\(stringCounter)"
        }
        return key
    }

    private func assertNoPrivateStrings(in fixtureSet: SanitizedFixtureSet) throws {
        var outputStrings = Set<String>()
        collectStrings(from: fixtureSet.fixtures, into: &outputStrings)
        collectStrings(from: fixtureSet.manifest, into: &outputStrings)
        let leaked = unsafeOriginalStrings
            .subtracting(preservedOriginalStrings)
            .intersection(outputStrings)
            .filter { $0.count >= 4 }
            .sorted()
        guard leaked.isEmpty else {
            throw error("Sanitization leak check failed for \(leaked.count) source strings")
        }
    }

    private func collectStrings(from value: Any, into strings: inout Set<String>) {
        if let dictionary = value as? [String: Any] {
            strings.formUnion(dictionary.keys)
            for value in dictionary.values {
                collectStrings(from: value, into: &strings)
            }
        } else if let array = value as? [Any] {
            for value in array {
                collectStrings(from: value, into: &strings)
            }
        } else if let string = value as? String {
            strings.insert(string)
        }
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "CitrationCLI.ZoteroFixtures", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - SanitizedFixtureSet

struct SanitizedFixtureSet {
    // MARK: Internal

    let fixtures: [String: Any]
    let manifest: [String: Any]

    var fixtureCount: Int {
        fixtures.count
    }

    func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let expectedFiles = Set(fixtures.keys).union(["manifest.json"])
        let existingFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for file in existingFiles where file.pathExtension == "json" && !expectedFiles.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }

        for (filename, value) in fixtures {
            try Self.data(for: value).write(to: directory.appending(path: filename), options: .atomic)
        }
        try Self.data(for: manifest).write(to: directory.appending(path: "manifest.json"), options: .atomic)
    }

    func serializedData() throws -> Data {
        try Self.data(for: ["fixtures": fixtures, "manifest": manifest])
    }

    // MARK: Private

    private static func data(for value: Any) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }
}
