import SwiftUI

/// Compact horizontally-scrolling deal card.
struct DealCardView: View {

    let deal: MarketDeal
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: deal.store.chainColor))
                        .frame(width: 8, height: 8)
                    Text(deal.store.chain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("−\(deal.discountPercent)%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.brandAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.brandAmberLight)
                        .clipShape(Capsule())
                }

                Text(deal.productName)
                    .font(.callout).fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(deal.quantity)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "€%.2f", deal.discountPrice))
                        .font(.headline).fontWeight(.bold)
                        .foregroundStyle(Color.brandPrimary)
                    Text(String(format: "€%.2f", deal.originalPrice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            }
            .padding(14)
            .frame(width: 180, height: 150, alignment: .topLeading)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(deal.productName) at \(deal.store.chain), \(deal.discountPercent) percent off, now \(String(format: "%.2f", deal.discountPrice)) euros")
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack {
            ForEach(MarketDeal.mocked) { deal in
                DealCardView(deal: deal, onTap: {})
            }
        }
        .padding()
    }
}
