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
                    Text(Date(), format: dynamicTypeSize.isAccessibilitySize
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
                // The avatar is the way into Profile and settings.
                Button(action: onProfile) {
                    Group {
                        if let initial = AppState.shared.userProfile.name.first {
                            Text(String(initial).uppercased())
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                        } else {
                            Image(systemName: "person.fill").font(.headline)
                        }
                    }
                    .padding(8)
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.dullPink, in: Circle())
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
    static let icon: CGFloat = 30
    static let gap: CGFloat = Spacing.md
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
