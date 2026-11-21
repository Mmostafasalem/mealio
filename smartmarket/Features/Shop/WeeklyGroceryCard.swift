import SwiftUI

/// "This week's groceries": a list built on the phone that fits what's left of the
/// budget (see `WeeklyGroceryPlanner`). Remove what you don't want; Add all puts the
/// rest in the cart (and, through the cart, in My Stock).
struct WeeklyGroceryCard: View {
    @State private var cart = ShoppingCartService.shared
    @State private var removed: Set<String> = []
    @State private var added = 0
    /// Bumped when Profile changes the diet or the favourite foods, so the list is rebuilt.
    @State private var profileRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var plan: GroceryPlan {
        _ = profileRevision
        let favourites = Set(UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? [])
        let linked = Set((UserDefaults.standard.dictionary(forKey: "cartStockLinks_v1") as? [String: String] ?? [:]).values)
        let ownStock = StockStore.shared.items.filter { !linked.contains($0.id.uuidString) && !$0.isExpired() }.map(\.food.name)
        return WeeklyGroceryPlanner.plan(budget: cart.weeklyBudget, cart: cart.cartItems, favourites: favourites,
                                         preferences: .load(), excluded: removed, stock: ownStock) { cart.effectivePrice(for: $0, store: .catalog) }
    }

    var body: some View {
        let plan = plan
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Label("This week's groceries", systemImage: "list.bullet.clipboard").font(.headline)
                Spacer()
                Text(String(format: "€%.2f of €%.2f", plan.total, plan.available))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Color.labelSecondary)
                    .contentTransition(.numericText())
            }
            if plan.lines.isEmpty {
                Text(plan.available < WeeklyGroceryPlanner.minimumToSuggest ? "Your cart fills this week's budget."
                                        : "Your cart already has a balanced week, and nothing else fits what's left. Raise the budget or bring back cleared suggestions.")
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
            } else {
                Text(plan.tight
                     ? "Your budget is tight, so the basics for a balanced week come first, then your foods (two of a kind at most)."
                     : "The foods you picked, plus what a balanced week still needs, within what's left of your budget. Your meal plan is made from what you buy.")
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                VStack(spacing: 0) {
                    ForEach(plan.lines) { line in
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.item.name).font(.subheadline.weight(.medium))
                                Text(line.reason.rawValue).font(.caption).foregroundStyle(Color.labelSecondary)
                            }
                            Spacer()
                            Text(String(format: "€%.2f", line.price)).font(.subheadline).monospacedDigit()
                            Button {
                                withAnimation(reduceMotion ? .reducedFade : .snappyValue) { _ = removed.insert(line.item.id) }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.labelTertiary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(line.item.name) from the suggestions" as String)
                        }
                        .padding(.vertical, 6)
                        if line.id != plan.lines.last?.id { Divider() }
                    }
                }
                PrimaryButton(title: "Add all \(plan.lines.count) to cart", systemImage: "cart.badge.plus") {
                    for line in plan.lines { cart.add(line.item, store: .catalog) }
                    added &+= 1
                }
                .accessibilityIdentifier("shop.weeklyPlan.addAll")
            }
            if !removed.isEmpty {
                Button("Show removed suggestions again") { withAnimation { removed = [] } }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.labelPrimary)
            }
        }
        .padding(16)
        .premiumCard()
        .sensoryFeedback(.success, trigger: added)
        .animation(reduceMotion ? .reducedFade : .snappyValue, value: plan.lines.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shop.weeklyPlan")
        .onReceive(NotificationCenter.default.publisher(for: .personalDataDidChange)) { _ in profileRevision &+= 1 }
        .onAppear { profileRevision &+= 1 }
    }
}
