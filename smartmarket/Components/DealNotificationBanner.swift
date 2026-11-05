import SwiftUI

/// Top-of-screen banner announcing a deal on a favorited food.
/// Auto-dismisses (as a skip) after 8 seconds.
struct DealNotificationBanner: View {

    let deal: MarketDeal
    let onBuy: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let duration: TimeInterval = 8
    @State private var startDate: Date = .now
    @State private var buyTrigger = false
    @State private var skipTrigger = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.dullPink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(deal.productName)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(2)
                    Text("\(deal.store.chain) · \(deal.quantity)")
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                    let priceLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                        : AnyLayout(HStackLayout(spacing: 6))
                    priceLayout {
                        Text(String(format: "€%.2f", deal.discountPrice))
                            .font(.subheadline).fontWeight(.bold)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(Color.brandPrimary)
                        Text("est. price")
                            .font(.caption2)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            let actionLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Spacing.sm))
                : AnyLayout(HStackLayout(spacing: 10))
            actionLayout {
                Button {
                    skipTrigger.toggle()
                    onSkip()
                } label: {
                    Text("Dismiss")
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .foregroundStyle(Color.labelPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 1)
                        )
                }
                .buttonStyle(ScalePressStyle())
                .sensoryFeedback(.warning, trigger: skipTrigger)

                Button {
                    buyTrigger.toggle()
                    onBuy()
                } label: {
                    Label("Add to list", systemImage: "cart.badge.plus")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .foregroundStyle(Color.onAccent)
                        .background(Color.dullPink,
                                    in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                }
                .buttonStyle(ScalePressStyle())
                .sensoryFeedback(.success, trigger: buyTrigger)
            }

            if !reduceMotion {
                // Updates once per second — not 60fps
                TimelineView(.periodic(from: startDate, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(startDate)
                    let fraction = max(0, 1 - elapsed / duration)
                    ProgressView(value: fraction, total: 1.0)
                        .tint(Color.brandPrimary.opacity(0.5))
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(Spacing.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .elevation(Elevation.high)
        .padding(.horizontal, Spacing.lg)
        .onAppear { startDate = .now }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onSkip()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(deal.productName) at \(deal.store.chain), estimated \(String(format: "%.2f", deal.discountPrice)) euros")
    }
}

#Preview {
    DealNotificationBanner(deal: MarketDeal.mocked[0], onBuy: {}, onSkip: {})
}
