import SwiftUI

/// Open typographic header. Today's nutrition, rather than decoration, leads Home.
struct HomeHeaderView: View {
    let vm: HomeViewModel
    /// Opens Profile and settings.
    var onProfile: () -> Void = {}
    @AppStorage("bowlGuideVisible_v2") private var bowlVisible = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vm.now, format: dynamicTypeSize.isAccessibilitySize
                         ? .dateTime.day().month(.abbreviated)
                         : .dateTime.weekday(.wide).day().month(.wide))
                        .font(.captionText)
                        .foregroundStyle(Color.labelSecondary)
                    // The wave sets its own Dynamic Type-scaled font; kerning -1 matches the old tracking.
                    WeightWaveText("Today", kerning: -1)
                        .foregroundStyle(Color.labelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: Spacing.sm)
                // Offline status lives in Home's MorphIsland notice now.
                // Nourlo's place: fixed here, but alive. Tapping it opens the guide.
                if bowlVisible { HeaderBowl() }
                // Reminders live in Profile › Notifications, not on Home (TestFlight B5).
                // The avatar is the way into Profile and settings.
                Button(action: onProfile) {
                    // The profile photo when there is one, else the initial.
                    ProfileAvatar(size: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityLabel("Profile and settings")
                .accessibilityIdentifier("home.profile")
            }

        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared card grid
//
// Every Home card uses the same two columns: a 30pt icon column, a 12pt gap,
// then text. Titles, rows, dividers and nested lines all start on those edges,
// and trailing values end on the card's right padding.
enum HomeGrid {
    /// A glyph sits centred in this column, so the column plus the gap is what the eye
    /// reads as the space between icon and text: keep both small.
    static let icon: CGFloat = 24
    static let gap: CGFloat = 5
    /// Where text starts, measured from the card's leading padding.
    static var textInset: CGFloat { icon + gap }
}

/// A card's title, with its icon centred in the shared icon column.
struct HomeCardTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: HomeGrid.gap) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .frame(width: HomeGrid.icon)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The bowl in Home's header. It stays put, but it isn't a picture: it
/// breathes and blinks, strikes a pose every few seconds (a wave, then a hop),
/// thinks while a meal plan is being written and celebrates a logged meal.
struct HeaderBowl: View {
    @State private var pose = 0
    @State private var celebrating = false
    @State private var loop = DailyLoopStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Writing a meal plan wins, then a fresh win, then how the streak is doing.
    private var mood: MascotMood {
        if AppState.shared.isGeneratingMealPlan { return .thinking }
        if celebrating { return .celebrate }
        return loop.state.mood
    }

    private func celebrate() {
        celebrating = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            celebrating = false
        }
    }

    var body: some View {
        MascotGuideView(mood: mood, size: 44, onTap: {
            NotificationCenter.default.post(name: .toggleBowlGuide, object: nil)
        }, trigger: pose)
            // The character's own padding makes a 68 pt button; keep the row at 44.
            .frame(width: 56, height: 44)
            .overlay(alignment: .bottomTrailing) {
                if loop.state.streak > 0 {
                    Text("\(loop.state.streak)" as String)
                        .font(.system(.caption2, design: .rounded).weight(.heavy).monospacedDigit())
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.progress, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.surfaceGrouped, lineWidth: 2))
                        .contentTransition(.numericText())
                        .offset(x: 2, y: 2)
                        .accessibilityLabel("\(loop.state.streak)-day streak" as String)
                        .accessibilityIdentifier("home.streakBadge")
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: FoodLogStore.shared.entries.count) { old, new in
                guard new > old else { return }
                celebrate()
            }
            .onChange(of: loop.lastCompletion) { _, _ in celebrate() }
            .onChange(of: loop.pendingMilestone) { _, days in if days != nil { celebrate() } }
            .task {
                // A fresh pose now and then; it rests in between.
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(7))
                    guard !Task.isCancelled else { return }
                    pose += 1
                }
            }
    }
}
