@testable import Citration
import Foundation
import Testing

// MARK: - EPUBPackageReaderTests

@Suite("EPUB Package Reader")
struct EPUBPackageReaderTests {
    @Test("resolves first spine document")
    func resolvesFirstSpineDocument() throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }

        let epubURL = try makeEPUB(
            in: tempDirectory,
            title: "Sample Book &amp; Notes",
            firstHref: "Text/chapter1.xhtml"
        )
        let unpackRoot = tempDirectory.appendingPathComponent("unpacked", isDirectory: true)

        let publication = try EPUBPackageReader(unpackRoot: unpackRoot).publication(from: epubURL)

        #expect(publication.title == "Sample Book & Notes")
        #expect(publication.initialDocumentURL.lastPathComponent == "chapter1.xhtml")
        #expect(publication.initialDocumentURL.path.contains("/OEBPS/Text/"))
        #expect(publication.packageDocumentURL.lastPathComponent == "package.opf")
        #expect(publication.readingOrder.map(\.idref) == ["chapter1", "chapter2"])
        #expect(publication.readingOrder.map(\.cfiBase) == ["/6/2", "/6/4"])
        #expect(publication.tableOfContents.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(publication.readingOrderIndex(forCFI: "epubcfi(/6/4!/4/2/1:0)") == 1)
        #expect(publication.readingOrderIndex(forCFI: "epub-start") == nil)
    }

    @Test("rejects unsafe archive entries")
    func rejectsUnsafeArchiveEntries() throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }

        let unsafeURL = try makeUnsafeEPUB(in: tempDirectory)
        let unpackRoot = tempDirectory.appendingPathComponent("unpacked", isDirectory: true)

        do {
            _ = try EPUBPackageReader(unpackRoot: unpackRoot).publication(from: unsafeURL)
            Issue.record("Expected unsafe EPUB archive to be rejected")
        } catch let error as EPUBPackageReaderError {
            guard case .unsafeArchiveEntry = error else {
                Issue.record("Expected unsafeArchiveEntry, got \(error)")
                return
            }
        }
    }

    @Test("searches real spine text without altering the publication")
    func searchesRealSpineText() throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }

        let epubURL = try makeEPUB(
            in: tempDirectory,
            title: "Search Book",
            firstHref: "Text/chapter1.xhtml"
        )
        let publication = try EPUBPackageReader(
            unpackRoot: tempDirectory.appendingPathComponent("unpacked", isDirectory: true)
        ).publication(from: epubURL)

        let results = publication.search("Readable text")
        #expect(results.count == 2)
        #expect(results.first?.readingOrderIndex == 0)
        #expect(results.first?.excerpt.contains("Readable text") == true)
        #expect(publication.search("missing phrase").isEmpty)
    }

    @Test("CFI base follows the actual OPF spine element index")
    func cfiBaseUsesActualSpineNodeIndex() throws {
        let tempDirectory = makeTempDirectory()
        defer { cleanupDirectory(tempDirectory) }

        let epubURL = try makeEPUB(
            in: tempDirectory,
            title: "Alternate Package Layout",
            firstHref: "Text/chapter1.xhtml",
            elementBeforeSpine: "<bindings/>"
        )
        let publication = try EPUBPackageReader(
            unpackRoot: tempDirectory.appendingPathComponent("unpacked", isDirectory: true)
        ).publication(from: epubURL)

        #expect(publication.readingOrder.map(\.cfiBase) == ["/8/2", "/8/4"])
        #expect(publication.readingOrderIndex(forCFI: "epubcfi(/8/4!/4/2/1:0)") == 1)
        #expect(publication.readingOrderIndex(forCFI: "epubcfi(/6/4!/4/2/1:0)") == nil)
    }
}

private extension EPUBPackageReaderTests {
    func makeEPUB(
        in tempDirectory: URL,
        title: String,
        firstHref: String,
        elementBeforeSpine: String = ""
    ) throws -> URL {
        let sourceDirectory = tempDirectory.appendingPathComponent("book-source", isDirectory: true)
        let metaDirectory = sourceDirectory.appendingPathComponent("META-INF", isDirectory: true)
        let oebpsDirectory = sourceDirectory.appendingPathComponent("OEBPS", isDirectory: true)
        let textDirectory = oebpsDirectory.appendingPathComponent("Text", isDirectory: true)

        try FileManager.default.createDirectory(at: metaDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true)

        try "application/epub+zip".write(
            to: sourceDirectory.appendingPathComponent("mimetype"),
            atomically: true,
            encoding: .utf8
        )
        try containerXML.write(
            to: metaDirectory.appendingPathComponent("container.xml"),
            atomically: true,
            encoding: .utf8
        )
        try packageXML(
            title: title,
            firstHref: firstHref,
            elementBeforeSpine: elementBeforeSpine
        ).write(
            to: oebpsDirectory.appendingPathComponent("package.opf"),
            atomically: true,
            encoding: .utf8
        )
        try ncxXML.write(
            to: oebpsDirectory.appendingPathComponent("toc.ncx"),
            atomically: true,
            encoding: .utf8
        )
        try chapterHTML(title: "Chapter 1").write(
            to: textDirectory.appendingPathComponent("chapter1.xhtml"),
            atomically: true,
            encoding: .utf8
        )
        try chapterHTML(title: "Chapter 2").write(
            to: textDirectory.appendingPathComponent("chapter2.xhtml"),
            atomically: true,
            encoding: .utf8
        )

        let epubURL = tempDirectory.appendingPathComponent("sample.epub")
        try runZip(
            arguments: ["-qr", epubURL.path, "mimetype", "META-INF", "OEBPS"],
            currentDirectory: sourceDirectory
        )
        return epubURL
    }

    func makeUnsafeEPUB(in tempDirectory: URL) throws -> URL {
        let sourceDirectory = tempDirectory.appendingPathComponent("unsafe-source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try "outside".write(
            to: tempDirectory.appendingPathComponent("outside.txt"),
            atomically: true,
            encoding: .utf8
        )

        let epubURL = tempDirectory.appendingPathComponent("unsafe.epub")
        try runZip(
            arguments: ["-q", epubURL.path, "../outside.txt"],
            currentDirectory: sourceDirectory
        )
        return epubURL
    }

    var containerXML: String {
        """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    }

    func packageXML(title: String, firstHref: String, elementBeforeSpine: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
          </metadata>
          <manifest>
            <item id="chapter1" href="\(firstHref)" media-type="application/xhtml+xml"/>
            <item id="chapter2" href="Text/chapter2.xhtml" media-type="application/xhtml+xml"/>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
          </manifest>
          \(elementBeforeSpine)
          <spine toc="ncx">
            <itemref idref="chapter1"/>
            <itemref idref="chapter2"/>
          </spine>
        </package>
        """
    }

    func chapterHTML(title: String) -> String {
        """
        <!doctype html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>\(title)</title></head>
        <body><h1>\(title)</h1><p>Readable text.</p></body>
        </html>
        """
    }

    var ncxXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
          <navMap>
            <navPoint id="one"><navLabel><text>Chapter 1</text></navLabel><content src="Text/chapter1.xhtml"/></navPoint>
            <navPoint id="two"><navLabel><text>Chapter 2</text></navLabel><content src="Text/chapter2.xhtml"/></navPoint>
          </navMap>
        </ncx>
        """
    }

    func runZip(arguments: [String], currentDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: details])
        }
    }

    func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("citration-epub-reader-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
