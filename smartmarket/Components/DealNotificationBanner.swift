import SwiftUI

/// Top-of-screen banner announcing a deal on a favorited food.
/// Auto-dismisses (as a skip) after 8 seconds.
struct DealNotificationBanner: View {

    let deal: MarketDeal
    let onBuy: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration: TimeInterval = 8
    @State private var startDate: Date = .now
    @State private var buyTrigger = false
    @State private var skipTrigger = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Deal on \(deal.productName)")
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Text("\(deal.store.chain) · \(deal.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(String(format: "€%.2f", deal.discountPrice))
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundStyle(Color.brandPrimary)
                        Text(String(format: "€%.2f", deal.originalPrice))
                            .font(.caption).foregroundStyle(.secondary)
                            .strikethrough()
                        Text("−\(deal.discountPercent)%")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(Color.brandAmber)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    skipTrigger.toggle()
                    onSkip()
                } label: {
                    Text("Skip")
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(.separator), lineWidth: 1)
                        )
                }
                .sensoryFeedback(.warning, trigger: skipTrigger)

                Button {
                    buyTrigger.toggle()
                    onBuy()
                } label: {
                    Label("Buy it", systemImage: "cart.badge.plus")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .onAppear { startDate = .now }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onSkip()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deal alert for \(deal.productName)")
    }
}

#Preview {
    DealNotificationBanner(deal: MarketDeal.mocked[0], onBuy: {}, onSkip: {})
}
