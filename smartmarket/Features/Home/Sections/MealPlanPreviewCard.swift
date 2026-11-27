import SwiftUI

/// Compact preview of today's generated meals, linking to the full plan.
struct MealPlanPreviewCard: View {
    let vm: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(title: "Today's meals", subtitle: subtitle, symbol: "fork.knife", section: .meals)

            // `vm.isLoading` follows the deals, so a plan that exists is always shown.
            if let plan = vm.mealPlan {
                ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { idx, meal in
                    MealPreviewRow(
                        icon: meal.sfSymbol,
                        title: meal.title,
                        calories: meal.entries.reduce(0) { $0 + $1.calories },
                        accent: Self.mealAccent(idx)
                    )
                    if idx < plan.allMeals.count - 1 {
                        Divider().padding(.leading, HomeGrid.textInset)
                    }
                }
            } else if vm.isLoading {
                VStack(spacing: Spacing.md) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(Color(.systemFill))
                            .frame(height: 40)
                    }
                }
                .shimmer(active: !reduceMotion)
                .accessibilityHidden(true)
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    Text("Your plan builds itself from your cart and My Stock. Open Meals to see it.")
                        .font(.subheadline).foregroundStyle(Color.labelSecondary)
                }
                .padding(.vertical, Spacing.sm)
            }

            HomeSectionButton(title: "Open plan", symbol: "calendar", section: .meals) {
                AppRouter.shared.open(.meals)
            }
            .accessibilityIdentifier("home.meals.open")
        }
        .homeSectionCard(.meals)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.mealsSection")
    }

    private var subtitle: String? {
        guard let plan = vm.mealPlan else { return nil }
        let kcal = plan.allMeals.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.calories } }
        return "\(plan.allMeals.count) meals · \(kcal) kcal planned"
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
        HStack(spacing: HomeGrid.gap) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: HomeGrid.icon, height: HomeGrid.icon)
                .background(HomeSection.meals.color.opacity(0.35), in: Circle())

            Text(title).font(.subheadline).fontWeight(.semibold).lineLimit(1)
            Spacer()
            Text("\(calories) kcal" as String)
                .font(.footnote).fontWeight(.semibold)
                .foregroundStyle(Color.labelSecondary).monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(calories) kilocalories" as String)
    }
}
