import WidgetKit
import SwiftUI

// The widget extension: home-screen and lock-screen widgets, the workout
// Live Activity, and the Control Center button. Feature code lives in the
// other files in this folder; shared data types are in ../Shared.

@main
struct NourloWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
    }
}

/// Calories left today (scaffold; the full set of sizes is built on top of this).
struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NourloCalories", provider: CaloriesProvider()) { entry in
            VStack(spacing: 2) {
                Text("\(entry.snapshot.caloriesLeft)").font(.title.weight(.bold)).monospacedDigit()
                Text("kcal left").font(.caption).foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(NourloLink.logFood.url)
        }
        .configurationDisplayName("Calories left")
        .description("How much of today's calorie goal is left.")
        .supportedFamilies([.systemSmall])
    }
}

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let snapshot: NourloSnapshot
}

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry { CaloriesEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(CaloriesEntry(date: Date(), snapshot: context.isPreview ? .placeholder : NourloSnapshotStore.today()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let now = Date()
        // Refresh at midnight so a new day starts at zero even if the app isn't opened.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        completion(Timeline(entries: [CaloriesEntry(date: now, snapshot: NourloSnapshotStore.today(now: now))],
                            policy: .after(midnight)))
    }
}
