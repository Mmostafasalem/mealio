import SwiftUI

// MARK: - Cook with what I have
//
// Recipes the food in My Stock can make, with no AI: ready ones first, then the
// ones missing one or two things (which go to the cart in one tap). Searching
// looks through the whole cookbook. Recipes come from the Wikibooks Cookbook
// (CC BY-SA 4.0); the credit stays under every recipe.

struct CookWithWhatIHaveView: View {
    @State private var stock = StockStore.shared
    @State private var all: [CookbookRecipe] = []
    @State private var suggestions: [CookbookSuggestion] = []
    @State private var loading = true
    @State private var course: CookbookRecipe.Course?
    @State private var query = ""

    private var prefs: Set<DietaryPreference> { Set<DietaryPreference>.load() }
    private var stockNames: [String] { stock.items.map(\.food.name) }

    private var shown: [CookbookSuggestion] {
        suggestions.filter { course == nil || $0.recipe.course == course }
    }

    private var searchResults: [CookbookRecipe] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return all.filter { $0.title.localizedStandardContains(q) && (course == nil || $0.course == course) }
            .prefix(80).map { $0 }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        chip("All", selected: course == nil) { course = nil }
                        ForEach(CookbookRecipe.Course.allCases.filter { $0 != .sauce || !query.isEmpty }, id: \.self) { c in
                            chip(c.title, selected: course == c) { course = course == c ? nil : c }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if !query.isEmpty {
                Section("From the cookbook") {
                    if searchResults.isEmpty { Text("No recipe called “\(query)”.").foregroundStyle(.secondary) }
                    ForEach(searchResults) { recipe in
                        let missing = KitchenMatcher(names: stockNames).missing(in: recipe)
                        row(recipe, have: recipe.keyIngredients.count - missing.count, missing: missing)
                    }
                }
            } else if stock.items.isEmpty {
                ContentUnavailableView("Your stock is empty", systemImage: "cabinet",
                                       description: Text("Add what's in your kitchen to My Stock, and recipes that use it show up here. You can also search all \(all.count) recipes."))
                    .listRowBackground(Color.clear)
            } else if shown.isEmpty {
                ContentUnavailableView("Nothing close yet", systemImage: "frying.pan",
                                       description: Text("No recipe can be made with what's in stock or with one or two more things. Search to browse all \(all.count) recipes."))
                    .listRowBackground(Color.clear)
            } else {
                let ready = shown.filter { $0.missing.isEmpty }
                let nearly = shown.filter { !$0.missing.isEmpty }
                if !ready.isEmpty {
                    Section {
                        ForEach(ready.prefix(60)) { s in row(s.recipe, have: s.have, missing: s.missing) }
                    } header: { Text("Ready to cook") } footer: { Text("Salt, oil, spices, flour, sugar and stock are counted as kitchen basics.") }
                }
                if !nearly.isEmpty {
                    Section("One or two things short") {
                        ForEach(nearly.prefix(60)) { s in row(s.recipe, have: s.have, missing: s.missing) }
                    }
                }
            }

            Section {
                CookbookCredit(recipe: nil)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background { GrainyGradient().ignoresSafeArea() }
        .navigationTitle("Cook with what I have")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search \(all.isEmpty ? "" : "\(all.count) ")recipes")
        .accessibilityIdentifier("cookbook.list")
        .task(id: stock.items.map(\.id)) { await refresh() }
    }

    private func refresh() async {
        let names = stockNames
        let prefs = prefs
        let (recipes, found) = await Task.detached(priority: .userInitiated) {
            let recipes = CookbookLibrary.recipes
            return (recipes, CookbookSuggester.suggestions(stock: names, recipes: recipes, prefs: prefs))
        }.value
        all = recipes.filter { $0.fits(prefs) }
        suggestions = found
        loading = false
    }

    private func row(_ recipe: CookbookRecipe, have: Int, missing: [CookbookRecipe.Line]) -> some View {
        NavigationLink {
            CookbookRecipeView(recipe: recipe)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.labelPrimary)
                Text(details(recipe, have: have)).font(.footnote).foregroundStyle(Color.labelSecondary)
                if !missing.isEmpty {
                    Text("Missing: " + missing.map { $0.terms.first ?? $0.text }.joined(separator: ", "))
                        .font(.footnote.weight(.medium)).foregroundStyle(Color.brandAmber)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("cookbook.recipe.\(recipe.id)")
    }

    private func details(_ recipe: CookbookRecipe, have: Int) -> String {
        var parts = ["\(have) of \(recipe.keyIngredients.count) in stock"]
        if let m = recipe.minutes { parts.append("\(m) min") }
        parts.append("\(Int(recipe.perServing.kcal)) kcal a serving")
        return parts.joined(separator: " · ")
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.surfaceGrouped : Color.labelPrimary)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(selected ? Color.labelPrimary : Color.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - One recipe

struct CookbookRecipeView: View {
    let recipe: CookbookRecipe
    @State private var stock = StockStore.shared
    @State private var showCooked = false
    @State private var addedToCart = false

    private var kitchen: KitchenMatcher { KitchenMatcher(names: stock.items.map(\.food.name)) }

    var body: some View {
        let missing = kitchen.missing(in: recipe)
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(recipe.title).font(.title2.weight(.bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.labelSecondary)
                    HStack(spacing: Spacing.sm) {
                        tile("\(Int(recipe.perServing.kcal))", "kcal")
                        tile("\(Int(recipe.perServing.protein.rounded())) g", "protein")
                        tile("\(Int(recipe.perServing.carbs.rounded())) g", "carbs")
                        tile("\(Int(recipe.perServing.fat.rounded())) g", "fat")
                    }
                    Text("A serving, estimated from USDA values for the ingredients.")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
                .padding(.vertical, Spacing.xs)
            }

            Section {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Image(systemName: symbol(for: line))
                            .foregroundStyle(color(for: line))
                            .frame(width: 20)
                        Text(line.text).font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(line.isPantry ? "kitchen basic" : kitchen.has(line) ? "in stock" : "missing")
                }
                if !missing.isEmpty {
                    Button {
                        for line in missing {
                            if let item = CookbookSuggester.catalogItem(for: line) { ShoppingCartService.shared.add(item, store: .catalog) }
                        }
                        addedToCart = true
                    } label: {
                        Label(addedToCart ? "Added to your cart" : "Add what's missing to the cart", systemImage: addedToCart ? "checkmark" : "cart.badge.plus")
                    }
                    .disabled(addedToCart)
                    .accessibilityIdentifier("cookbook.addMissing")
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text(missing.isEmpty ? "You have everything for this." : "\(missing.count) missing from My Stock.")
            }

            Section("Method") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text("\(i + 1)").font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Color.brandPrimary)
                            .frame(width: 22, alignment: .leading)
                        Text(step).font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button {
                    showCooked = true
                } label: {
                    Label("I cooked this", systemImage: "fork.knife")
                        .font(.headline)
                        .foregroundStyle(Color.surfaceGrouped)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.labelPrimary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(ScalePressStyle())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("cookbook.cooked")
            }

            Section { CookbookCredit(recipe: recipe) }
                .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCooked) { CookedRecipeSheet(recipe: recipe) }
    }

    private var subtitle: String {
        var parts: [String] = [recipe.course.title]
        let serves = recipe.servings.rounded() == recipe.servings ? "\(Int(recipe.servings))" : String(format: "%.1f", recipe.servings)
        parts.append(recipe.servingsEstimated ? "about \(serves) servings" : "serves \(serves)")
        if let m = recipe.minutes { parts.append("\(m) min") }
        return parts.joined(separator: " · ")
    }

    private func symbol(for line: CookbookRecipe.Line) -> String {
        if line.isPantry { return "circle.dashed" }
        return kitchen.has(line) ? "checkmark.circle.fill" : "cart"
    }

    private func color(for line: CookbookRecipe.Line) -> Color {
        if line.isPantry { return Color.labelSecondary }
        return kitchen.has(line) ? Color.green : Color.brandAmber
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

// MARK: - I cooked this

struct CookedRecipeSheet: View {
    let recipe: CookbookRecipe
    @Environment(\.dismiss) private var dismiss
    @State private var eaten = 1.0
    @State private var slot = MealSlot.suggested()
    @State private var useStock = true
    @State private var done: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $eaten, in: 0.5...6, step: 0.5) {
                        Text("You ate \(eaten.formatted()) serving\(eaten == 1 ? "" : "s")")
                    }
                    .accessibilityIdentifier("cookbook.eaten")
                    Picker("Meal", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                    Text("\(Int((recipe.perServing.kcal * eaten).rounded())) kcal · \(Int((recipe.perServing.protein * eaten).rounded())) g protein")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Log what you ate") }

                Section {
                    Toggle("Take the ingredients out of My Stock", isOn: $useStock)
                } footer: {
                    Text("Takes the whole recipe's amounts from the matching foods in stock. Kitchen basics are left alone.")
                }

                if let done {
                    Section { Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("I cooked this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { log() }.fontWeight(.semibold).accessibilityIdentifier("cookbook.log")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func log() {
        FoodLogStore.shared.add(FoodLogEntry(nutritionFood: recipe.servingFood, slot: slot, amount: eaten))
        if useStock { CookbookCooking.takeFromStock(recipe) }
        dismiss()
    }
}

enum CookbookCooking {
    /// Takes each key ingredient's grams from the first matching stock items (gram or
    /// millilitre foods only; a food counted in servings is left as it is).
    @discardableResult
    static func takeFromStock(_ recipe: CookbookRecipe, store: StockStore? = nil) -> [String] {
        let store = store ?? .shared
        var used: [String] = []
        for line in recipe.keyIngredients {
            guard var remaining = line.grams, remaining > 0 else { continue }
            let matching = store.items.filter { item in
                item.food.basis != .serving && KitchenMatcher(names: [item.food.name]).has(line)
            }.sorted { StockItem.expiryOrder($0, $1) }
            for item in matching where remaining > 0.5 {
                let take = min(remaining, item.amount)
                if item.amount - take < 0.5 { try? store.remove(id: item.id) }
                else { try? store.update(id: item.id, amount: item.amount - take, expiresAt: item.expiryDay()) }
                remaining -= take
                used.append(item.food.name)
            }
        }
        return used
    }
}

// MARK: - Credit (must stay: CC BY-SA 4.0)

struct CookbookCredit: View {
    let recipe: CookbookRecipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let recipe, let page = recipe.pageURL {
                Text("Recipe: “\(recipe.title)” from the Wikibooks Cookbook, by its contributors.")
                Link("Open the original page", destination: page)
            } else {
                Text("Recipes from the Wikibooks Cookbook, by its contributors.")
                Link("Wikibooks Cookbook", destination: URL(string: "https://en.wikibooks.org/wiki/Cookbook:Recipes")!)
            }
            Text("Adapted by Nourlo: amounts read into grams and nutrition estimated from USDA data.")
            Link("Licence: CC BY-SA 4.0", destination: CookbookLibrary.licenseURL)
        }
        .font(.caption)
        .foregroundStyle(Color.labelSecondary)
        .accessibilityIdentifier("cookbook.credit")
    }
}
