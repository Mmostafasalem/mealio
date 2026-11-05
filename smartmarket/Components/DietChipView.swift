import SwiftUI

/// Toggleable pill chip for dietary preference selection.
struct DietChipView: View {

    let preference: DietaryPreference
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            onTap()
        }) {
            HStack(spacing: 5) {
                Image(systemName: preference.sfSymbol)
                    .font(.system(size: 12, weight: .medium))
                Text(preference.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(isSelected ? Color.coral : Color.surfaceSecondary)
            .foregroundStyle(isSelected ? Color.onAccent : Color.labelPrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color(.separator),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isSelected)
    }
}

#Preview {
    HStack {
        DietChipView(preference: .vegan, isSelected: true, onTap: {})
        DietChipView(preference: .glutenFree, isSelected: false, onTap: {})
    }
    .padding()
}
