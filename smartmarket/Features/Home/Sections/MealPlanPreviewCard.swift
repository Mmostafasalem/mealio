import SwiftUI

/// Compact preview of today's generated meals, linking to the full plan.
struct MealPlanPreviewCard: View {
    let vm: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HomeCardTitle(title: "Today's meals", symbol: "fork.knife.circle.fill")
                Spacer()
                NavigationLink { MealPlanView() } label: {
                    Text("Full plan")
                        .font(.footnote).fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }

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
        HStack(spacing: HomeGrid.gap) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: HomeGrid.icon, height: HomeGrid.icon)
                .background(accent.opacity(0.12), in: Circle())

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
