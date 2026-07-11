import CitrationCore
import SwiftUI

struct ItemInfoInspectorSection: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let item: SynchronizedLibraryItem

    var body: some View {
        Section("Info") {
            LabeledContent("Item Type", value: fieldLabel(item.projected.itemType))
            LabeledContent("Zotero Key") {
                Text(item.identity.objectKey).textSelection(.enabled)
            }
        }
        .task(id: item.identity) {
            resetDrafts(from: item)
        }

        if !item.projected.creators.isEmpty {
            Section("Creators") {
                ForEach(item.projected.creators, id: \.position) { creator in
                    LabeledContent(fieldLabel(creator.creatorType)) {
                        Text(creatorName(creator)).textSelection(.enabled)
                    }
                }
            }
        }

        Section("Fields") {
            ForEach(editableStringFields, id: \.self) { field in
                LabeledContent(fieldLabel(field)) {
                    TextField(fieldLabel(field), text: binding(for: field), axis: field == "abstractNote" ? .vertical : .horizontal)
                        .labelsHidden()
                        .lineLimit(field == "abstractNote" ? 3 ... 8 : 1 ... 2)
                }
            }

            Button("Save Changes", systemImage: "checkmark") {
                saveChanges()
            }
            .disabled(!hasChanges || isSaving)
        }

        if !preservedFields.isEmpty {
            Section("Preserved Data") {
                ForEach(preservedFields, id: \.0) { field, value in
                    LabeledContent(fieldLabel(field)) {
                        Text(displayValue(value))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: Private

    private static let readOnlyFields: Set = .init([
        "dateAdded", "dateModified", "itemType", "key", "version",
    ])

    private static let hiddenStructuralFields: Set = .init([
        "collections", "creators", "tags",
    ])

    @State private var drafts: [String: String] = [:]
    @State private var isSaving = false

    private var editableStringFields: [String] {
        item.projected.fields
            .filter { field, value in
                value.stringValue != nil && !Self.readOnlyFields.contains(field)
            }
            .map(\.key)
            .sorted(by: compareFields)
    }

    private var preservedFields: [(String, JSONValue)] {
        item.projected.fields
            .filter { field, value in
                value.stringValue == nil && !Self.hiddenStructuralFields.contains(field)
            }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private var hasChanges: Bool {
        editableStringFields.contains { field in
            drafts[field] != item.projected.fields[field]?.stringValue
        }
    }

    private func binding(for field: String) -> Binding<String> {
        Binding(
            get: { drafts[field] ?? item.projected.fields[field]?.stringValue ?? "" },
            set: { drafts[field] = $0 }
        )
    }

    private func resetDrafts(from item: SynchronizedLibraryItem) {
        drafts = Dictionary(uniqueKeysWithValues: item.projected.fields.compactMap { field, value in
            value.stringValue.map { (field, $0) }
        })
    }

    private func saveChanges() {
        let updates = editableStringFields.compactMap { field -> ZoteroItemFieldUpdate? in
            guard
                let value = drafts[field],
                value != item.projected.fields[field]?.stringValue
            else {
                return nil
            }
            return ZoteroItemFieldUpdate(field: field, value: .string(value))
        }
        guard !updates.isEmpty else {
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let updated = try await model.updateItemFields(identity: item.identity, updates: updates)
                resetDrafts(from: updated)
            } catch {
                model.statusMessage = "Failed to update item"
            }
        }
    }

    private func compareFields(_ lhs: String, _ rhs: String) -> Bool {
        let priority = [
            "title", "abstractNote", "date", "publicationTitle", "bookTitle", "proceedingsTitle",
            "DOI", "ISBN", "ISSN", "url", "language", "rights", "extra",
        ]
        let left = priority.firstIndex(of: lhs) ?? priority.endIndex
        let right = priority.firstIndex(of: rhs) ?? priority.endIndex
        if left == right {
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return left < right
    }

    private func creatorName(_ creator: ZoteroProjectedCreator) -> String {
        if let literal = creator.literalName, !literal.isEmpty {
            return literal
        }
        return [creator.firstName, creator.lastName]
            .compactMap { $0?.bcTrimmedNonEmpty }
            .joined(separator: " ")
    }

    private func fieldLabel(_ field: String) -> String {
        field
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .replacingOccurrences(of: "Doi", with: "DOI")
            .replacingOccurrences(of: "Isbn", with: "ISBN")
            .replacingOccurrences(of: "Issn", with: "ISSN")
            .replacingOccurrences(of: "Url", with: "URL")
    }

    private func displayValue(_ value: JSONValue) -> String {
        guard
            let data = try? ZoteroJSON.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            return value.kind
        }
        return text
    }
}
