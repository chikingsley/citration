public enum ItemType: String, Codable, CaseIterable, Sendable {
	case article
	case book
	case preprint
	case thesis
	case dataset
	case webpage
	case unknown
}
