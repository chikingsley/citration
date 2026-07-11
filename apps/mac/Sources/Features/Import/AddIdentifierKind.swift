import CitrationCore

enum AddIdentifierKind: String, CaseIterable, Identifiable {
    case doi
    case isbn
    case arxiv

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .doi: "DOI"
        case .isbn: "ISBN"
        case .arxiv: "arXiv"
        }
    }

    var identifierType: IdentifierType {
        switch self {
        case .doi: .doi
        case .isbn: .isbn
        case .arxiv: .arxiv
        }
    }

    var prompt: String {
        switch self {
        case .doi: "10.1000/example"
        case .isbn: "9780000000000"
        case .arxiv: "2401.01234"
        }
    }
}
