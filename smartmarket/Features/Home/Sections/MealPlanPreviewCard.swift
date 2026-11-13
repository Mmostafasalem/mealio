import SwiftUI

/// Compact preview of today's generated meals, linking to the full plan.
struct MealPlanPreviewCard: View {
    let vm: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Today's Meals", systemImage: "fork.knife.circle.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                NavigationLink { MealPlanView() } label: {
                    Text("Full Plan")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .accessibilityAddTraits(.isHeader)

            if vm.isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(Color(.systemFill))
                        .frame(height: 40)
                        .shimmer(active: !reduceMotion)
                }
            } else if let plan = vm.mealPlan {
                ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { idx, meal in
                    MealPreviewRow(
                        icon: meal.sfSymbol,
                        title: meal.title,
                        calories: meal.entries.reduce(0) { $0 + $1.calories },
                        accent: Self.mealAccent(idx)
                    )
                    if idx < plan.allMeals.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    Text("Pull to refresh and generate today's plan")
                        .font(.subheadline).foregroundStyle(Color.labelSecondary)
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
    }

    static func mealAccent(_ idx: Int) -> Color {
        Color.labelPrimary
    }
}

/// One meal row in the plan preview.
struct MealPreviewRow: View {
    let icon: String
    let title: String
    let calories: Int
    let accent: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12), in: Circle())

            Text(title).font(.subheadline).fontWeight(.medium).lineLimit(1)
            Spacer()
            Text("\(calories) kcal")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(Color.labelSecondary).monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(calories) kilocalories")
    }
}
