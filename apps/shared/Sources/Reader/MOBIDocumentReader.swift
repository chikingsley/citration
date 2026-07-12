import CoreFoundation
import Foundation

// The binary parsing structure is adapted from Readpaw's MIT-licensed
// MobiReader. See THIRD_PARTY_NOTICES.md.

// MARK: - MOBIDocument

struct MOBIDocument: Sendable {
    let title: String
    let html: String
}

// MARK: - MOBIDocumentReaderError

enum MOBIDocumentReaderError: LocalizedError {
    case encrypted
    case invalid(String)
    case unsupportedCompression(UInt16)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .encrypted:
            "This MOBI file is DRM-protected. Citration does not bypass ebook encryption."
        case let .invalid(message):
            "This MOBI file could not be read: \(message)"
        case let .unsupportedCompression(value):
            "This MOBI file uses unsupported compression type \(value)."
        }
    }
}

// MARK: - MOBIDocumentReader

enum MOBIDocumentReader {
    // MARK: Internal

    static func read(from url: URL) throws -> MOBIDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > 150 * 1024 * 1024 {
            throw MOBIDocumentReaderError.invalid("file exceeds the 150 MB safety limit")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 78 else {
            throw MOBIDocumentReaderError.invalid("Palm database header is truncated")
        }

        let recordCount = Int(readUInt16(data, offset: 76))
        guard recordCount > 1, data.count >= 78 + recordCount * 8 else {
            throw MOBIDocumentReaderError.invalid("record directory is missing")
        }
        var offsets = (0 ..< recordCount).map { index in
            Int(readUInt32(data, offset: 78 + index * 8))
        }
        offsets.append(data.count)
        guard let header = record(0, data: data, offsets: offsets), header.count >= 24 else {
            throw MOBIDocumentReaderError.invalid("book header is missing")
        }

        let compression = readUInt16(header, offset: 0)
        let textLength = Int(readUInt32(header, offset: 4))
        let textRecordCount = Int(readUInt16(header, offset: 8))
        guard readUInt16(header, offset: 12) == 0 else {
            throw MOBIDocumentReaderError.encrypted
        }

        let headerResult = parseMOBIHeader(header, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        var text = Data()
        text.reserveCapacity(textLength)
        if textRecordCount > 0 {
            for index in 1 ... textRecordCount {
                guard var bytes = record(index, data: data, offsets: offsets) else {
                    break
                }
                bytes = stripTrailingEntries(bytes)
                switch compression {
                case 1:
                    text.append(bytes)
                case 2:
                    text.append(decompressPalmDOC(bytes))
                default:
                    throw MOBIDocumentReaderError.unsupportedCompression(compression)
                }
                if text.count >= textLength {
                    break
                }
            }
        }
        if text.count > textLength {
            text = text.prefix(textLength)
        }
        guard !text.isEmpty else {
            throw MOBIDocumentReaderError.invalid("book contains no readable text records")
        }
        let decoded = try decode(text, preferredEncoding: headerResult.encoding)
        let body = decoded.replacingOccurrences(of: "\u{0000}", with: "")
        return MOBIDocument(title: headerResult.title, html: wrap(body: body, title: headerResult.title))
    }

    // MARK: Private

    private static func decode(_ data: Data, preferredEncoding: String.Encoding) throws -> String {
        if
            let decoded = String(bytes: data, encoding: preferredEncoding)
            ?? String(bytes: data, encoding: .utf8)
            ?? String(bytes: data, encoding: .isoLatin1)
        {
            return decoded
        }
        throw MOBIDocumentReaderError.invalid("book text uses an unsupported encoding")
    }

    private static func parseMOBIHeader(
        _ header: Data,
        fallbackTitle: String
    ) -> (title: String, encoding: String.Encoding) {
        guard header.count >= 132, header.subdata(in: 16 ..< 20) == Data("MOBI".utf8) else {
            return (fallbackTitle, .utf8)
        }
        let encoding: String.Encoding = switch readUInt32(header, offset: 44) {
        case 1252: .windowsCP1252
        default: .utf8
        }
        if let title = exthTitle(in: header, encoding: encoding) {
            return (title, encoding)
        }
        let titleOffset = Int(readUInt32(header, offset: 84))
        let titleLength = Int(readUInt32(header, offset: 88))
        guard
            titleOffset > 0,
            titleLength > 0,
            titleOffset + titleLength <= header.count,
            let title = String(bytes: header[titleOffset ..< titleOffset + titleLength], encoding: encoding),
            !title.isEmpty
        else {
            return (fallbackTitle, encoding)
        }
        return (title, encoding)
    }

    private static func exthTitle(in header: Data, encoding: String.Encoding) -> String? {
        let exthOffset = 16 + Int(readUInt32(header, offset: 20))
        guard
            exthOffset + 12 <= header.count,
            header[exthOffset ..< exthOffset + 4] == Data("EXTH".utf8)
        else {
            return nil
        }
        let recordCount = Int(readUInt32(header, offset: exthOffset + 8))
        var offset = exthOffset + 12
        for _ in 0 ..< recordCount {
            let type = readUInt32(header, offset: offset)
            let length = Int(readUInt32(header, offset: offset + 4))
            guard length >= 8, offset + length <= header.count else {
                return nil
            }
            if type == 99 || type == 503 || type == 508 {
                return String(bytes: header[offset + 8 ..< offset + length], encoding: encoding)
            }
            offset += length
        }
        return nil
    }

    private static func record(_ index: Int, data: Data, offsets: [Int]) -> Data? {
        guard index >= 0, index + 1 < offsets.count else {
            return nil
        }
        let start = offsets[index]
        let end = offsets[index + 1]
        guard start >= 0, end > start, end <= data.count else {
            return nil
        }
        return data.subdata(in: start ..< end)
    }

    private static func stripTrailingEntries(_ input: Data) -> Data {
        guard input.count > 4 else {
            return input
        }
        var output = input
        let entryCount = Int(output[output.endIndex - 1] & 0b111)
        for _ in 0 ..< entryCount {
            var index = output.endIndex - 1
            while index > output.startIndex {
                if output[index] & 0x80 != 0 {
                    output = output.subdata(in: output.startIndex ..< index)
                    break
                }
                index -= 1
            }
        }
        return output
    }

    private static func decompressPalmDOC(_ input: Data) -> Data {
        var output = Data()
        output.reserveCapacity(input.count * 2)
        var index = input.startIndex
        while index < input.endIndex {
            let byte = input[index]
            switch byte {
            case 0x00,
                 0x09 ... 0x7F:
                output.append(byte)
                index += 1

            case 0x01 ... 0x08:
                let count = min(Int(byte), input.endIndex - index - 1)
                index += 1
                if count > 0 {
                    output.append(input.subdata(in: index ..< index + count))
                    index += count
                }

            case 0x80 ... 0xBF:
                guard index + 1 < input.endIndex else {
                    return output
                }
                let pair = (UInt16(byte) << 8) | UInt16(input[index + 1])
                let distance = Int((pair & 0x3FFF) >> 3)
                let length = Int(pair & 0b111) + 3
                if distance > 0, distance <= output.count {
                    for _ in 0 ..< length {
                        output.append(output[output.endIndex - distance])
                    }
                }
                index += 2

            default:
                output.append(0x20)
                output.append(byte ^ 0x80)
                index += 1
            }
        }
        return output
    }

    private static func wrap(body: String, title: String) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(escapedTitle)</title>
        <style>
        :root { color-scheme: light dark; }
        body { max-width: 46rem; margin: 0 auto; padding: 7vh 7vw 12vh; font: 1.15rem/1.65 ui-serif, serif; }
        img, svg { max-width: 100%; height: auto; }
        p { orphans: 2; widows: 2; }
        </style></head><body>\(body)</body></html>
        """
    }

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else {
            return 0
        }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else {
            return 0
        }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}

private extension String.Encoding {
    static let windowsCP1252: String.Encoding = {
        let coreFoundation = CFStringEncoding(0x0500)
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(coreFoundation))
    }()
}
