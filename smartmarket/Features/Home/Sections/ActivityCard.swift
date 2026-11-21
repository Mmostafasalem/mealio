import SwiftUI

/// Today's steps and active energy from Apple Health. Shown only while Apple
/// Health is on and access has been asked for; tapping opens its settings.
struct ActivityCard: View {

    @State private var health = HealthService.shared

    var body: some View {
        if health.showsActivity {
            NavigationLink { HealthSettingsView() } label: { card }
                .buttonStyle(ScalePressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityText(steps: health.stepsToday, kcal: health.activeKcalToday))
                .accessibilityHint("Opens Apple Health settings")
                .accessibilityIdentifier("home.activity")
                .task { await health.refreshReads() }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HomeCardTitle(title: "Activity today", symbol: "figure.walk")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.lg) { stats }
                VStack(alignment: .leading, spacing: Spacing.md) { stats }
            }
            Text("From Apple Health")
                .font(.caption)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .premiumCard()
    }

    @ViewBuilder private var stats: some View {
        stat(value: Self.number(health.stepsToday), unit: "steps", symbol: "shoeprints.fill")
        stat(value: Self.number(health.activeKcalToday), unit: "active kcal", symbol: "flame.fill")
    }

    private func stat(value: String, unit: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Color.progress)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.labelPrimary)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whole numbers with grouping, or a dash while unknown.
    static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return Int(value.rounded()).formatted(.number.grouping(.never))
    }

    static func accessibilityText(steps: Double?, kcal: Double?) -> String {
        let stepsText = steps.map { "\(Int($0.rounded()).formatted(.number.grouping(.never))) steps" } ?? "steps not available"
        let kcalText = kcal.map { "\(Int($0.rounded()).formatted(.number.grouping(.never))) active kilocalories" } ?? "active energy not available"
        return "Activity today from Apple Health: \(stepsText), \(kcalText)"
    }
}
