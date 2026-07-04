import SwiftUI

struct DealCardView: View {

    let deal: MarketDeal
    let onTap: () -> Void

    private var storeColor: Color { Color(hex: deal.store.chainColor) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header: store stripe ───────────────────────────────────
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(storeColor)
                        .frame(width: 3)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(storeColor)
                            .frame(width: 6, height: 6)
                        Text(deal.store.chain.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(storeColor)
                            .kerning(0.8)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(storeColor.opacity(0.07))
                }

                // ── Product name ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text(deal.productName)
                        .font(.callout).fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(deal.quantity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer(minLength: 6)

                // ── Price row (estimated) ─────────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "€%.2f", deal.discountPrice))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.brandPrimary)
                    Text("est. price")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .frame(width: 178, height: 178, alignment: .topLeading)
            .background(
                // Subtle store-color wash at the top
                LinearGradient(
                    colors: [storeColor.opacity(0.06), Color.surface],
                    startPoint: .top, endPoint: .center
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: storeColor.opacity(0.10), radius: 4, x: 0, y: 2)
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color(.separator).opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(deal.productName) at \(deal.store.chain), estimated \(String(format: "%.2f", deal.discountPrice)) euros")
    }
}

// MARK: - Pressable button style (shared via ViewModifiers.swift)

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
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
