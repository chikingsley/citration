import SwiftUI
import CitrationCore

private struct TagSummary: Identifiable {
    let tag: String
    let count: Int

    var id: String { tag.lowercased() }
}

struct TagFilterPanel: View {
    let items: [BCItem]
    @Binding var selectedTag: String?

    private var tagSummaries: [TagSummary] {
        Dictionary(grouping: items.flatMap(\.tags)) { tag in
            tag.lowercased()
        }
        .values
        .compactMap { tags in
            guard let displayTag = tags.first else { return nil }
            return TagSummary(tag: displayTag, count: tags.count)
        }
        .sorted { lhs, rhs in
            lhs.tag.localizedCaseInsensitiveCompare(rhs.tag) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if tagSummaries.isEmpty {
                Text("No tags to display")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                tagList
            }
            Divider()
            footer
        }
    }

    private var tagList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                Button {
                    selectedTag = nil
                } label: {
                    tagFilterRow(
                        title: "All Tags",
                        count: items.count,
                        isSelected: selectedTag == nil,
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                .buttonStyle(.plain)

                ForEach(tagSummaries) { summary in
                    Button {
                        selectedTag = summary.tag
                    } label: {
                        tagFilterRow(
                            title: summary.tag,
                            count: summary.count,
                            isSelected: selectedTag == summary.tag,
                            systemImage: "tag"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(minHeight: 72, maxHeight: 160)
    }

    private var footer: some View {
        HStack {
            Text(selectedTag ?? "Filter Tags")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if selectedTag != nil {
                Button {
                    selectedTag = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Clear tag filter")
            }
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func tagFilterRow(
        title: String,
        count: Int,
        isSelected: Bool,
        systemImage: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isSelected ? "\(systemImage).fill" : systemImage)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
            Spacer()
            Text(count.formatted())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
