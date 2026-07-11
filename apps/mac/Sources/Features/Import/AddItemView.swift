import SwiftUI

struct AddItemView: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let onImportDocuments: () -> Void

    var body: some View {
        @Bindable var importer = model.importer

        VStack(alignment: .leading, spacing: 18) {
            Text("Add to Library")
                .font(.title2.bold())

            Form {
                Section("Resolve an Identifier") {
                    Picker("Identifier", selection: $importer.identifierKind) {
                        ForEach(AddIdentifierKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.importer.isResolvingIdentifier)

                    TextField(
                        model.importer.identifierKind.title,
                        text: $importer.identifierInput,
                        prompt: Text(model.importer.identifierKind.prompt)
                    )
                    .onSubmit(resolveIdentifier)

                    HStack {
                        Spacer()
                        Button(
                            model.importer.isResolvingIdentifier ? "Resolving…" : "Add Item",
                            action: resolveIdentifier
                        )
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            model.importer.isResolvingIdentifier
                                || model.importer.identifierInput.bcTrimmedNonEmpty == nil
                        )
                    }
                }

                Section("Other Ways to Add") {
                    Button("Import Documents…", systemImage: "doc.badge.plus") {
                        onImportDocuments()
                    }
                    Button("Add Empty Item", systemImage: "doc") {
                        model.addEmptyItem()
                        dismiss()
                    }
                    Button("New Collection", systemImage: "folder.badge.plus") {
                        model.collections.create()
                        dismiss()
                    }
                    Button("New Note", systemImage: "note.text.badge.plus") {
                        model.notes.prepareNewNote()
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(width: 480, height: 360)
        .onChange(of: model.importer.identifierInput) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.isEmpty, !model.importer.isResolvingIdentifier {
                dismiss()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func resolveIdentifier() {
        model.importer.addByIdentifier()
    }
}
