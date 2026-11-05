import SwiftUI

/// Open typographic header. Today's nutrition, rather than decoration, leads Home.
struct HomeHeaderView: View {
    let vm: HomeViewModel
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
                    Text(dynamicTypeSize.isAccessibilitySize ? "Your balance." : "Your day,\nyour balance.")
                        .font(.largeTitle.weight(.bold))
                        .tracking(-1)
                        .foregroundStyle(Color.labelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: Spacing.sm)
                if !NetworkMonitor.shared.isOnline { OfflineBadge() }
                Text(AppState.shared.userProfile.name.prefix(1).uppercased())
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(8)
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.coral, in: Circle())
                    .accessibilityHidden(true)
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Spacing.lg))
            layout {
                Label("Goal · \(vm.goal) kcal", systemImage: "target")
                Label("Catalog · \(vm.nearbyDeals.count) items", systemImage: "basket")
                if vm.isRefreshing { ProgressView().accessibilityLabel("Refreshing catalog") }
            }
            .font(.captionText)
            .foregroundStyle(Color.labelSecondary)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
