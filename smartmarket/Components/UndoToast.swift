import SwiftUI

/// Slide-up banner with an Undo action — use for destructive mutations.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        // An inverse surface: dark on light, light on dark, so it never melts into the page.
        HStack(spacing: Spacing.md) {
            Image(systemName: "trash.fill")
                .font(.caption)
                .foregroundStyle(Color.surfaceGrouped.opacity(0.75))
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.surfaceGrouped)
            Spacer()
            Button(action: onUndo) {
                Text("Undo").font(.subheadline.bold())
                    .underline()
                    .foregroundStyle(Color.surfaceGrouped)
                    .minTapTarget()
                    .contentShape(Rectangle())
            }
                .accessibilityIdentifier("undoToast.undo")
                .accessibilityLabel("Undo: \(message)")
                .buttonStyle(ScalePressStyle())
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.labelPrimary, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .elevation(Elevation.high)
        .padding(.horizontal, Spacing.lg)
    }
}
