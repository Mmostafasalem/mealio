import SwiftUI

/// Catalog estimates with loading / empty states; branch stock is not verified.
struct HomeDealsSection: View {
    let vm: HomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "basket.fill").foregroundStyle(Color.brandPrimary)
                    Text("Grocery estimates").font(.sectionTitle)
                }
                Spacer()
                if !vm.nearbyDeals.isEmpty {
                    Text("\(vm.nearbyDeals.count) items")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.coral, in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .accessibilityAddTraits(.isHeader)

            if vm.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(0..<3, id: \.self) { _ in SkeletonDealCard() }
                    }
                    .padding(.horizontal, 1)
                }
            } else if vm.nearbyDeals.isEmpty {
                emptyDeals
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(vm.nearbyDeals) { deal in
                            DealCardView(deal: deal) { vm.activeDealBanner = deal }
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
    }

    private var emptyDeals: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "basket")
                .font(.system(size: 32))
                .foregroundStyle(Color.brandPrimary.opacity(0.35))
            VStack(alignment: .leading, spacing: 3) {
                Text("No catalog estimates")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Pull down to refresh.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.sm)
    }
}

/// Shimmer placeholder shown while deals load.
struct SkeletonDealCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            .fill(Color(.systemFill))
            .frame(width: 160, height: 100)
            .shimmer(active: true)
            .accessibilityHidden(true)
    }
}
