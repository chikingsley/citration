import CitrationCore
import SwiftUI

// MARK: - WorkspaceTabBar

struct WorkspaceTabBar: View {
    // MARK: Internal

    @Bindable var model: AppModel

    let onDetach: (LocalAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                libraryTab
                ForEach(model.documentSessions) { session in
                    documentTab(session.attachment)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(.bar)
        .accessibilityLabel("Document tabs")
    }

    // MARK: Private

    private var libraryTab: some View {
        Button {
            model.selectWorkspaceTab(.library)
        } label: {
            Label("Library", systemImage: "books.vertical")
                .frame(minWidth: 92)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(.rect)
        }
        .buttonStyle(WorkspaceTabButtonStyle(isSelected: model.selectedWorkspaceTab == .library))
        .accessibilityLabel("Library tab")
        .accessibilityAddTraits(model.selectedWorkspaceTab == .library ? .isSelected : [])
    }

    private func documentTab(_ attachment: LocalAttachment) -> some View {
        HStack(spacing: 6) {
            Button {
                model.selectWorkspaceTab(.document(attachment.objectKey))
            } label: {
                Label(attachment.fileName, systemImage: iconName(for: attachment.documentFormat))
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(attachment.fileName)
            .accessibilityAddTraits(
                model.selectedWorkspaceTab == .document(attachment.objectKey) ? .isSelected : []
            )

            Button {
                model.closeDocument(attachmentKey: attachment.objectKey)
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(attachment.fileName)")
            .help("Close \(attachment.fileName)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 150)
        .background(
            model.selectedWorkspaceTab == .document(attachment.objectKey)
                ? Color.accentColor.opacity(0.14)
                : Color.clear
        )
        .contentShape(.rect)
        .contextMenu {
            Button("Move to New Window", systemImage: "macwindow.badge.plus") {
                onDetach(attachment)
            }
            Button("Close", systemImage: "xmark") {
                model.closeDocument(attachmentKey: attachment.objectKey)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document tab, \(attachment.fileName)")
    }

    private func iconName(for format: DocumentFormat) -> String {
        switch format {
        case .pdf:
            "doc.richtext"
        case .epub:
            "book"
        case .html:
            "safari"
        case .plainText:
            "doc.plaintext"
        case .image:
            "photo"
        case .audio:
            "waveform"
        case .unknown:
            "doc"
        }
    }
}

// MARK: - WorkspaceTabButtonStyle

private struct WorkspaceTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
