@testable import CitrationCore
import Foundation
import Testing

@Suite("Zotero raw object compatibility")
struct ZoteroRawObjectTests {
    // MARK: Internal

    @Test("JSON primitives retain their exact kinds")
    func primitivesRoundTrip() throws {
        let source = Data(#"{"bool":true,"integer":42,"null":null,"number":1.25,"string":"value"}"#.utf8)

        let decoded = try ZoteroJSON.decode(source)
        let encoded = try ZoteroJSON.encode(decoded)
        let redecoded = try ZoteroJSON.decode(encoded)

        #expect(decoded == redecoded)
        #expect(decoded.objectValue?["integer"] == .integer(42))
        #expect(decoded.objectValue?["number"] == .number(1.25))
    }

    @Test("A raw object exposes identity without narrowing its fields")
    func objectIdentity() throws {
        let source = Data(
            #"{"data":{"futureField":{"nested":[1,true,null]},"itemType":"book","key":"AAAA0001","version":7},"key":"AAAA0001","version":7}"#.utf8
        )

        let object = try JSONDecoder().decode(ZoteroRawObject.self, from: source)
        let redecoded = try JSONDecoder().decode(
            ZoteroRawObject.self,
            from: ZoteroJSON.encode(object.rawValue)
        )

        #expect(object.key == "AAAA0001")
        #expect(object.version == 7)
        #expect(object.itemType == "book")
        #expect(redecoded == object)
        #expect(redecoded.data["futureField"] == object.data["futureField"])
    }

    @Test("Every captured fixture structurally round-trips")
    func capturedFixturesRoundTrip() throws {
        let fixtureDirectory = try fixtureDirectory()
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: fixtureDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" && $0.lastPathComponent != "manifest.json" }

        #expect(!fixtureURLs.isEmpty)

        for fixtureURL in fixtureURLs {
            let source = try Data(contentsOf: fixtureURL)
            let decoded = try ZoteroJSON.decode(source)
            let encoded = try ZoteroJSON.encode(decoded)
            let redecoded = try ZoteroJSON.decode(encoded)

            #expect(redecoded == decoded, "Fixture changed: \(fixtureURL.lastPathComponent)")
        }
    }

    @Test("Captured items cover the live compatibility contract")
    func capturedItemCoverage() throws {
        let data = try Data(contentsOf: fixtureDirectory().appending(path: "items.json"))
        let objects = try JSONDecoder().decode([ZoteroRawObject].self, from: data)

        let itemTypes = Set(objects.compactMap(\.itemType))
        #expect(itemTypes.isSuperset(of: [
            "annotation", "attachment", "book", "conferencePaper", "journalArticle", "note", "preprint",
        ]))

        let annotationTypes = Set(objects.compactMap { $0.data["annotationType"]?.stringValue })
        #expect(annotationTypes == ["highlight", "ink", "note", "underline"])

        let contentTypes = Set(objects.compactMap { $0.data["contentType"]?.stringValue })
        #expect(contentTypes.isSuperset(of: ["application/epub+zip", "application/pdf", "text/html"]))

        let creatorRoles = Set(objects.flatMap { object in
            object.data["creators"]?.arrayValue?.compactMap { creator in
                creator.objectValue?["creatorType"]?.stringValue
            } ?? []
        })
        #expect(creatorRoles.isSuperset(of: ["author", "contributor", "editor"]))

        let keys = Set(objects.compactMap(\.key))
        let parentKeys = Set(objects.compactMap { $0.data["parentItem"]?.stringValue })
        #expect(parentKeys.isSubset(of: keys))
    }

    // MARK: Private

    private func fixtureDirectory() throws -> URL {
        try #require(Bundle.module.resourceURL?.appending(path: "Fixtures/Zotero"))
    }
}
