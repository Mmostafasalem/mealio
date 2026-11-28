import SwiftUI
import WidgetKit

/// Calories left today, on the home screen, in StandBy and on the lock screen.
struct CaloriesWidget: Widget {
    static let kind = "NourloCalories"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            CaloriesWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Calories")
        .description("How much of today's calorie goal is left, with protein, carbs and fat.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CaloriesWidgetView: View {
    let snapshot: NourloSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(snapshot.needsSetup ? NourloLink.home.url : NourloLink.logFood.url)
    }

    @ViewBuilder private var content: some View {
        if snapshot.needsSetup {
            setup
        } else {
            numbers
        }
    }

    /// Before Nourlo is set up there is no goal, so no numbers to show.
    @ViewBuilder private var setup: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "flame")
                .font(.title2)
                .widgetAccentable()
                .accessibilityLabel(NourloSnapshot.setupPrompt)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryInline:
            Label(NourloSnapshot.setupPrompt, systemImage: "flame")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").widgetAccentable()
                    Text("Calories").font(.headline).widgetAccentable()
                }
                Text(NourloSnapshot.setupPrompt)
                    .font(.body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(Color.nourloPink)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(NourloSnapshot.setupPrompt)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    @ViewBuilder private var numbers: some View {
        switch family {
        case .accessoryCircular:
            CaloriesCircular(snapshot: snapshot)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            CaloriesRectangular(snapshot: snapshot)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Label(NourloWidgetFormat.inline(snapshot), systemImage: "flame")
                .accessibilityLabel(NourloWidgetFormat.caloriesAccessibility(snapshot))
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            CaloriesMedium(snapshot: snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        default:
            CaloriesSmall(snapshot: snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

/// The big number and its caption, read as one sentence by VoiceOver.
private struct CaloriesHeadline: View {
    let snapshot: NourloSnapshot
    var numberFont: Font = .system(.title2, design: .rounded).weight(.bold)

    var body: some View {
        VStack(spacing: 0) {
            Text("\(NourloWidgetFormat.headlineNumber(snapshot))" as String)
                .font(numberFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(NourloWidgetFormat.headlineCaption(snapshot))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct CaloriesSmall: View {
    let snapshot: NourloSnapshot

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                CalorieRing(progress: snapshot.progress, lineWidth: 9)
                CaloriesHeadline(snapshot: snapshot).padding(12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NourloWidgetFormat.caloriesAccessibility(snapshot))
            LogFoodButton(compact: true)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

private struct CaloriesMedium: View {
    let snapshot: NourloSnapshot

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 8) {
                ZStack {
                    CalorieRing(progress: snapshot.progress, lineWidth: 10)
                    CaloriesHeadline(snapshot: snapshot, numberFont: .system(.title, design: .rounded).weight(.bold))
                        .padding(14)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NourloWidgetFormat.caloriesAccessibility(snapshot))
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                MacroBar(name: "Protein", value: snapshot.proteinG, goal: snapshot.proteinGoalG)
                MacroBar(name: "Carbs", value: snapshot.carbsG, goal: snapshot.carbsGoalG)
                MacroBar(name: "Fat", value: snapshot.fatG, goal: snapshot.fatGoalG)
                LogFoodButton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

private struct CaloriesCircular: View {
    let snapshot: NourloSnapshot

    var body: some View {
        Gauge(value: snapshot.progress) {
            Image(systemName: "flame")
        } currentValueLabel: {
            Text("\(NourloWidgetFormat.headlineNumber(snapshot))" as String)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(Color.nourloPink)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NourloWidgetFormat.caloriesAccessibility(snapshot))
    }
}

private struct CaloriesRectangular: View {
    let snapshot: NourloSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").widgetAccentable()
                Text("Calories").font(.headline).widgetAccentable()
            }
            Text(NourloWidgetFormat.inline(snapshot))
                .font(.body)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Gauge(value: snapshot.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(Color.nourloPink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NourloWidgetFormat.caloriesAccessibility(snapshot))
    }
}

#Preview(as: .systemSmall) { CaloriesWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
#Preview(as: .systemMedium) { CaloriesWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
#Preview(as: .accessoryRectangular) { CaloriesWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
