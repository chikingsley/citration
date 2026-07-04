import SwiftUI

struct RootImportDropZone: View {
    let targeted: Bool
    let dragBorderPhase: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: targeted ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                Text("Drop Here to Import as New Items")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(targeted ? 0.22 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(targeted ? 0.95 : 0.35),
                        style: StrokeStyle(
                            lineWidth: targeted ? 2 : 1,
                            dash: [8, 5],
                            dashPhase: dragBorderPhase
                        )
                    )
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.15), value: targeted)
        }
        .background(.bar)
        .overlay(alignment: .topLeading) {
            if targeted {
                DropTargetBadge(title: "Drop to Import New Items", targeted: targeted)
                    .padding(.top, -34)
                    .padding(.leading, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }
}

struct DropTargetBadge: View {
    let title: String
    let targeted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: targeted ? "checkmark.circle.fill" : "circle")
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    Color.accentColor.opacity(targeted ? 0.95 : 0.45),
                    style: StrokeStyle(lineWidth: targeted ? 1.4 : 1)
                )
        )
        .animation(.easeInOut(duration: 0.14), value: targeted)
    }
}

struct AttachmentDropOverlay: View {
    let targeted: Bool
    let dragBorderPhase: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(0.95),
                style: StrokeStyle(lineWidth: 2.5, dash: [12, 8], dashPhase: dragBorderPhase)
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.14), value: targeted)
    }
}
