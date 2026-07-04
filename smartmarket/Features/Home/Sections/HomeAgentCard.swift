import SwiftUI

/// AI assistant summary card with an "Ask Agent" entry point.
struct HomeAgentCard: View {
    let vm: HomeViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    LinearGradient(colors: [Color.brandPrimary, Color.brandDark],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(Circle())
                        .frame(width: 36, height: 36)
                    Text("SM").font(.caption).fontWeight(.bold).foregroundStyle(.white)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mealio Agent").font(.subheadline).fontWeight(.semibold)
                    Text("AI-powered meal & deal assistant")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if appState.isGeneratingMealPlan {
                    HStack(spacing: Spacing.xs) {
                        ProgressView().scaleEffect(0.7).tint(Color.brandPrimary)
                        Text("Thinking…").font(.caption2).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }

            AgentMessageCardView(
                message: vm.mealPlan?.agentNotes,
                isLoading: vm.isLoading || appState.isGeneratingMealPlan
            )

            Button { vm.showAgentChat = true } label: {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Ask Agent").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).fontWeight(.semibold).opacity(0.7)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(colors: [Color.brandPrimary, Color.brandDark],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                )
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityLabel("Ask the Mealio agent")
        }
        .padding(Spacing.lg)
        .premiumCard()
        .animation(.snappyValue, value: appState.isGeneratingMealPlan)
    }
}
