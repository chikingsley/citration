import CitrationCore
import SwiftUI

// MARK: - ItemInfoInspectorSection

struct ItemInfoInspectorSection: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let item: SynchronizedLibraryItem

    var body: some View {
        Section("Info") {
            if model.itemTypeDefinitions.isEmpty {
                LabeledContent("Item Type", value: fieldLabel(item.projected.itemType))
            } else {
                Picker("Item Type", selection: $draftItemType) {
                    ForEach(model.itemTypeDefinitions, id: \.itemType) { definition in
                        Text(definition.localized).tag(definition.itemType)
                    }
                }
                Button("Convert Item Type", systemImage: "arrow.triangle.2.circlepath") {
                    convertItemType()
                }
                .disabled(draftItemType == item.projected.itemType || isConverting)
            }
            LabeledContent("Zotero Key") {
                Text(item.identity.objectKey).textSelection(.enabled)
            }
        }
        .task(id: item.identity) {
            resetDrafts(from: item)
            draftItemType = item.projected.itemType
            isEditingCreators = false
            isEditingFields = false
            showAllFields = false
            _ = await model.loadItemEditingSchema(for: item.projected.itemType)
        }

        Section("Creators") {
            if isEditingCreators {
                ForEach(creatorDrafts) { creator in
                    creatorEditor(creator)
                }
                Button("Add Creator", systemImage: "plus") {
                    addCreator()
                }
                HStack {
                    Button("Cancel") {
                        cancelCreatorEditing()
                    }
                    Spacer()
                    Button(isSavingCreators ? "Saving…" : "Save") {
                        saveCreators()
                    }
                    .disabled(!hasCreatorChanges || isSavingCreators)
                }
            } else {
                if creatorDrafts.isEmpty {
                    Text("No creators")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(creatorDrafts) { creator in
                        LabeledContent(creatorRoleLabel(creator)) {
                            Text(creatorDisplayName(creator))
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
                Button(creatorDrafts.isEmpty ? "Add Creator" : "Edit Creators", systemImage: "pencil") {
                    isEditingCreators = true
                    if creatorDrafts.isEmpty {
                        addCreator()
                    }
                }
            }
        }

        Section("Fields") {
            if isEditingFields {
                Toggle("Show All Fields", isOn: $showAllFields)
                ForEach(visibleEditableStringFields, id: \.self) { field in
                    LabeledContent(fieldLabel(field)) {
                        TextField(
                            fieldLabel(field),
                            text: binding(for: field),
                            axis: field == "abstractNote" ? .vertical : .horizontal
                        )
                        .labelsHidden()
                        .lineLimit(field == "abstractNote" ? 3 ... 8 : 1 ... 2)
                    }
                }
                HStack {
                    Button("Cancel") {
                        cancelFieldEditing()
                    }
                    Spacer()
                    Button(isSaving ? "Saving…" : "Save") {
                        saveChanges()
                    }
                    .disabled(!hasChanges || isSaving)
                }
            } else {
                if populatedEditableStringFields.isEmpty {
                    Text("No populated fields")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(populatedEditableStringFields, id: \.self) { field in
                        LabeledContent(fieldLabel(field)) {
                            Text(item.projected.fields[field]?.stringValue ?? "")
                                .multilineTextAlignment(.trailing)
                                .lineLimit(field == "abstractNote" ? 6 : 2)
                                .textSelection(.enabled)
                        }
                    }
                }
                Button("Edit Fields", systemImage: "pencil") {
                    isEditingFields = true
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
    @State private var draftItemType = ""
    @State private var isConverting = false
    @State private var creatorDrafts: [CreatorDraft] = []
    @State private var isSavingCreators = false
    @State private var isEditingCreators = false
    @State private var isEditingFields = false
    @State private var showAllFields = false

    private var editingSchema: ZoteroItemEditingSchema? {
        model.itemEditingSchemas[item.projected.itemType]
    }

    private var creatorTypeDefinitions: [ZoteroCreatorTypeDefinition] {
        if let editingSchema {
            return editingSchema.creatorTypes
        }
        var seen = Set<String>()
        return item.projected.creators.compactMap { creator in
            guard seen.insert(creator.creatorType).inserted else {
                return nil
            }
            return ZoteroCreatorTypeDefinition(
                creatorType: creator.creatorType,
                localized: fieldLabel(creator.creatorType)
            )
        }
    }

    private var editableStringFields: [String] {
        let schemaFields = editingSchema?.fields.map(\.field) ?? []
        let existingStringFields = item.projected.fields.compactMap { field, value in
            value.stringValue == nil ? nil : field
        }
        return Set(schemaFields + existingStringFields)
            .filter { field in
                !Self.readOnlyFields.contains(field) && !Self.hiddenStructuralFields.contains(field)
            }
            .sorted(by: compareFields)
    }

    private var populatedEditableStringFields: [String] {
        editableStringFields.filter { field in
            item.projected.fields[field]?.stringValue?.bcTrimmedNonEmpty != nil
        }
    }

    private var visibleEditableStringFields: [String] {
        showAllFields ? editableStringFields : populatedEditableStringFields
    }

    private var hasChanges: Bool {
        editableStringFields.contains { field in
            drafts[field] != item.projected.fields[field]?.stringValue
        }
    }

    private var originalCreatorData: [[String: JSONValue]] {
        item.projected.fields["creators"]?.arrayValue?.compactMap(\.objectValue) ?? []
    }

    private var hasCreatorChanges: Bool {
        creatorDrafts.map(\.data) != originalCreatorData
    }
}

private extension ItemInfoInspectorSection {
    private func creatorEditor(_ creator: CreatorDraft) -> some View {
        HStack(spacing: 6) {
            Picker("Role", selection: creatorTypeBinding(for: creator.id)) {
                ForEach(creatorTypeDefinitions, id: \.creatorType) { definition in
                    Text(definition.localized).tag(definition.creatorType)
                }
            }
            .labelsHidden()
            .frame(width: 88)

            if creator.data["name"] != nil {
                TextField("Name", text: creatorFieldBinding(for: creator.id, field: "name"))
            } else {
                TextField("Last", text: creatorFieldBinding(for: creator.id, field: "lastName"))
                TextField("First", text: creatorFieldBinding(for: creator.id, field: "firstName"))
            }

            Menu {
                Button(creator.data["name"] == nil ? "Use Single Name Field" : "Use First and Last Name") {
                    toggleCreatorLiteralMode(id: creator.id)
                }
                Divider()
                Button("Remove Creator", systemImage: "trash", role: .destructive) {
                    creatorDrafts.removeAll { $0.id == creator.id }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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
        creatorDrafts = (item.projected.fields["creators"]?.arrayValue ?? []).compactMap { value in
            value.objectValue.map(CreatorDraft.init(data:))
        }
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
                isEditingFields = false
            } catch {
                model.statusMessage = "Failed to update item"
            }
        }
    }

    private func convertItemType() {
        let target = draftItemType
        isConverting = true
        Task {
            defer { isConverting = false }
            do {
                let converted = try await model.convertItemType(identity: item.identity, to: target)
                draftItemType = converted.projected.itemType
                resetDrafts(from: converted)
            } catch {
                draftItemType = item.projected.itemType
                model.statusMessage = "Failed to change item type"
            }
        }
    }

    private func addCreator() {
        let creatorType = editingSchema?.primaryCreatorType ?? "author"
        creatorDrafts.append(CreatorDraft(data: [
            "creatorType": .string(creatorType),
            "firstName": .string(""),
            "lastName": .string(""),
        ]))
    }

    private func saveCreators() {
        isSavingCreators = true
        Task {
            defer { isSavingCreators = false }
            do {
                let updated = try await model.updateCreators(
                    identity: item.identity,
                    creators: creatorDrafts.map(\.data)
                )
                resetDrafts(from: updated)
                isEditingCreators = false
            } catch {
                model.statusMessage = "Failed to update creators"
            }
        }
    }

    private func creatorTypeBinding(for id: UUID) -> Binding<String> {
        creatorFieldBinding(for: id, field: "creatorType")
    }

    private func creatorDisplayName(_ creator: CreatorDraft) -> String {
        if let literal = creator.data["name"]?.stringValue?.bcTrimmedNonEmpty {
            return literal
        }
        let components = [
            creator.data["firstName"]?.stringValue?.bcTrimmedNonEmpty,
            creator.data["lastName"]?.stringValue?.bcTrimmedNonEmpty,
        ].compactMap(\.self)
        return components.isEmpty ? "Unnamed Creator" : components.joined(separator: " ")
    }

    private func creatorRoleLabel(_ creator: CreatorDraft) -> String {
        let type = creator.data["creatorType"]?.stringValue ?? "creator"
        return creatorTypeDefinitions.first(where: { $0.creatorType == type })?.localized ?? fieldLabel(type)
    }

    private func cancelCreatorEditing() {
        resetDrafts(from: item)
        isEditingCreators = false
    }

    private func cancelFieldEditing() {
        resetDrafts(from: item)
        showAllFields = false
        isEditingFields = false
    }

    private func toggleCreatorLiteralMode(id: UUID) {
        let binding = creatorLiteralModeBinding(for: id)
        binding.wrappedValue.toggle()
    }

    private func creatorLiteralModeBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                creatorDrafts.first(where: { $0.id == id })?.data["name"] != nil
            },
            set: { useLiteralName in
                guard let index = creatorDrafts.firstIndex(where: { $0.id == id }) else {
                    return
                }
                var data = creatorDrafts[index].data
                if useLiteralName {
                    let name = [data["firstName"]?.stringValue, data["lastName"]?.stringValue]
                        .compactMap { $0?.bcTrimmedNonEmpty }
                        .joined(separator: " ")
                    data["firstName"] = nil
                    data["lastName"] = nil
                    data["name"] = .string(name)
                } else {
                    let name = data["name"]?.stringValue ?? ""
                    data["name"] = nil
                    data["firstName"] = .string("")
                    data["lastName"] = .string(name)
                }
                creatorDrafts[index].data = data
            }
        )
    }

    private func creatorFieldBinding(for id: UUID, field: String) -> Binding<String> {
        Binding(
            get: {
                creatorDrafts.first(where: { $0.id == id })?.data[field]?.stringValue ?? ""
            },
            set: { value in
                guard let index = creatorDrafts.firstIndex(where: { $0.id == id }) else {
                    return
                }
                creatorDrafts[index].data[field] = .string(value)
            }
        )
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

    private func fieldLabel(_ field: String) -> String {
        if let localized = editingSchema?.fields.first(where: { $0.field == field })?.localized {
            return localized
        }
        return field
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .replacingOccurrences(of: "Doi", with: "DOI")
            .replacingOccurrences(of: "Isbn", with: "ISBN")
            .replacingOccurrences(of: "Issn", with: "ISSN")
            .replacingOccurrences(of: "Url", with: "URL")
    }
}

// MARK: - CreatorDraft

private struct CreatorDraft: Identifiable {
    let id: UUID = .init()
    var data: [String: JSONValue]
}
