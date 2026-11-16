import SwiftUI

/// Price estimates for the person's favourite foods; nothing here is a verified shelf price.
struct HomeDealsSection: View {
    let vm: HomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HomeCardTitle(title: "Grocery estimates", symbol: "basket.fill")
                Spacer()
                if !vm.nearbyDeals.isEmpty {
                    Text("\(vm.nearbyDeals.count) items")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.dullPink, in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .accessibilityAddTraits(.isHeader)

            if vm.nearbyDeals.isEmpty {
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
                Text("No favourite foods yet")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Choose them in Profile to see their estimated prices here.")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
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
