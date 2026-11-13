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
