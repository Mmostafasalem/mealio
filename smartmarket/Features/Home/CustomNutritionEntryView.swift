import SwiftUI

/// Missing dishes are entered from real menu figures or calculated ingredients, never guessed by name.
struct CustomNutritionEntryView: View {
    @Bindable var catalog: NutritionCatalogService
    let market: NutritionCatalogService.Market
    let onSave: (NutritionFood) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: String?
    @State private var mode = 0
    @State private var name = ""
    @State private var restaurant = ""
    @State private var energy = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var menuLink = ""
    @State private var yield = ""
    @State private var ingredients: [NutritionIngredient] = []
    @State private var showIngredients = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Dish type", selection: $mode) {
                    Text("Recipe").tag(0)
                    Text("Restaurant menu").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("customFood.mode")
                Section("Dish") {
                    TextField("Dish name", text: $name).focused($focusedField, equals: "customFood.name").accessibilityIdentifier("customFood.name")
                    if mode == 1 {
                        TextField("Restaurant name", text: $restaurant).focused($focusedField, equals: "customFood.restaurant").accessibilityIdentifier("customFood.restaurant")
                    }
                }
                if mode == 0 {
                    // The action comes first: on iOS 26 the keyboard's floating
                    // "Done" pill owns a full-width, invisible strip above the
                    // keyboard, so a row placed lower is unreachable while a
                    // field is focused.
                    Section {
                        Button("Add ingredient") { focusedField = nil; showIngredients = true }
                            .disabled(ingredients.count >= 50)
                            .accessibilityIdentifier("customFood.addIngredient")
                        ForEach($ingredients) { $ingredient in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ingredient.food.name).font(.subheadline)
                                Text(ingredient.food.sourceName).font(.caption).foregroundStyle(Color.labelSecondary)
                                HStack {
                                    Text("Amount (\(ingredient.food.basis.rawValue))")
                                    Spacer()
                                    TextField("Amount", value: $ingredient.amount, format: .number)
                                        .focused($focusedField, equals: ingredient.id.uuidString)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                }
                            }
                        }.onDelete { ingredients.remove(atOffsets: $0) }
                    } header: { Text("Ingredients") } footer: {
                        Text("Add the ingredients and amounts you actually used, including oils and sauces. Match raw/cooked descriptions to when you weighed them.")
                    }
                    Section {
                        TextField("Final cooked weight (g)", text: $yield).keyboardType(.decimalPad)
                            .focused($focusedField, equals: "customFood.yield")
                            .accessibilityIdentifier("customFood.yield")
                        Text("Weigh the finished edible dish, without the pot. The app divides the ingredients' total nutrition by this yield; cooking water changes weight, not the ingredients' total calories. Discarded oil or cooking liquid can affect the estimate.")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    } header: { Text("Final dish yield") }
                } else {
                    Section("Published nutrition per restaurant serving") {
                        numericField("Calories (kcal)", text: $energy, id: "customFood.energy")
                        numericField("Protein (g)", text: $protein, id: "customFood.protein")
                        numericField("Carbohydrate (g)", text: $carbs, id: "customFood.carbs")
                        numericField("Fat (g)", text: $fat, id: "customFood.fat")
                        TextField("Menu link (optional, HTTPS)", text: $menuLink)
                            .focused($focusedField, equals: "customFood.link")
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Text("Copy all four values from the restaurant's current menu or nutrition sheet. Unknown is not zero. This saves one menu serving; you can log a fraction later. Nourlo labels these as entered by you, not independently verified.")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                }
                if let error { Text(error).foregroundStyle(Color.brandDanger).accessibilityIdentifier("customFood.error") }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add a dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.accessibilityIdentifier("customFood.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }.accessibilityIdentifier("customFood.keyboardDone")
                }
            }
            .sheet(isPresented: $showIngredients) {
                NutritionIngredientPicker(catalog: catalog, market: market) {
                    ingredients.append(NutritionIngredient(food: $0, amount: $0.defaultAmount))
                }
            }
        }
    }
    private func numericField(_ title: String, text: Binding<String>, id: String) -> some View {
        TextField(title, text: text).focused($focusedField, equals: id).keyboardType(.decimalPad).accessibilityIdentifier(id)
    }
    private func number(_ input: String) -> Double? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).map { character -> String in
            if let digit = character.wholeNumberValue { return String(digit) }
            if character == "," || character == "٫" { return "." }
            return String(character)
        }.joined()
        return Double(normalized)
    }
    private func save() {
        focusedField = nil
        do {
            let food: NutritionFood
            if mode == 0 {
                guard let weight = number(yield) else { throw NutritionEntryError.invalidRecipe }
                food = try NutritionFood.makeRecipe(name: name, ingredients: ingredients, cookedYieldG: weight)
            } else {
                guard let kcal = number(energy), let p = number(protein), let c = number(carbs), let f = number(fat)
                else { throw NutritionEntryError.invalidMenu }
                food = try NutritionFood.makeMenuFood(name: name, restaurant: restaurant, kcal: kcal, protein: p, carbs: c, fat: f, sourceURL: menuLink)
            }
            try catalog.saveCustom(food)
            onSave(food)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct NutritionIngredientPicker: View {
    @Bindable var catalog: NutritionCatalogService
    let market: NutritionCatalogService.Market
    let select: (NutritionFood) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var products: [NutritionFood] = []
    @State private var task: Task<Void, Never>?
    @State private var loading = false
    @State private var notice: String?
    private var local: [NutritionFood] {
        catalog.searchIngredients(query)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search ingredients", text: $query).autocorrectionDisabled()
                        .focused($searchFocused)
                        .accessibilityIdentifier("customFood.ingredientSearch")
                }
                ForEach(local) { ingredientRow($0) }
                if query.count >= 2 {
                    Section("Packaged ingredients · \(market.title)") {
                        Button(loading ? "Searching…" : "Search packaged ingredients") { search() }.disabled(loading)
                        Text("Sends only this ingredient query and selected market to Open Food Facts.").font(.footnote)
                        if let notice { Text(notice).font(.footnote) }
                        ForEach(products) { ingredientRow($0) }
                        if hasMore {
                            Button("Load more ingredients") { search(loadMore: true) }.disabled(loading)
                        }
                    }
                } else {
                    Text("Search a food in English, Lithuanian or Arabic. Choose the exact description before entering its amount.")
                }
            }
            .navigationTitle("Choose ingredient")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: query) { task?.cancel(); products = []; loading = false; notice = nil; page = 0; hasMore = false }
            .task { searchFocused = true }
            .onDisappear { searchFocused = false; task?.cancel() }
        }
    }
    private func ingredientRow(_ food: NutritionFood) -> some View {
        Button {
            catalog.remember(food)
            select(food)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                Text(food.subtitle + " · " + food.sourceName).font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }.accessibilityIdentifier("customFood.ingredient." + food.id)
    }
    private func search(loadMore: Bool = false) {
        let input = query
        let requestedPage = loadMore ? page + 1 : 1
        loading = true; notice = nil
        task = Task { @MainActor in
            do {
                let found = try await catalog.fetchProducts(input, market: market, page: requestedPage)
                guard !Task.isCancelled, input == query else { return }
                if loadMore {
                    let ids = Set(products.map(\.id))
                    products += found.foods.filter { !ids.contains($0.id) }
                } else { products = found.foods }
                page = requestedPage
                hasMore = found.hasMore
                if found.foods.isEmpty {
                    notice = found.hasMore ? "No usable nutrition on this page. Load more results or narrow the search." : "No usable products on this page. Try another term or the offline references."
                }
            } catch {
                guard !Task.isCancelled, input == query else { return }
                notice = error.localizedDescription
            }
            loading = false
        }
    }
}
