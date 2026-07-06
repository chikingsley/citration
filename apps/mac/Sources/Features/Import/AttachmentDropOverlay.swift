import SwiftUI

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
