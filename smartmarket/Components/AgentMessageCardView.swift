import SwiftUI

/// Meal notes retain their actual source; missing content is not a typing state.
struct AgentMessageCardView: View {
    let message: String?
    let isLoading: Bool
    var sourceLabel: String = "Meal suggestions"

    private var hasMessage: Bool {
        !(message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(sourceLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brandDark)

            if isLoading {
                Label("Preparing meal suggestions…", systemImage: "hourglass")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
            } else if hasMessage {
                Text(message ?? "")
                    .font(.subheadline).foregroundStyle(Color.labelPrimary)
            } else {
                Text("No meal notes yet. You can log food now or open Meals to review suggestions.")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.tile))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 16) {
        AgentMessageCardView(message: "Review the ingredients and portions before logging a meal.", isLoading: false)
        AgentMessageCardView(message: nil, isLoading: true)
        AgentMessageCardView(message: nil, isLoading: false)
    }
    .padding()
}
