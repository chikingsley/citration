import Foundation

final class EPUBSpineIndexParserDelegate: NSObject, XMLParserDelegate {
    // MARK: Internal

    private(set) var spineNodeIndex: Int?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qualifiedNameValue: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        _ = parser
        _ = namespaceURI
        _ = attributeDict
        if depth == 1 {
            packageChildIndex += 1
            let name = qualifiedNameValue ?? elementName
            if name.split(separator: ":").last?.lowercased() == "spine" {
                spineNodeIndex = packageChildIndex
            }
        }
        depth += 1
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qualifiedNameValue: String?
    ) {
        _ = parser
        _ = elementName
        _ = namespaceURI
        _ = qualifiedNameValue
        depth -= 1
    }

    // MARK: Private

    private var depth = 0
    private var packageChildIndex = -1
}
