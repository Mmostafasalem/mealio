import SwiftUI

/// The card shown when the person taps a grocery estimate on Home (it lives inside
/// Home's MorphIsland). Catalog prices have no retailer verification, so this is
/// never an unsolicited alert: it shows one "est. price", no savings, no countdown,
/// and "Add to list" only adds the item to the grocery list.
struct DealNotificationBanner: View {
    let deal: MarketDeal
    let onBuy: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "basket.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.brandLight, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deal.productName)
                        .font(.headline)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(2)
                    Text("\(deal.store.name) · \(deal.quantity)")
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "€%.2f", deal.discountPrice))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.labelPrimary)
                    Text("est. price")
                        .font(.caption2)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: Spacing.sm) {
                Button(action: onSkip) {
                    Text("Skip")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.labelPrimary)
                        .background(Color.surfaceSecondary, in: Capsule())
                        .contentShape(Capsule())
                }
                Button(action: onBuy) {
                    Label("Add to list", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.surface)
                        .background(Color.labelPrimary, in: Capsule())
                        .contentShape(Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(ScalePressStyle())
        }
        // No auto-dismiss: this card opens only when the person taps an estimate,
        // so it stays until they choose Skip or Add to list.
        .padding(Spacing.lg)
    }
}

#Preview("Deal card") {
    if let deal = MarketDeal.mocked.first {
        DealNotificationBanner(deal: deal, onBuy: {}, onSkip: {})
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding()
            .background(Color.surfaceGrouped)
    }
}
