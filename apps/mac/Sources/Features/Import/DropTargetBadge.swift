import SwiftUI

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
