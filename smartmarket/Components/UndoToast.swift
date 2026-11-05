import SwiftUI

/// Slide-up banner with an Undo action — use for destructive mutations.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "trash.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
                .foregroundStyle(Color.coral)
                .minTapTarget()
                .buttonStyle(ScalePressStyle())
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .elevation(Elevation.high)
        .padding(.horizontal, Spacing.lg)
    }
}
