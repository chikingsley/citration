extension AppModel {
    enum Route: String, CaseIterable, Identifiable {
        case workspace
        case components

        var id: String { rawValue }

        var title: String {
            switch self {
            case .workspace:
                return "Workspace"
            case .components:
                return "Components"
            }
        }
    }

    enum AttachmentImportMode {
        case auto
        case attachToSelectedItem
        case createNewItemPerFile
    }
}
