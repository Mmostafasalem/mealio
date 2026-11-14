import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Colours (the app's Color tokens aren't in this target)

extension Color {
    /// Nourlo pink, the widgets' accent: rings and bars filling up.
    static let nourloPink = Color(red: 232 / 255, green: 105 / 255, blue: 138 / 255) // #E8698A
    /// The track behind a ring or bar.
    /// Dark ink for text on pink (white on this pink is too faint).
    static let nourloOnPink = Color(red: 0x24 / 255, green: 0x33 / 255, blue: 0x4D / 255) // #24334D
    static let nourloTrack = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x24 / 255, green: 0x30 / 255, blue: 0x42 / 255, alpha: 1)
            : UIColor(red: 0xEF / 255, green: 0xE8 / 255, blue: 0xE6 / 255, alpha: 1)
    })
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: NourloSnapshot
}

/// Reads the snapshot the app wrote. One entry now and one at midnight (a new
/// day starts at zero, with tomorrow's planned meals if the app saved them);
/// the app reloads the timelines whenever its numbers change.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let now = Date()
        // The gallery shows sample numbers until the app has written real ones.
        let saved = NourloSnapshotStore.load()
        let snapshot = context.isPreview && saved == nil ? .placeholder : NourloSnapshotStore.today(now: now)
        completion(SnapshotEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400))
        let entries = [
            SnapshotEntry(date: now, snapshot: NourloSnapshotStore.today(now: now)),
            SnapshotEntry(date: midnight, snapshot: NourloSnapshotStore.today(now: midnight)),
        ]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

// MARK: - Pieces

/// The calorie ring: pink fill on a soft track, accentable in tinted modes.
struct CalorieRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.nourloTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.001))
                .stroke(Color.nourloPink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }
}

/// One macro: name, grams of goal, and a thin bar.
struct MacroBar: View {
    let name: String
    let value: Int
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text(NourloWidgetFormat.macro(value, of: goal))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.nourloTrack)
                    Capsule().fill(Color.nourloPink)
                        .frame(width: proxy.size.width * NourloWidgetFormat.fraction(value, of: goal))
                        .widgetAccentable()
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NourloWidgetFormat.macroAccessibility(name, value, of: goal))
    }
}

/// The "Log food" button (iOS 17 interactive widget): opens the food logger.
struct LogFoodButton: View {
    var compact = false

    var body: some View {
        Button(intent: OpenNourloIntent(screen: .logFood)) {
            Label("Log food", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.nourloOnPink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: compact ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Color.nourloPink)
        .widgetAccentable()
        .accessibilityLabel("Log food")
        .accessibilityHint("Opens Nourlo's food logger")
    }
}
