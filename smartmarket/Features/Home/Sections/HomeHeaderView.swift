import SwiftUI

/// Open typographic header. Today's nutrition, rather than decoration, leads Home.
struct HomeHeaderView: View {
    let vm: HomeViewModel
    /// Opens Profile and settings.
    var onProfile: () -> Void = {}
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
                // Nourlo's place: fixed here, but alive. Tapping it opens the quick actions.
                NourloButton()
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
