import SwiftUI

// Home cards for people who turned calorie tracking off: instead of the
// calorie ring, Home leads with what they did choose (this week's groceries
// and budget, this week's workouts). Today's meals already has its own card.

/// The cart against this week's budget, with a way into Shop.
struct GrocerySummaryCard: View {
    @State private var cart = ShoppingCartService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HomeCardTitle(title: "This week's groceries", symbol: "cart.fill")
                Spacer()
                Button { NotificationCenter.default.post(name: .openShop, object: nil) } label: {
                    Text("Shop")
                        .font(.footnote).fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("home.groceries.shop")
            }

            if cart.cartItems.isEmpty {
                Text("Your cart is empty. Add what you need this week in Shop.")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.leading, HomeGrid.textInset)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("€" + String(format: "%.2f", cart.total))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("of €" + String(format: "%.0f", cart.weeklyBudget))
                            .font(.subheadline)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text("\(cart.itemCount) \(cart.itemCount == 1 ? "item" : "items")")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.labelSecondary)
                    }
                    ProgressView(value: cart.budgetFraction)
                        .tint(cart.budgetColor)
                        .accessibilityHidden(true)
                    Text(cart.budgetRemaining >= 0
                         ? "€" + String(format: "%.2f", cart.budgetRemaining) + " left in your budget"
                         : "€" + String(format: "%.2f", -cart.budgetRemaining) + " over your budget")
                        .font(.footnote)
                        .foregroundStyle(cart.budgetRemaining >= 0 ? Color.labelSecondary : Color.brandDanger)
                }
                .padding(.leading, HomeGrid.textInset)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
        .accessibilityIdentifier("home.grocerySummary")
    }
}

/// Workouts done this week (last seven days), with a way into Train.
struct WorkoutSummaryCard: View {
    @State private var store = WorkoutStore.shared

    private var thisWeek: [CompletedWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return store.completed.filter { $0.date >= start }
    }

    var body: some View {
        let week = thisWeek
        let minutes = week.reduce(0) { $0 + $1.minutes }
        let calories = week.reduce(0) { $0 + $1.calories }
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HomeCardTitle(title: "Your training", symbol: "figure.run")
                Spacer()
                Button { NotificationCenter.default.post(name: .openTrain, object: nil) } label: {
                    Text("Train")
                        .font(.footnote).fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("home.training.open")
            }

            if week.isEmpty {
                Text("No workouts in the last 7 days. Build one in Train and tick it off when you're done.")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.leading, HomeGrid.textInset)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: Spacing.lg) {
                    stat("\(week.count)", week.count == 1 ? "workout" : "workouts")
                    stat("\(minutes)", "min")
                    stat("\(calories)", "kcal")
                }
                .padding(.leading, HomeGrid.textInset)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last 7 days: \(week.count) workouts, \(minutes) minutes, about \(calories) kilocalories")
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
        .accessibilityIdentifier("home.workoutSummary")
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(Color.labelSecondary)
        }
    }
}
