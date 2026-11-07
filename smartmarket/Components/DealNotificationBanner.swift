import SwiftUI

/// Compatibility surface for existing Home callers. Catalog prices have no
/// retailer verification, so they must not produce unsolicited retailer alerts,
/// countdowns, or alert purchase actions. Estimates remain in the catalog UI.
struct DealNotificationBanner: View {
    let deal: MarketDeal
    let onBuy: () -> Void
    let onSkip: () -> Void

    var body: some View {
        EmptyView()
    }
}
