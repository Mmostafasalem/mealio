import SwiftUI

struct StoreDetailSheet: View {

    let store: Store
    @Bindable var vm: StoreMapViewModel
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Deals whose name matches any favorited product name (name-based, works across all stores)
    private var favDeals: [MarketDeal] {
        let favNames = ProductCatalogService.shared.nameFor(ids: appState.favoriteFoodIDs)
        return vm.storeDeals.filter { deal in
            let dn = deal.productName.lowercased()
            return favNames.contains { fav in dn.contains(fav) || fav.contains(dn.prefix(8)) }
        }
    }

    private var otherDeals: [MarketDeal] {
        let favDealIDs = Set(favDeals.map(\.id))
        return vm.storeDeals.filter { !favDealIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Store header
                Section {
                    StoreHeaderRow(store: store)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // Favourite deals
                if !favDeals.isEmpty {
                    Section {
                        ForEach(favDeals) { deal in
                            DealRow(deal: deal, isFav: true) {
                                addToGrocery(deal)
                            }
                        }
                    } header: {
                        Label("Your Favourites Here", systemImage: "heart.fill")
                            .foregroundStyle(Color.brandPrimary)
                    }
                }

                // All other deals
                if !otherDeals.isEmpty {
                    Section {
                        ForEach(otherDeals) { deal in
                            DealRow(deal: deal, isFav: false) {
                                addToGrocery(deal)
                            }
                        }
                    } header: {
                        Label("All Products", systemImage: "basket.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                // Meal plan matches
                let matches = mealPlanMatches()
                if !matches.isEmpty {
                    Section {
                        ForEach(matches, id: \.self) { name in
                            MealMatchRow(name: name)
                        }
                    } header: {
                        Label("In Your Meal Plan", systemImage: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
                }

                if vm.storeDeals.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No products",
                            systemImage: "basket",
                            description: Text("No products listed for this store yet.")
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(store.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func addToGrocery(_ marketDeal: MarketDeal) {
        if let deal = appState.activeDeals.first(where: { "\($0.id)" == marketDeal.productId }) {
            appState.addDealToGrocery(deal)
        }
    }

    private func mealPlanMatches() -> [String] {
        guard let plan = appState.weeklyMealPlan else { return [] }
        let dealNames = Set(vm.storeDeals.map { $0.productName.lowercased() })
        let today = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1].lowercased()
        let lookup: [String: DayPlan?] = [
            "monday": plan.pirmadienis, "tuesday": plan.antradienis,
            "wednesday": plan.treciadienis, "thursday": plan.ketvirtadienis,
            "friday": plan.pentadienis, "saturday": plan.sestadienis,
            "sunday": plan.sekmadienis
        ]
        guard let dayPlan = lookup[today] ?? plan.pirmadienis else { return [] }

        var matches: [String] = []
        for meal in [dayPlan.pusryciai, dayPlan.pietus, dayPlan.vakariene, dayPlan.uzkandziai].compactMap({ $0 }) {
            if dealNames.contains(where: { meal.pavadinimas.lowercased().contains($0) || $0.contains(meal.pavadinimas.lowercased()) }) {
                matches.append(meal.pavadinimas)
            }
        }
        return matches
    }
}

// MARK: - Sub-views

private struct StoreHeaderRow: View {
    let store: Store

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: store.chainColor))
                    .frame(width: 52, height: 52)
                Text(store.chainIcon)
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.name)
                    .font(.headline)
                Text(store.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct DealRow: View {
    let deal: MarketDeal
    let isFav: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isFav {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.brandPrimary)
                    }
                    Text(deal.productName)
                        .font(.subheadline).fontWeight(.medium)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(deal.quantity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f€", deal.discountPrice))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(Color.brandPrimary)
                Text("est. price")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.brandPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(deal.productName) to cart")
        }
        .padding(.vertical, 2)
    }
}

private struct MealMatchRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(hex: "#10B981"))
                .font(.system(size: 16))
            Text(name)
                .font(.subheadline)
        }
    }
}
