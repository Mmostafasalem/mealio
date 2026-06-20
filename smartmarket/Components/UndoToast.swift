import SwiftUI

/// Slide-up banner with an Undo action — use for destructive mutations.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
                .foregroundStyle(Color.brandAmber)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 4)
        .padding(.horizontal, 16)
    }
}
