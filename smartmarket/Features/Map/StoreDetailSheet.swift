import SwiftUI

struct StoreDetailSheet: View {

    let store: Store
    @State var vm: StoreMapViewModel
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Bridge: catalog string IDs → backend int product IDs
    private var favProductIDs: Set<String> {
        let strIDs = appState.favoriteFoodIDs
        let intIDs = Food.catalog
            .filter { strIDs.contains($0.id) }
            .compactMap { $0.backendId.map { String($0) } }
        return Set(intIDs)
    }

    private var favDeals: [MarketDeal] {
        vm.storeDeals.filter { favProductIDs.contains($0.productId) }
    }

    private var otherDeals: [MarketDeal] {
        vm.storeDeals.filter { !favProductIDs.contains($0.productId) }
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
                                vm.addDealToList(deal)
                            }
                        }
                    } header: {
                        Label("Your Favourites On Discount", systemImage: "heart.fill")
                            .foregroundStyle(Color.brandPrimary)
                    }
                }

                // All other deals
                if !otherDeals.isEmpty {
                    Section {
                        ForEach(otherDeals) { deal in
                            DealRow(deal: deal, isFav: false) {
                                vm.addDealToList(deal)
                            }
                        }
                    } header: {
                        Label("All Deals", systemImage: "tag.fill")
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
                            "No deals",
                            systemImage: "tag.slash",
                            description: Text("No active deals at this store right now.")
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

    private func mealPlanMatches() -> [String] {
        guard let plan = appState.weeklyMealPlan else { return [] }
        let dealNames = Set(vm.storeDeals.map { $0.productName.lowercased() })
        let today = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1].lowercased()
        let dayPlan = [
            "monday": plan.pirmadienis, "tuesday": plan.antradienis,
            "wednesday": plan.treciadienis, "thursday": plan.ketvirtadienis,
            "friday": plan.pentadienis, "saturday": plan.sestadienis,
            "sunday": plan.sekmadienis
        ][today] ?? plan.pirmadienis

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
                    DealTypeBadge(type: deal.dealType)
                    Text(deal.quantity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(String(format: "%.2f€", deal.discountPrice))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(Color.brandPrimary)
                    Text("-\(deal.discountPercent)%")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.brandPrimary.opacity(0.12))
                        .foregroundStyle(Color.brandPrimary)
                        .clipShape(Capsule())
                }
                Text(String(format: "%.2f€", deal.originalPrice))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.brandPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

private struct DealTypeBadge: View {
    let type: MarketDeal.DealType

    private var color: Color {
        switch type {
        case .weeklySpecial: return .brandPrimary
        case .dailyFresh:    return Color(hex: "#10B981")
        case .loyaltyCard:   return Color.brandAmber
        case .clearance:     return Color(hex: "#EF4444")
        case .bulkDeal:      return Color(hex: "#8B5CF6")
        }
    }

    var body: some View {
        Text(type.displayName)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
