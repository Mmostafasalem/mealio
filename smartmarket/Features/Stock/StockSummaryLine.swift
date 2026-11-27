import SwiftUI

/// One line under a food on a review card: "From your stock: Bread (150 g left after this)"
/// or "Not in your stock". Logging takes the amount out of that stock item.
struct StockSummaryLine: View {
    let summary: StockSummary

    var body: some View {
        Label {
            Text(summary.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: summary.inStock ? "cabinet.fill" : "cabinet")
                .foregroundStyle(summary.inStock ? Color.ringProtein : Color.labelSecondary)
        }
        .font(.caption)
        .foregroundStyle(summary.inStock ? Color.labelPrimary : Color.labelSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(summary.inStock ? "stockLine.from" : "stockLine.none")
    }
}
