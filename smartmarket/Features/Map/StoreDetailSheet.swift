import SwiftUI

struct StoreDetailSheet: View {

    let store: Store
    @Bindable var vm: StoreMapViewModel
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var openRecipe: StoreRecipe?

    /// Recipes this store's products cover, best match first.
    private var storeRecipes: [StoreRecipe] {
        let deals = vm.deals(for: store)
        var ids = Set(deals.map(\.productId))
        let names = Set(deals.map { $0.productName.lowercased() })
        // productId is a catalog id offline and the backend integer online; names cover both
        for food in Food.catalog {
            if let b = food.backendId, ids.contains(String(b)) { ids.insert(food.id) }
            if names.contains(food.name.lowercased()) || names.contains(food.nameEn.lowercased()) { ids.insert(food.id) }
        }
        return StoreRecipe.recipesMatching(discountedIDs: ids)
    }

    /// The fan holds a hand of five; the rest stay in the list fallback.
    private static let fanLimit = 5

    // Deals whose name matches any favorited product name (name-based, works across all stores)
    private var favDeals: [MarketDeal] {
        vm.favouriteDeals(for: store, favIDs: appState.favoriteFoodIDs)
    }

    private var otherDeals: [MarketDeal] {
        vm.otherDeals(for: store, favIDs: appState.favoriteFoodIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                // Store header
                Section {
                    StoreHeaderRow(store: store)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    Text("Catalog estimates for this chain. Check prices and stock at the branch before shopping.")
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                }

                Section {
                    NavigationLink { RetailerProductsView(retailer: store.chain) } label: {
                        Label("Find reported retailer products", systemImage: "magnifyingglass")
                    }
                    Text("Explore packaged foods with source nutrition, then add what you have purchased to stock.")
                        .font(.footnote).foregroundStyle(.secondary)
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
                        Label("Favourite catalog items", systemImage: "heart.fill")
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
                        Label("Catalog estimates", systemImage: "basket.fill")
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                // Recipes from this store's products
                let recipes = storeRecipes
                if !recipes.isEmpty {
                    Section {
                        if FanCards<StoreRecipe, RecipeFanCard>.prefersStaticList(voiceOver: voiceOver, reduceMotion: reduceMotion, typeSize: typeSize) {
                            ForEach(recipes) { recipe in
                                RecipeListRow(recipe: recipe) { openRecipe = recipe }
                            }
                        } else {
                            FanCards(items: Array(recipes.prefix(Self.fanLimit)),
                                     label: { "\($0.name), \(Self.coverage($0))" },
                                     onOpen: { openRecipe = $0 }) { recipe in
                                RecipeFanCard(recipe: recipe, coverage: Self.coverage(recipe))
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    } header: {
                        Label("Recipes from this store", systemImage: "frying.pan")
                            .foregroundStyle(Color.labelSecondary)
                    } footer: {
                        if recipes.count > Self.fanLimit && !FanCards<StoreRecipe, RecipeFanCard>.prefersStaticList(voiceOver: voiceOver, reduceMotion: reduceMotion, typeSize: typeSize) {
                            Text("Showing the \(Self.fanLimit) best matches of \(recipes.count) recipes.")
                        }
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
                            .foregroundStyle(Color.labelSecondary)
                    }
                }

                if vm.deals(for: store).isEmpty {
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
        .sheet(item: $openRecipe) { recipe in
            RecipeSheet(mealName: recipe.name)
        }
    }

    static func coverage(_ recipe: StoreRecipe) -> String {
        "\(recipe.matchCount) of \(recipe.totalIngredients) ingredients here"
    }

    private func addToGrocery(_ marketDeal: MarketDeal) {
        if let deal = appState.activeDeals.first(where: { "\($0.id)" == marketDeal.productId }) {
            appState.addDealToGrocery(deal)
        }
    }

    private func mealPlanMatches() -> [String] {
        guard let plan = appState.weeklyMealPlan else { return [] }
        let dealNames = Set(vm.deals(for: store).map { $0.productName.lowercased() })
        // Weekday numbers are independent of localized weekday names.
        let today = Calendar.current.component(.weekday, from: Date())
        let lookup: [Int: DayPlan?] = [
            2: plan.pirmadienis, 3: plan.antradienis,
            4: plan.treciadienis, 5: plan.ketvirtadienis,
            6: plan.pentadienis, 7: plan.sestadienis,
            1: plan.sekmadienis
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
                    .fill(Color.rhino)
                    .frame(width: 52, height: 52)
                Text(store.chainIcon)
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(Color.almond)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.name)
                    .font(.headline)
                Text(store.address)
                    .font(.caption)
                    .foregroundStyle(Color.labelSecondary)
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
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f€", deal.discountPrice))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(Color.brandPrimary)
                Text("est. price")
                    .font(.caption2)
                    .foregroundStyle(Color.labelSecondary)
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

/// One recipe card in the fan.
private struct RecipeFanCard: View {
    let recipe: StoreRecipe
    let coverage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(Color.brandLight)
                .frame(height: 96)
                .overlay(
                    Image(systemName: recipe.coverSymbol)
                        .font(.title)
                        .foregroundStyle(Color.labelPrimary)
                )
            Text(recipe.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text(coverage)
                .font(.caption2)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        .elevation(Elevation.card)
    }
}

/// The plain list used under VoiceOver, Reduce Motion and large text.
private struct RecipeListRow: View {
    let recipe: StoreRecipe
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.md) {
                Image(systemName: recipe.coverSymbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.brandLight, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.labelPrimary)
                    Text(StoreDetailSheet.coverage(recipe))
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.labelTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the recipe")
    }
}

private struct MealMatchRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandPrimary)
                .font(.system(size: 16))
            Text(name)
                .font(.subheadline)
        }
    }
}
