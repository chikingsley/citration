import CitrationCore
import SwiftUI

// MARK: - LibraryDataInspectorSection

struct LibraryDataInspectorSection: View {
    // MARK: Internal

    let model: AppModel
    let item: SynchronizedLibraryItem

    var body: some View {
        Group {
            if let snapshot {
                representationSection(snapshot)
                attachmentSection(snapshot)
                settingSection(snapshot)
                deletedSection(snapshot)
                unsupportedSection(snapshot)
            } else if let errorMessage {
                Section("Preserved Data") {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Preserved Data") {
                    ProgressView("Inspecting SQLite…")
                }
            }
        }
        .task(id: refreshID) {
            loadSnapshot()
        }
    }

    // MARK: Private

    @State private var snapshot: ZoteroLibraryPreservationSnapshot?
    @State private var errorMessage: String?

    private var refreshID: String {
        [
            String(model.observedLibraryID ?? 0),
            String(model.libraryObservationRevision),
            String(model.navigationObservationRevision),
            item.identity.objectKey,
        ].joined(separator: ":")
    }

    private func representationSection(_ snapshot: ZoteroLibraryPreservationSnapshot) -> some View {
        Section("Library Representation") {
            Text("A diagnostic count of the Zotero objects Citration preserves locally. These values are not ordinary item metadata.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Raw Objects", value: snapshot.objectCounts.map(\.count).reduce(0, +).formatted())
            ForEach(snapshot.objectCounts, id: \.kind) { object in
                LabeledContent(object.kind.capitalized, value: object.count.formatted())
            }
            LabeledContent("Collections", value: snapshot.collectionCount.formatted())
            LabeledContent("Distinct Tags", value: snapshot.tagCount.formatted())
            LabeledContent("Full-Text Records", value: snapshot.fullTextCount.formatted())
        }
    }

    private func attachmentSection(_ snapshot: ZoteroLibraryPreservationSnapshot) -> some View {
        Section("Attachment State") {
            ForEach(cacheStateCounts(in: snapshot), id: \.state) { value in
                LabeledContent(cacheStateLabel(value.state), value: value.count.formatted())
            }
            let selectedAttachments = snapshot.attachments.filter { $0.parentKey == item.identity.objectKey }
            if selectedAttachments.isEmpty {
                Text("No attachment objects belong to this item.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedAttachments) { attachment in
                    DiagnosticDisclosureRow(title: attachment.fileName) {
                        LabeledContent("Key", value: attachment.key)
                        LabeledContent("Cache", value: attachment.cacheState)
                        LabeledContent("Content Type", value: attachment.contentType)
                        LabeledContent("Local File", value: attachment.localPath == nil ? "Not cached" : "Present")
                        LabeledContent("Full Text", value: fullTextLabel(attachment))
                    }
                }
            }
        }
    }

    private func settingSection(_ snapshot: ZoteroLibraryPreservationSnapshot) -> some View {
        Section("Synchronized Settings") {
            Text("Library-level Zotero settings synchronized as opaque JSON so they can round-trip without data loss.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if snapshot.settings.isEmpty {
                Text("No synchronized setting objects.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.settings) { setting in
                    DiagnosticDisclosureRow(title: setting.key) {
                        LabeledContent("Version", value: setting.version.formatted())
                        Text(json(setting.value))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func deletedSection(_ snapshot: ZoteroLibraryPreservationSnapshot) -> some View {
        Section("Trash And Tombstones") {
            Text("Tombstones remember deleted object keys so deletion can synchronize correctly across devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if snapshot.deletedObjects.isEmpty {
                Text("No deleted objects are preserved.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Preserved", value: snapshot.deletedObjects.count.formatted())
                ForEach(snapshot.deletedObjects) { object in
                    Text("\(object.kind):\(object.key)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func unsupportedSection(_ snapshot: ZoteroLibraryPreservationSnapshot) -> some View {
        Section("Unsupported Raw Objects") {
            Text("Objects without a first-class Citration view remain preserved here in their original Zotero form.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if snapshot.unsupportedObjects.isEmpty {
                Text("Every current raw object has a known lossless projection.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.unsupportedObjects) { object in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(object.kind):\(object.key)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Text("\(object.type ?? "unknown type") · v\(object.version) · \(object.syncState.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func cacheStateCounts(
        in snapshot: ZoteroLibraryPreservationSnapshot
    ) -> [(state: String, count: Int)] {
        Dictionary(grouping: snapshot.attachments, by: \.cacheState)
            .map { (state: $0.key, count: $0.value.count) }
            .sorted { $0.state < $1.state }
    }

    private func fullTextLabel(_ attachment: ZoteroAttachmentStateSummary) -> String {
        guard let version = attachment.fullTextVersion else {
            return "Not synchronized"
        }
        if let indexed = attachment.indexedPages, let total = attachment.totalPages {
            return "v\(version) · \(indexed)/\(total) pages"
        }
        return "Version \(version)"
    }

    private func cacheStateLabel(_ state: String) -> String {
        state
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func json(_ value: JSONValue) -> String {
        guard
            let data = try? ZoteroJSON.encode(value),
            let string = String(data: data, encoding: .utf8)
        else {
            return "Unable to display preserved value"
        }
        return string
    }

    private func loadSnapshot() {
        guard let libraryID = model.observedLibraryID else {
            snapshot = nil
            errorMessage = "No active SQLite library."
            return
        }
        do {
            snapshot = try model.database.libraryPreservationSnapshot(libraryID: libraryID)
            errorMessage = nil
        } catch {
            snapshot = nil
            errorMessage = "Failed to inspect preserved library data."
        }
    }
}

// MARK: - DiagnosticDisclosureRow

private struct DiagnosticDisclosureRow<Content: View>: View {
    // MARK: Internal

    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .padding(.leading, 18)
            }
        }
    }

    // MARK: Private

    @State private var expanded = false
}
