import SwiftUI

struct StoreDetailSheet: View {

    let store: Store
    let vm: StoreMapViewModel

    private var favIDs: Set<String> {
        Set((UserDefaults.standard.array(forKey: Constants.Storage.favoriteFoodIDs) as? [String]) ?? [])
    }

    private var favDeals: [MarketDeal] {
        vm.storeDeals.filter { favIDs.contains($0.productId) }
    }

    private var otherDeals: [MarketDeal] {
        vm.storeDeals.filter { !favIDs.contains($0.productId) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !favDeals.isEmpty    { favouritesSection }
                allDealsSection
                recipesSection
                mealMatchesSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.surface)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: store.chainColor))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(store.chain.prefix(1)))
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.chain)
                        .font(.title3.bold())
                    Text(store.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(.caption)
                    .foregroundStyle(Color.brandPrimary)
                Text(store.address)
                    .font(.caption)
                    .foregroundStyle(Color.labelSecondary)
            }

            Text("\(vm.storeDeals.count) deals available")
                .font(.caption)
                .foregroundStyle(Color.labelTertiary)
        }
        .padding(.top, 8)
    }

    // MARK: - Favourites

    private var favouritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Your Favourites", symbol: "heart.fill", color: Color.brandDanger)
            ForEach(favDeals) { deal in
                DealRow(deal: deal, showHeart: true)
            }
        }
    }

    // MARK: - All deals

    private var allDealsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("All Deals", symbol: "tag.fill", color: Color.brandPrimary)
            if otherDeals.isEmpty && favDeals.isEmpty {
                Text("No deals at this store right now.")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
            } else {
                ForEach(otherDeals) { deal in
                    DealRow(deal: deal, showHeart: false)
                }
            }
        }
    }

    // MARK: - Recipes

    private var recipesSection: some View {
        let recipes = vm.recipesForStore(store)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recipes from today's discounts", symbol: "frying.pan.fill", color: Color.brandAmber)
            if recipes.isEmpty {
                Text("No matching recipes for current discounts.")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
            } else {
                ForEach(recipes) { recipe in
                    RecipeCardView(recipe: recipe)
                }
            }
        }
    }

    // MARK: - Meal plan matches

    private var mealMatchesSection: some View {
        let matches = mealPlanMatches()
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Matches your current meal plan", symbol: "fork.knife", color: Color.brandPrimary)
            if matches.isEmpty {
                Text("No meal plan matches at this store.")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
            } else {
                ForEach(matches, id: \.entry.id) { item in
                    MealMatchRow(mealType: item.mealType, entry: item.entry)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
        }
    }

    private func mealPlanMatches() -> [(mealType: String, entry: MealEntry)] {
        let discountedNames = Set(vm.storeDeals.map { $0.productName.lowercased() })

        let plan: MealPlan?
        if let weekly = AppState.shared.weeklyMealPlan {
            plan = MealPlan.from(weekly: weekly)
        } else if let data = UserDefaults.standard.data(forKey: Constants.Storage.currentMealPlan),
                  let weekly = try? JSONDecoder().decode(WeeklyMealPlan.self, from: data) {
            plan = MealPlan.from(weekly: weekly)
        } else {
            plan = nil
        }
        guard let plan else { return [] }

        var results: [(String, MealEntry)] = []
        let sections: [(String, [MealEntry])] = [
            ("sunrise", plan.breakfast),
            ("sun.max", plan.lunch),
            ("moon",    plan.dinner),
            ("sparkles", plan.snacks),
        ]
        for (symbol, entries) in sections {
            for entry in entries where discountedNames.contains(where: { entry.foodName.lowercased().contains($0) }) {
                results.append((symbol, entry))
            }
        }
        return results
    }
}

// MARK: - DealRow

private struct DealRow: View {
    let deal: MarketDeal
    let showHeart: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showHeart {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.brandDanger)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(deal.productName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(deal.quantity)
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                    DealTypeBadge(type: deal.dealType)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "€%.2f", deal.discountPrice))
                    .font(.subheadline.bold())
                Text("−\(deal.discountPercent)%")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.brandAmber.opacity(0.15))
                    .foregroundStyle(Color.brandAmber)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - DealTypeBadge

private struct DealTypeBadge: View {
    let type: MarketDeal.DealType

    private var label: String {
        switch type {
        case .weeklySpecial: return "Weekly"
        case .dailyFresh:    return "Fresh today"
        case .loyaltyCard:   return "Loyalty"
        case .clearance:     return "Clearance"
        case .bulkDeal:      return "Bulk"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.brandPrimary.opacity(0.12))
            .foregroundStyle(Color.brandPrimary)
            .clipShape(Capsule())
    }
}

// MARK: - RecipeCardView

private struct RecipeCardView: View {
    let recipe: StoreRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: recipe.coverSymbol)
                    .font(.title2)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.brandPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(recipe.matchCount) of \(recipe.totalIngredients) ingredients on discount today")
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.brandPrimary.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(
                            width: geo.size.width * CGFloat(recipe.matchCount) / CGFloat(max(recipe.totalIngredients, 1)),
                            height: 4
                        )
                }
            }
            .frame(height: 4)

            // Ingredient list
            FlowLayout(spacing: 6) {
                ForEach(recipe.requiredFoodIDs, id: \.self) { foodID in
                    let isAvailable = recipe.availableFoodIDs.contains(foodID)
                    let label = Food.catalog.first(where: { $0.id == foodID })?.nameEn ?? foodID
                    Text(label)
                        .font(.caption)
                        .strikethrough(!isAvailable, color: Color.labelTertiary)
                        .foregroundStyle(isAvailable ? Color.brandPrimary : Color.labelTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isAvailable
                                ? Color.brandPrimary.opacity(0.1)
                                : Color.surfaceSecondary
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - MealMatchRow

private struct MealMatchRow: View {
    let mealType: String   // SF Symbol
    let entry: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mealType)
                .font(.title3)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 36, height: 36)
                .background(Color.brandPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(.subheadline.weight(.medium))
                Text("\(entry.portionG)g")
                    .font(.caption)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            Text("On discount here")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.brandPrimary.opacity(0.12))
                .foregroundStyle(Color.brandPrimary)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

#Preview {
    let vm = StoreMapViewModel()
    let store = MarketDeal.mocked.first!.store
    vm.deals = MarketDeal.mocked
    vm.selectStore(store)
    return StoreDetailSheet(store: store, vm: vm)
}
