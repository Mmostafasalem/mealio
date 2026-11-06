import SwiftUI

/// Slide-up banner with an Undo action — use for destructive mutations.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "trash.fill")
                .font(.caption)
                .foregroundStyle(Color.almond.opacity(0.7))
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.almond)
            Spacer()
            Button(action: onUndo) {
                Text("Undo").font(.subheadline.bold())
                    .foregroundStyle(Color.dullPink)
                    .minTapTarget()
                    .contentShape(Rectangle())
            }
                .accessibilityIdentifier("undoToast.undo")
                .accessibilityLabel("Undo: \(message)")
                .font(.subheadline.bold())
                .foregroundStyle(Color.dullPink)
                .buttonStyle(ScalePressStyle())
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.rhino, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .elevation(Elevation.high)
        .padding(.horizontal, Spacing.lg)
    }
}
