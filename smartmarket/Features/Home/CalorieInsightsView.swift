import SwiftUI
import Charts

// MARK: - Calorie insights
//
// TestFlight B7: "I cannot find where to see my calories insights history."
// Reached from Home (the calorie card's Insights button and its week chart):
// daily calories against the target over 7 or 30 days, days on target, the
// logging streak, average macros, and day by day; all logged food from there.

/// Numbers for the insights page, from the food log. Pure, so it is unit tested.
struct CalorieInsights: Equatable {
    struct Day: Identifiable, Equatable {
        let date: Date
        var kcal: Int = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var id: Date { date }
        var logged: Bool { kcal > 0 }
    }

    /// One per calendar day, oldest first, ending today.
    let days: [Day]
    let target: Int
    /// Consecutive days with food logged, up to today (or yesterday while today is still empty).
    let streak: Int

    /// "On target": within 10% of the daily goal either way.
    static let tolerance = 0.1

    init(entries: [FoodLogEntry], target: Int, days count: Int, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: Day] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.loggedAt)
            var value = byDay[day] ?? Day(date: day)
            value.kcal += entry.calories
            value.protein += entry.proteinG
            value.carbs += entry.carbsG
            value.fat += entry.fatG
            byDay[day] = value
        }
        days = (0..<max(count, 1)).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { byDay[$0] ?? Day(date: $0) }
        }
        self.target = max(target, 1)
        var streak = 0
        var day = today
        if (byDay[day]?.kcal ?? 0) == 0, let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        while (byDay[day]?.kcal ?? 0) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        self.streak = streak
    }

    var loggedDays: [Day] { days.filter(\.logged) }

    private func average(_ value: (Day) -> Double) -> Double? {
        let logged = loggedDays
        return logged.isEmpty ? nil : logged.map(value).reduce(0, +) / Double(logged.count)
    }

    var averageKcal: Int? { average { Double($0.kcal) }.map { Int($0.rounded()) } }
    var averageProtein: Double? { average(\.protein) }
    var averageCarbs: Double? { average(\.carbs) }
    var averageFat: Double? { average(\.fat) }

    func isOnTarget(_ day: Day) -> Bool {
        day.logged && abs(Double(day.kcal - target)) <= Double(target) * Self.tolerance
    }

    var daysOnTarget: Int { days.filter(isOnTarget).count }
}

struct CalorieInsightsView: View {
    @State private var log = FoodLogStore.shared
    @State private var range: CalorieTrendRange = .week
    private let now = Date()

    private var target: Int { max(AppState.shared.userProfile.dailyCalorieGoal, 1) }
    private var macroTargets: (protein: Double, carbs: Double, fat: Double) {
        let isKeto = Set<DietaryPreference>.load().contains(.keto)
        let t = BMRCalculator.macroTargets(calories: target, isKeto: isKeto)
        return (Double(t.proteinG), Double(t.carbsG), Double(t.fatG))
    }

