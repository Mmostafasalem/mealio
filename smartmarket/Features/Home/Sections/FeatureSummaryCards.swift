import SwiftUI
import Charts

// Home's grocery and training sections. Each has its own colour and icon
// (`HomeSection`), one small chart and a call-to-action button.

/// The cart against this week's budget, with Shop and My Stock.
struct GrocerySummaryCard: View {
    @State private var cart = ShoppingCartService.shared
    /// My Stock sits here (where food comes in), not in a row of look-alike buttons.
    var showsStock = true

    private var subtitle: String {
        cart.cartItems.isEmpty ? "Your cart is empty"
            : "\(cart.itemCount) \(cart.itemCount == 1 ? "item" : "items") in your cart"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(title: "This week's groceries", subtitle: subtitle, symbol: "cart.fill", section: .groceries)

            if cart.cartItems.isEmpty {
                Text("Add what you need this week in Shop. Your budget is " + Money.formatWhole(eur: cart.weeklyBudget) + ".")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Money.format(eur: cart.total))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("of " + Money.formatWhole(eur: cart.weeklyBudget) + " budget")
                            .font(.subheadline)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    BudgetBar(fraction: cart.budgetFraction, over: cart.budgetRemaining < 0)
                    Text(cart.budgetRemaining >= 0
                         ? Money.format(eur: cart.budgetRemaining) + " left in your budget"
                         : Money.format(eur: -cart.budgetRemaining) + " over your budget")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(cart.budgetRemaining >= 0 ? Color.labelSecondary : Color.brandDanger)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: Spacing.md) {
                HomeSectionButton(title: "Shop", symbol: "basket.fill", section: .groceries) {
                    NotificationCenter.default.post(name: .openShop, object: nil)
                }
                .accessibilityIdentifier("home.groceries.shop")
                if showsStock {
                    NavigationLink { StockView() } label: {
                        HomeSectionButtonLabel(title: "My Stock", symbol: "cabinet.fill", section: .groceries, prominent: false)
                    }
                    .buttonStyle(ScalePressStyle())
                    .accessibilityHint("Food you have at home")
                    .accessibilityIdentifier("home.stock")
                }
            }
        }
        .homeSectionCard(.groceries)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.grocerySummary")
    }
}

/// Spent against the budget: a filled bar in the section's colour, red when over.
private struct BudgetBar: View {
    let fraction: Double
    let over: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surface.opacity(0.9))
                Capsule()
                    .fill(over ? Color.brandDanger : HomeSection.groceries.color)
                    .frame(width: max(10, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 12)
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// Workouts in the last seven days, as minutes per day, with a way into Train.
struct WorkoutSummaryCard: View {
    @State private var store = WorkoutStore.shared

    private var days: [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let minutes = store.completed.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
            return (day, minutes)
        }
    }

    private var thisWeek: [CompletedWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return store.completed.filter { $0.date >= start }
    }

    var body: some View {
        let week = thisWeek
        let minutes = week.reduce(0) { $0 + $1.minutes }
        let calories = week.reduce(0) { $0 + $1.calories }
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(title: "Your training",
                              subtitle: week.isEmpty ? "No workouts in the last 7 days"
                                  : "\(week.count) \(week.count == 1 ? "workout" : "workouts") · \(minutes) min · \(calories) kcal",
                              symbol: "figure.run", section: .training)
                .accessibilityIdentifier("home.training.header")

            if !week.isEmpty {
                Chart {
                    ForEach(days, id: \.date) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.minutes))
                            .foregroundStyle(HomeSection.training.color)
                            .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last 7 days: \(week.count) workouts, \(minutes) minutes, about \(calories) kilocalories")
            }

            HomeSectionButton(title: "Start workout", symbol: "play.fill", section: .training) {
                NotificationCenter.default.post(name: .openTrain, object: nil)
            }
            .accessibilityIdentifier("home.training.open")
        }
        .homeSectionCard(.training)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.workoutSummary")
    }
}
