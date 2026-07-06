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
}

private extension EPUBPackageReaderTests {
    func makeEPUB(in tempDirectory: URL, title: String, firstHref: String) throws -> URL {
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
        try packageXML(title: title, firstHref: firstHref).write(
            to: oebpsDirectory.appendingPathComponent("package.opf"),
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

    func packageXML(title: String, firstHref: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
          </metadata>
          <manifest>
            <item id="chapter1" href="\(firstHref)" media-type="application/xhtml+xml"/>
            <item id="chapter2" href="Text/chapter2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
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