    var body: some View {
        let insights = CalorieInsights(entries: log.allEntries, target: target, days: range.days, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Picker("Range", selection: $range) {
                    ForEach(CalorieTrendRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("insights.range")

                summary(insights)
                chartCard(insights)
                macrosCard(insights)
                dayByDay(insights)

                NavigationLink { FoodHistoryView() } label: {
                    HStack {
                        Label("All logged food", systemImage: "list.bullet.rectangle")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .foregroundStyle(Color.labelPrimary)
                    .padding(Spacing.lg)
                    .frame(minHeight: 44)
                    .premiumCard()
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityIdentifier("insights.allFood")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Calorie insights")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarHidden(false)
        .accessibilityIdentifier("insights.screen")
    }

    // MARK: Summary tiles

    private func summary(_ insights: CalorieInsights) -> some View {
        let logged = insights.loggedDays.count
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) { tiles(insights, logged: logged) }
            VStack(spacing: Spacing.md) { tiles(insights, logged: logged) }
        }
    }

    @ViewBuilder private func tiles(_ insights: CalorieInsights, logged: Int) -> some View {
        tile(symbol: "chart.bar.fill", label: "Daily average",
             value: insights.averageKcal.map { "\($0)" } ?? "–", unit: "kcal",
             spoken: insights.averageKcal.map { "Daily average \($0) kilocalories, target \(insights.target)" } ?? "No days logged yet")
        tile(symbol: "target", label: "On target",
             value: "\(insights.daysOnTarget)", unit: "of \(logged) logged \(logged == 1 ? "day" : "days")",
             spoken: "\(insights.daysOnTarget) of \(logged) logged days within 10 percent of your target")
            .accessibilityIdentifier("insights.onTarget")
        tile(symbol: "flame.fill", label: "Streak",
             value: "\(insights.streak)", unit: insights.streak == 1 ? "day" : "days",
             spoken: "Logging streak: \(insights.streak) \(insights.streak == 1 ? "day" : "days") in a row")
            .accessibilityIdentifier("insights.streak")
    }

    private func tile(symbol: String, label: String, value: String, unit: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.onAccent)
                .frame(width: 28, height: 28)
                .background(Color.progress, in: Circle())
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Color.labelSecondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.labelPrimary)
            Text(unit).font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .premiumCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Chart

    private func chartCard(_ insights: CalorieInsights) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeCardTitle(title: "Calories vs target", symbol: "chart.bar.xaxis")
            HStack(spacing: Spacing.md) {
                legend(color: .progress, text: "On or under")
                legend(color: .brandDanger, text: "Over by 10%+")
                legend(color: .labelSecondary, text: "Target", dashed: true)
            }
            Chart {
                ForEach(insights.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day),
                            y: .value("Calories", day.kcal))
                        .foregroundStyle(Double(day.kcal) > Double(insights.target) * (1 + CalorieInsights.tolerance)
                                         ? Color.brandDanger : Color.progress)
                        .cornerRadius(range == .week ? 6 : 2)
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .accessibilityValue(day.logged ? "\(day.kcal) kilocalories" : "Nothing logged")
                }
                RuleMark(y: .value("Target", insights.target))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Color.labelSecondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target \(insights.target)" as String)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .accessibilityLabel("Daily target")
                    .accessibilityValue("\(insights.target) kilocalories")
            }
            .chartXAxis {
                if range == .week {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
            }
            .chartYScale(domain: 0...max(Double(insights.target) * 1.3, Double(insights.days.map(\.kcal).max() ?? 0) * 1.1))
            .frame(height: 220)
            .accessibilityIdentifier("insights.chart")
            if insights.loggedDays.isEmpty {
                Text("Nothing logged in the last \(range.title). Log food and your days fill in here.")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .premiumCard(surface: .hero)
    }

    private func legend(color: Color, text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dashed {
                Rectangle().fill(color).frame(width: 12, height: 2)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            }
            Text(text).font(.caption2).foregroundStyle(Color.labelSecondary).lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    // MARK: Macros

    private func macrosCard(_ insights: CalorieInsights) -> some View {
        let goals = macroTargets
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HomeCardTitle(title: "Average macros", symbol: "chart.pie.fill")
            Text("Per logged day, against your daily targets.")
                .font(.footnote).foregroundStyle(Color.labelSecondary)
            macroRow("Protein", value: insights.averageProtein, goal: goals.protein, color: .ringProtein)
            macroRow("Carbs", value: insights.averageCarbs, goal: goals.carbs, color: .ringCarbs)
            macroRow("Fat", value: insights.averageFat, goal: goals.fat, color: .ringFat)
        }
        .padding(Spacing.lg)
        .premiumCard()
        .accessibilityIdentifier("insights.macros")
    }

    private func macroRow(_ name: String, value: Double?, goal: Double, color: Color) -> some View {
        let grams = value.map { Int($0.rounded()) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(grams.map(String.init) ?? "–") / \(Int(goal.rounded())) g" as String)
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Color.labelSecondary)
            }
            ProgressView(value: min((value ?? 0) / max(goal, 1), 1))
                .tint(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): average \(grams.map { "\($0) grams" } ?? "not logged") of \(Int(goal.rounded())) grams")
    }

    // MARK: Day by day

    @ViewBuilder private func dayByDay(_ insights: CalorieInsights) -> some View {
        let logged = insights.loggedDays.reversed()
        if !logged.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HomeCardTitle(title: "Day by day", symbol: "calendar")
                ForEach(Array(logged)) { day in
                    HStack(spacing: Spacing.md) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.subheadline)
                            .frame(minWidth: 96, alignment: .leading)
                        GeometryReader { geo in
                            let fraction = min(Double(day.kcal) / Double(insights.target), 1.3) / 1.3
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.progressTrack)
                                Capsule().fill(insights.isOnTarget(day) || day.kcal < insights.target ? Color.progress : Color.brandDanger)
                                    .frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 8)
                        Text("\(day.kcal)" as String)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(minWidth: 48, alignment: .trailing)
                        if insights.isOnTarget(day) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.progress)
                        } else {
                            Image(systemName: "circle").foregroundStyle(Color.labelTertiary)
                        }
                    }
                    .frame(minHeight: 36)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(day.kcal) kilocalories\(insights.isOnTarget(day) ? ", on target" : "")")
                }
            }
            .padding(Spacing.lg)
            .premiumCard()
        }
    }
}

// MARK: - Home's week chart

/// The last 7 days as small bars with the target line, for the calorie card on Home.
struct WeekCaloriesMiniChart: View {
    let insights: CalorieInsights

    var body: some View {
        Chart {
            ForEach(insights.days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Calories", day.kcal))
                    .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.progress : Color.progress.opacity(0.55))
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Target", insights.target))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.labelTertiary)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(Double(insights.target) * 1.2, Double(insights.days.map(\.kcal).max() ?? 0)))
        .frame(height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 7 days")
        .accessibilityValue(insights.averageKcal.map { "Average \($0) kilocalories a day, target \(insights.target)" } ?? "Nothing logged yet")
    }
}
