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
