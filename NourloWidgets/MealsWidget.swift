import SwiftUI
import WidgetKit

/// Today's planned meals with their calories.
struct MealsWidget: Widget {
    static let kind = "NourloMeals"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            MealsWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(NourloLink.meals.url)
        }
        .configurationDisplayName("Today's meals")
        .description("The meals planned for today, with calories.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MealsWidgetView: View {
    let snapshot: NourloSnapshot
    @Environment(\.widgetFamily) private var family

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 12 : 6) {
            header
            if snapshot.meals.isEmpty {
                empty
            } else {
                ForEach(Array(snapshot.meals.prefix(isLarge ? 6 : 3).enumerated()), id: \.offset) { _, meal in
                    MealRow(meal: meal, isLarge: isLarge)
                }
                let hidden = snapshot.meals.count - (isLarge ? 6 : 3)
                if hidden > 0 {
                    Text("+\(hidden) more" as String)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Today's meals", systemImage: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.nourloPink)
                .widgetAccentable()
            Spacer(minLength: 4)
            if !snapshot.meals.isEmpty {
                Text("\(NourloWidgetFormat.plannedTotal(snapshot.meals)) kcal" as String)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(NourloWidgetFormat.plannedTotal(snapshot.meals)) calories planned" as String)
            }
        }
        .lineLimit(1)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("No meal plan yet")
                .font(.headline)
            Text("Make a plan in Nourlo and today's meals show here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MealRow: View {
    let meal: NourloSnapshot.Meal
    let isLarge: Bool

    var body: some View {
        HStack(alignment: isLarge ? .top : .center, spacing: 10) {
            Image(systemName: NourloWidgetFormat.symbol(forSlot: meal.slot))
                .font(.subheadline)
                .foregroundStyle(Color.nourloPink)
                .widgetAccentable()
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(meal.slot)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(meal.name)
                    .font(isLarge ? .subheadline : .caption)
                    .lineLimit(isLarge ? 2 : 1)
            }
            Spacer(minLength: 4)
            Text("\(meal.kcal) kcal" as String)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NourloWidgetFormat.mealAccessibility(meal))
    }
}

#Preview(as: .systemMedium) { MealsWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder)
    SnapshotEntry(date: .now, snapshot: .empty())
}
#Preview(as: .systemLarge) { MealsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
