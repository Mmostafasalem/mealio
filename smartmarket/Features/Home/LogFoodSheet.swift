import SwiftUI

/// Source-backed food logging. Quick-add uses the explicitly displayed 100 g/ml basis;
/// the row opens the source and portion editor.
struct LogFoodSheet: View {

    @Bindable var vm: HomeViewModel
    var onSelect: ((NutritionFood, Double) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var slot: MealSlot = .suggested()
    @State private var query: String = ""
    @State private var addedToast: String?
    @State private var detailFood: NutritionFood?
    @State private var catalog = NutritionCatalogService.shared
    @State private var market: NutritionCatalogService.Market = .worldwide
    @State private var productPage = 0
    @State private var hasMoreProducts = false
    @State private var showCustomCreator = false
    @State private var pendingCustom: NutritionFood?
    @State private var products: [NutritionFood] = []
    @State private var productNotice: String?
    @State private var isSearching = false
    @State private var lookupTask: Task<Void, Never>?

    @FocusState private var searchFocused: Bool

    private var results: [NutritionFood] { catalog.searchLocal(query) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if onSelect == nil { slotPicker }
                searchField
                Picker("Product market", selection: $market) {
                    ForEach(NutritionCatalogService.Market.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("logFood.market")

                List {
                    if let error = catalog.loadError { Text(error).foregroundStyle(Color.brandDanger) }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !catalog.customFoods.isEmpty {
                            Section("Your dishes and restaurant entries") {
                                ForEach(catalog.customFoods) { food in
                                    row(food).swipeActions {
                                        Button("Delete", role: .destructive) { catalog.removeCustom(food.id) }
                                    }
                                }
                            }
                        }
                        if !vm.recentNutritionFoods.isEmpty {
                            Section("Recent foods") {
                                ForEach(vm.recentNutritionFoods) { food in row(food) }
                            }
                        }
                        Section("Food database") {
                            Text("Search \(catalog.foods.count.formatted()) reference foods offline, including prepared and restaurant-style dishes. Look up packaged products worldwide or by market.")
                            Text("Choose the description that matches what you weighed: raw, cooked, drained or prepared.")
                                .font(.footnote).foregroundStyle(Color.labelSecondary)
                        }
                        if onSelect == nil && !vm.plannedEntries(for: slot).isEmpty {
                            Section("From today's plan") {
                                ForEach(vm.plannedEntries(for: slot)) { entry in
                                    Text(entry.foodName).font(.subheadline)
                                }
                                Text("Meal-plan totals are estimates. Search and log each ingredient with the amount you ate to track sourced nutrition.")
                                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                            }
                        }
                    } else {
                        if !results.isEmpty {
                            Section("Offline foods and saved products") {
                                ForEach(results) { food in row(food) }
                                if results.count == 60 {
                                    Text("Showing the first 60 matches. Add preparation or ingredient details to narrow your search.")
                                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                                }
                            }
                        }
                        Section("Packaged products") {
                            Button { searchProducts() } label: {
                                Label(isSearching ? "Searching products…" : "Search Open Food Facts", systemImage: "magnifyingglass")
                            }
                            .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                            .accessibilityIdentifier("logFood.searchProducts")
                            Text("Sends only your search or barcode to Open Food Facts. Search runs when you tap; your profile and food log are not sent.")
                                .font(.footnote).foregroundStyle(Color.labelSecondary)
                            if isSearching { ProgressView() }
                            if let notice = productNotice { Text(notice).font(.footnote) }
                            ForEach(products) { food in row(food) }
                            if hasMoreProducts {
                                Button("Load more products") { searchProducts(loadMore: true) }
                                    .disabled(isSearching)
                                    .accessibilityIdentifier("logFood.loadMore")
                            }
                        }
                        if results.isEmpty && products.isEmpty && !isSearching {
                            Text("No local matches. Try an ingredient name in English, Lithuanian or Arabic, search products, or add the dish from its menu nutrition or ingredients.")
                                .font(.footnote).foregroundStyle(Color.labelSecondary)
                        }
                    }
                    Section {
                        Button("Add a recipe or restaurant dish") { showCustomCreator = true }
                            .accessibilityIdentifier("logFood.createDish")
                        Text("No database includes every restaurant or homemade recipe. Published menu entries can be saved per serving; recipes are calculated from their actual ingredients and final cooked weight.")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                    Section {
                        Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                        Link("Open Food Facts · ODbL database", destination: URL(string: "https://world.openfoodfacts.org/terms-of-use")!)
                        Text("Nutrition varies by product and preparation. Check the package label for the food you eat.")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(item: $detailFood) { food in
                    ServingDetailView(food: food, slot: slot, actionTitle: onSelect == nil ? nil : "Add to stock") { grams in
                        if let onSelect { onSelect(food, grams) }
                        else { vm.logFood(food, slot: slot, amount: grams) }
                        dismiss()
                    }
                }
            }
            .navigationTitle(onSelect == nil ? "Add Food" : "Add to Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCustomCreator = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a recipe or restaurant dish")
                        .accessibilityIdentifier("logFood.createDishToolbar")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showCustomCreator, onDismiss: {
                if let food = pendingCustom { detailFood = food; pendingCustom = nil }
            }) {
                CustomNutritionEntryView(catalog: catalog, market: market) { pendingCustom = $0 }
            }
            .overlay(alignment: .bottom) { toast }
            .onChange(of: query) {
                lookupTask?.cancel()
                products = []
                productNotice = nil
                isSearching = false
                productPage = 0
                hasMoreProducts = false
            }
            .onChange(of: market) {
                lookupTask?.cancel()
                products = []; productNotice = nil; isSearching = false
                productPage = 0; hasMoreProducts = false
            }
            .onDisappear { lookupTask?.cancel() }
            .onAppear {
                catalog.reloadSaved()
                slot = vm.logSheetSlot ?? .suggested()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Slot picker

    private var slotPicker: some View {
        Picker("Meal", selection: $slot) {
            ForEach(MealSlot.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
            TextField("Search foods", text: $query)
                .accessibilityIdentifier("logFood.search")
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchProducts() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.labelSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Row

    private func row(_ food: NutritionFood) -> some View {
        HStack(spacing: 12) {
            // Tapping the info area opens the serving detail (fine-tune → Add).
            Button {
                detailFood = food
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(slot.accent)
                        .frame(width: 34, height: 34)
                        .background(slot.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(Color.labelPrimary)
                        Text(food.subtitle)
                            .font(.caption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text("\(Int(food.kcal.rounded())) kcal / \(food.basis == .serving ? "serving" : "100 " + food.basis.rawValue)")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.labelSecondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("logFood.food." + food.id)

            // Quick-add at default serving (the 2-tap path).
            Button {
                quickAdd(food)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(slot.accent)
                    .minTapTarget()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(Int(food.defaultAmount)) \(food.basis.rawValue) of \(food.name)")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Toast

    @ViewBuilder private var toast: some View {
        if let msg = addedToast {
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Color.almond)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.rhino, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func quickAdd(_ food: NutritionFood) {
        if let onSelect {
            onSelect(food, food.defaultAmount)
            dismiss()
            return
        }
        vm.logFood(food, slot: slot, amount: food.defaultAmount)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Added \(Int(food.defaultAmount)) \(food.basis.rawValue) · \(food.name)")
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { addedToast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { addedToast = nil }
        }
    }

    private func searchProducts(loadMore: Bool = false) {
        guard !isSearching else { return }
        let submitted = query
        let submittedMarket = market
        let nextPage = loadMore ? productPage + 1 : 1
        isSearching = true
        productNotice = nil
        lookupTask = Task { @MainActor in
            do {
                let found = try await catalog.fetchProducts(submitted, market: submittedMarket, page: nextPage)
                guard !Task.isCancelled, submitted == query, submittedMarket == market else { return }
                if loadMore {
                    let existing = Set(products.map(\.id))
                    products += found.foods.filter { !existing.contains($0.id) }
                } else { products = found.foods }
                productPage = nextPage
                hasMoreProducts = found.hasMore
                productNotice = found.foods.isEmpty ? (found.hasMore ? "No usable nutrition on this page. Load more products or narrow your search." : "No usable products on this page. Check the barcode or try another name.") : nil
            } catch {
                guard !Task.isCancelled, submitted == query, submittedMarket == market else { return }
                productNotice = (error as? LocalizedError)?.errorDescription ?? "Product search is unavailable. Offline foods and saved products still work."
            }
            isSearching = false
        }
    }

}

// MARK: - Serving detail (fine-tune grams before logging)

struct ServingDetailView: View {
    let food: NutritionFood
    let slot: MealSlot
    let actionTitle: String?
    let onAdd: (Double) -> Void

    @State private var grams: Double
    @State private var didAdd = false

    init(food: NutritionFood, slot: MealSlot, actionTitle: String? = nil, onAdd: @escaping (Double) -> Void) {
        self.food = food
        self.slot = slot
        self.onAdd = onAdd
        self.actionTitle = actionTitle
        _grams = State(initialValue: food.defaultAmount)
    }

    private var factor: Double { grams / food.referenceAmount }
    private var kcal: Int { Int((food.kcal * factor).rounded()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Calorie hero for this serving
                VStack(spacing: 4) {
                    Text("\(kcal)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.labelPrimary).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("kcal · \(grams.formatted(.number.precision(.fractionLength(0...2)))) \(food.basis.rawValue)").font(.subheadline).foregroundStyle(Color.labelSecondary)
                    Text(food.brand ?? "Match the food's preparation to your portion")
                        .font(.subheadline).foregroundStyle(Color.labelSecondary)

                }
                .padding(.top, 12)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: grams)

                // Macro chips
                HStack(spacing: 10) {
                    macroChip("Protein", food.protein * factor, .proteinAccent)
                    macroChip("Carbs", food.carbs * factor, .carbsAccent)
                    macroChip("Fat", food.fat * factor, .fatAccent)
                }

                // Serving stepper
                VStack(spacing: 12) {
                    HStack {
                        Text("Serving").font(.headline)
                        Spacer()
                        Text("\(grams.formatted(.number.precision(.fractionLength(0...2)))) \(food.basis.rawValue)").font(.headline).monospacedDigit()
                    }
                    Stepper(value: $grams, in: food.minimumAmount...food.maximumAmount, step: food.basis == .serving ? 0.25 : 1) {
                        Text(food.basis == .serving ? "Number of servings" : "Amount in " + (food.basis == .grams ? "grams" : "millilitres"))
                    }
                    .accessibilityIdentifier("logFood.amount")
                    Slider(value: $grams, in: food.minimumAmount...food.maximumAmount, step: food.basis == .serving ? 0.25 : 1)
                        .tint(slot.accent)
                    HStack(spacing: 8) {
                        ForEach(food.basis == .serving ? [1, 2, 3, 4] : [50, 100, 150, 200], id: \.self) { preset in
                            Button("\(preset) \(food.basis.rawValue)") { grams = Double(preset) }
                                .font(.caption).fontWeight(.semibold)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.surfaceElevated, in: Capsule())
                        }
                    }
                }
                .padding(16)
                .premiumCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text(food.sourceName).font(.headline)
                    if food.source == .openFoodFacts, let date = food.sourceDate {
                        Text("Retrieved \(date)").font(.caption).foregroundStyle(Color.labelSecondary)
                    }
                    Text("\(food.referenceLabel): \(food.kcal.formatted(.number.precision(.fractionLength(0...1)))) kcal · Protein \(food.protein.formatted()) g · Carbs \(food.carbs.formatted()) g · Fat \(food.fat.formatted()) g")
                        .font(.footnote)
                    if let url = food.sourceURL { Link("View original nutrition record", destination: url) }
                    if let recipe = food.recipeDetails {
                        Text("Final weighed yield: \(recipe.cookedYieldG.formatted()) g").font(.footnote)
                        ForEach(recipe.ingredients) { ingredient in
                            Text("\(ingredient.food.name) · \(ingredient.amount.formatted()) \(ingredient.food.basis.rawValue)")
                                .font(.footnote)
                        }
                    }
                    Text(food.sourceExplanation)
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("logFood.source")
            }
            .padding(16)
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            LoadingSuccessButton(
                title: actionTitle ?? "Add to \(slot.title)",
                doneTitle: "Added",
                systemImage: "plus"
            ) {
                guard !didAdd else { return false }
                didAdd = true
                return true
            } onFinished: {
                // Close after the success moment.
                onAdd(grams)
            }
            .disabled(didAdd)
            .accessibilityIdentifier("logFood.addServing")
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    private func macroChip(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
