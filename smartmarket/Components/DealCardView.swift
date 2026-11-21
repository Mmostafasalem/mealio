import SwiftUI

struct DealCardView: View {

    let deal: MarketDeal
    let onTap: () -> Void

    private var storeColor: Color { Color.labelPrimary }
    // The card widens and grows taller with the text size instead of clipping it.
    @ScaledMetric(relativeTo: .callout) private var side: CGFloat = 178

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ─────────────────────────────────────────────────
                HStack(spacing: 6) {
                    Circle()
                        .fill(storeColor)
                        .frame(width: 6, height: 6)
                    Text("ESTIMATE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.labelSecondary)
                        .kerning(0.8)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // ── Product name ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text(deal.productName)
                        .font(.callout).fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !deal.quantity.isEmpty {
                        Text(deal.quantity)
                            .font(.caption2)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer(minLength: 6)

                // ── Price row (estimated) ─────────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "€%.2f", deal.discountPrice))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.brandPrimary)
                    Text("est. price")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .frame(width: min(side, 300), alignment: .topLeading)
            .frame(minHeight: 178, maxHeight: .infinity, alignment: .topLeading)
            .premiumCard(radius: Radius.tile)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(deal.productName), estimated \(String(format: "%.2f", deal.discountPrice)) euros")
    }
}

// MARK: - Pressable button style (shared via ViewModifiers.swift)

private struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(reduceMotion ? .none : .snappyValue, value: configuration.isPressed)
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 14) {
            ForEach(MarketDeal.mocked.prefix(4)) { deal in
                DealCardView(deal: deal, onTap: {})
            }
        }
        .padding()
    }
}
