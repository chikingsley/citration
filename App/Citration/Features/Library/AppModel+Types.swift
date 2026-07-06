extension AppModel {
    enum Route: String, CaseIterable, Identifiable {
        case workspace
        case components

        // MARK: Internal

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .workspace:
                "Workspace"
            case .components:
                "Components"
            }
        }
    }

    enum AttachmentImportMode {
        case auto
        case attachToSelectedItem
        case createNewItemPerFile
    }
}
