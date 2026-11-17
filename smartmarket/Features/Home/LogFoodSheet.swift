import SwiftUI
import TipKit

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
    /// Products are searched worldwide (the market switch was removed on 16 Nov 2026).
    private let market: NutritionCatalogService.Market = .worldwide
    @State private var productPage = 0
    @State private var hasMoreProducts = false
    @State private var showCustomCreator = false
    @State private var pendingCustom: NutritionFood?
    @State private var products: [NutritionFood] = []
    @State private var productNotice: String?
    @State private var isSearching = false
    @State private var lookupTask: Task<Void, Never>?
    /// Looks up packaged products a moment after typing stops (on unless turned off here).
    @AppStorage("autoProductSearch_v1") private var autoProductSearch = true
    @State private var autoSearchTask: Task<Void, Never>?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var showScanner = false
    @State private var scanned: ScannedBarcode?
    @State private var scanState: ScanState = .idle
    @State private var scanTask: Task<Void, Never>?
    @State private var scanOpenTask: Task<Void, Never>?
    private let scanTip = ScanBarcodeTip()

    /// Where a barcode lookup stands; shown at the top of the list.
    private enum ScanState: Equatable {
        case idle
        case looking(String)
        case noMatch(String)
        case failed(String, String)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var results: [NutritionFood] { catalog.searchLocal(query) }
    /// Wikibooks recipes, read in the background when the sheet opens.
    @State private var cookbook: [CookbookRecipe] = []
    /// The sheet's one-time setup (meal slot) has run; pushes and pops don't redo it.
    @State private var didSetUp = false
    private var recipeResults: [CookbookRecipe] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard onSelect == nil, q.count >= 2 else { return [] }
        return Array(cookbook.filter { $0.title.localizedStandardContains(q) }.prefix(8))
    }

    /// The first offline match whose name starts with what was typed, offered as ghost text.
    private var suggestion: String? {
        guard query.count >= 2, !query.hasSuffix("  ") else { return nil }
        return results.first { GhostSuggestionField.remainder(of: $0.name, after: query) != nil }?.name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if onSelect == nil { slotPicker }
                searchField
                List {
                    if let error = catalog.loadError { Text(error).foregroundStyle(Color.brandDanger) }
                    if scanState != .idle { scanSection }
                    if BarcodeScannerView.shouldOffer && scanState == .idle {
                        TipView(scanTip, arrowEdge: .top)
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                            .listRowBackground(Color.clear)
                    }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if onSelect == nil {
                            Section {
                                NavigationLink {
                                    CookbookBrowserView(slot: slot)
                                } label: {
                                    Label("Browse Wikibooks recipes", systemImage: "book")
                                }
                                .accessibilityIdentifier("logFood.browseRecipes")
                            } footer: {
                                Text("\(cookbook.isEmpty ? "About 1,500" : "\(cookbook.count)") recipes, logged per serving. Nutrition is estimated from USDA values for the ingredients.")
                            }
                        }
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
                        if !recipeResults.isEmpty {
                            Section("Wikibooks recipes") {
                                ForEach(recipeResults) { recipe in row(recipe.servingFood) }
                            }
                        }
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
                            Toggle("Look up products as I type", isOn: $autoProductSearch)
                                .toggleStyle(.spring)
                                .accessibilityIdentifier("logFood.autoProducts")
                            Button { searchProducts() } label: {
                                Label(isSearching ? "Searching products…" : "Search Open Food Facts now", systemImage: "magnifyingglass")
                            }
                            .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                            .accessibilityIdentifier("logFood.searchProducts")
                            Text(autoProductSearch
                                 ? "A moment after you stop typing, your search text (and nothing else) is sent to Open Food Facts to find packaged products. Your profile and food log are never sent. Turn this off to search only when you tap."
                                 : "Sends only your search or barcode to Open Food Facts, and only when you tap. Your profile and food log are not sent.")
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
                    ServingDetailView(food: food, slot: slot, actionTitle: onSelect == nil ? nil : "Add to stock",
                                      slotSelection: onSelect == nil ? $slot : nil) { grams in
                        // A scanned or searched product is saved only once it's actually used
                        // (`HomeViewModel.logFood` saves it when logging).
                        if let onSelect { catalog.remember(food); onSelect(food, grams) }
                        else { vm.logFood(food, slot: slot, amount: grams); LogFoodTip().invalidate(reason: .actionPerformed) }
                        dismiss()
                    }
                }
            }
            .task {
                guard onSelect == nil, cookbook.isEmpty else { return }
                let prefs = Set<DietaryPreference>.load()
                cookbook = await Task.detached(priority: .utility) { CookbookLibrary.recipes.filter { $0.fits(prefs) } }.value
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
            .sheet(isPresented: $showScanner, onDismiss: {
                if let code = scanned { scanned = nil; lookUp(code) }
            }) {
                BarcodeScannerSheet { scanned = $0 }
            }
            .overlay(alignment: .bottom) { toast }
            .onChange(of: query) {
                lookupTask?.cancel()
                products = []
                productNotice = nil
                isSearching = false
                productPage = 0
                hasMoreProducts = false
                scheduleAutoProductSearch()
            }
            .onChange(of: autoProductSearch) { scheduleAutoProductSearch() }
            .onDisappear { lookupTask?.cancel(); autoSearchTask?.cancel(); scanTask?.cancel(); scanOpenTask?.cancel() }
            .onAppear {
                // Also fires when coming back from a pushed food or the recipe browser:
                // the meal chosen here stays, and a search that leaving cancelled is reset.
                if isSearching { isSearching = false }
                guard !didSetUp else { return }
                didSetUp = true
                // Brings "From today's plan" to today if the day has changed.
                vm.activate()
                catalog.reloadSaved()
                slot = vm.logSheetSlot ?? .suggested()
                // Opened from a "Scan" widget, control or shortcut: start with the camera.
                takeScanRequest()
            }
            // A scan request while the logger is already open.
            .onChange(of: AppRouter.shared.scanRequestID) { _, _ in takeScanRequest() }
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
            // Letters land with a bounce; a matching food name is offered as ghost text.
            GhostSuggestionField(
                placeholder: "Search foods",
                text: $query,
                suggestion: suggestion,
                accessibilityIdentifier: "logFood.search",
                returnKey: .search,
                acceptIdentifier: "logFood.acceptSuggestion"
            ) {
                searchProducts()
                return true
            }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.labelSecondary)
                }
                .accessibilityLabel("Clear search")
            }
            if BarcodeScannerView.shouldOffer {
                Button { openScanner() } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .minTapTarget()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan barcode")
                .accessibilityHint("Reads a package barcode with the camera")
                .accessibilityIdentifier("logFood.scan")
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
            .accessibilityLabel("Add \(Self.amountText(food.defaultAmount, basis: food.basis)) of \(food.name)")
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
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func quickAdd(_ food: NutritionFood) {
        if let onSelect {
            catalog.remember(food)
            onSelect(food, food.defaultAmount)
            dismiss()
            return
        }
        vm.logFood(food, slot: slot, amount: food.defaultAmount)
        LogFoodTip().invalidate(reason: .actionPerformed)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Added \(Self.amountText(food.defaultAmount, basis: food.basis)) · \(food.name)")
    }

    /// "0.5 serving", "2 servings", "100 g", "250 ml": no truncation, no
    /// trailing zeros.
    static func amountText(_ amount: Double, basis: NutritionFood.Basis, locale: Locale = .current) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        switch basis {
        case .serving: return "\(number) \(amount > 1 ? "servings" : "serving")"
        case .grams, .millilitres: return "\(number) \(basis.rawValue)"
        }
    }

    private func showToast(_ message: String) {
        // Cancel the previous dismiss so a second add isn't cleared early.
        toastDismissTask?.cancel()
        withAnimation(.snappyValue) { addedToast = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappyValue) { addedToast = nil }
        }
    }

    // MARK: - Barcode

    @ViewBuilder private var scanSection: some View {
        Section("Barcode") {
            switch scanState {
            case .idle:
                EmptyView()
            case .looking(let code):
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking up \(code)…").font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            case .noMatch(let code):
                Text("No match for \(code). Enter it yourself.")
                    .font(.subheadline)
                    .accessibilityIdentifier("logFood.scanNoMatch")
                scanFollowUps
            case .failed(_, let message):
                Text(message).font(.subheadline)
                scanFollowUps
            }
        }
    }

    @ViewBuilder private var scanFollowUps: some View {
        Button("Enter it yourself") { scanState = .idle; showCustomCreator = true }
            .accessibilityIdentifier("logFood.scanManual")
        if BarcodeScannerView.shouldOffer {
            Button("Scan again") { openScanner() }
        }
    }

    private func openScanner() {
        scanTip.invalidate(reason: .actionPerformed)
        scanTask?.cancel()
        scanState = .idle
        showScanner = true
    }

    /// Opens the scanner for a fresh scan request from a widget, control or
    /// shortcut. Only the food logger takes it ("Add to stock" leaves it to
    /// expire). The camera opens once this sheet has finished presenting, so the
    /// nested sheet isn't dropped.
    private func takeScanRequest() {
        guard onSelect == nil, AppRouter.shared.consumeScanRequest(), BarcodeScannerView.shouldOffer else { return }
        guard !showScanner else { return }
        // A sheet already up over the logger would block the scanner's sheet.
        showCustomCreator = false
        scanOpenTask?.cancel()
        scanOpenTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, !showScanner else { return }
            openScanner()
        }
    }

    private func lookUp(_ code: ScannedBarcode) {
        scanTask?.cancel()
        let shown = GTIN.normalize(code.payload, symbology: code.symbology) ?? code.payload
        scanState = .looking(shown)
        scanTask = Task { @MainActor in
            let outcome = await BarcodeLookupService.shared.lookup(code.payload, symbology: code.symbology)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .found(let food):
                scanState = .idle
                // The same serving editor as a tapped search result; the product is
                // saved only if it is logged.
                detailFood = food
            case .notFound(let found):
                scanState = .noMatch(found)
                UIAccessibility.post(notification: .announcement, argument: "No match for this barcode. Enter it yourself.")
            case .invalidCode(let raw):
                scanState = .failed(raw, "That isn't a product barcode. Try again, or enter it yourself.")
            case .failed(let failedCode, let message):
                scanState = .failed(failedCode, message)
            }
        }
    }

    /// How long typing must pause before products are looked up.
    static let autoSearchPause: TimeInterval = 1.2

    /// Whether a query is worth sending by itself: three letters or more, and
    /// not a half-typed barcode (those are looked up when complete, on a tap or a scan).
    static func isAutoSearchable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 100 else { return false }
        return !trimmed.allSatisfy { $0.isNumber || $0.isWhitespace }
    }

    /// Looks up packaged products once typing has paused, never faster than
    /// Open Food Facts allows. A newer keystroke replaces the pending search.
    private func scheduleAutoProductSearch() {
        autoSearchTask?.cancel()
        // UI tests stay offline and deterministic.
        guard autoProductSearch, !NourloTips.isUITesting(), Self.isAutoSearchable(query) else { return }
        let submitted = query
        let submittedMarket = market
        autoSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.autoSearchPause))
            // Wait out the spacing between searches instead of failing with "please wait".
            while !Task.isCancelled, catalog.secondsUntilNextSearch > 0 {
                try? await Task.sleep(for: .seconds(min(catalog.secondsUntilNextSearch + 0.05, 1)))
            }
            guard !Task.isCancelled, submitted == query, submittedMarket == market, products.isEmpty, !isSearching else { return }
            searchProducts()
        }
    }

    private func searchProducts(loadMore: Bool = false) {
        guard !isSearching else { return }
        autoSearchTask?.cancel()
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
    let actionTitle: String?
    /// When set, the meal can be changed here (spring dropdown) and is written back.
    let slotSelection: Binding<MealSlot>?
    let onAdd: (Double) -> Void

    @State private var grams: Double
    @State private var slot: MealSlot
    @State private var didAdd = false

    init(food: NutritionFood, slot: MealSlot, actionTitle: String? = nil,
         slotSelection: Binding<MealSlot>? = nil, onAdd: @escaping (Double) -> Void) {
        self.food = food
        self.onAdd = onAdd
        self.actionTitle = actionTitle
        self.slotSelection = slotSelection
        _grams = State(initialValue: food.defaultAmount)
        _slot = State(initialValue: slotSelection?.wrappedValue ?? slot)
    }

    private var factor: Double { grams / food.referenceAmount }

    // Portion stepper: whole steps of 0.25 serving or 1 g / ml, same as before.
    private var amountStep: Double { food.basis == .serving ? 0.25 : 1 }
    private var amountStepRange: ClosedRange<Int> {
        Int((food.minimumAmount / amountStep).rounded())...Int((food.maximumAmount / amountStep).rounded())
    }
    private var amountSteps: Binding<Int> {
        Binding(
            get: { Int((grams / amountStep).rounded()) },
            set: { grams = Double($0) * amountStep }
        )
    }
    private var amountLabel: String {
        food.basis == .serving ? "Number of servings" : "Amount in " + (food.basis == .grams ? "grams" : "millilitres")
    }
    private func formatAmount(_ amount: Double) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        // Servings say "1×" so the number fits beside the stepper ("1 serving" didn't).
        return food.basis == .serving ? "\(number)×" : "\(number) \(food.basis.rawValue)"
    }
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

                if slotSelection != nil { mealPicker }

                // Serving stepper
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Serving").font(.headline)
                            Text(amountLabel)
                                .font(.caption).foregroundStyle(Color.labelSecondary)
                        }
                        Spacer(minLength: 8)
                        SpringStepper(
                            value: amountSteps,
                            in: amountStepRange,
                            format: { formatAmount(Double($0) * amountStep) },
                            label: amountLabel,
                            decrementLabel: "Less",
                            incrementLabel: "More",
                            font: .system(.headline, design: .rounded).weight(.bold)
                        )
                        .accessibilityIdentifier("logFood.amount")
                    }
                    RulerPicker(value: $grams, range: food.minimumAmount...food.maximumAmount, step: amountStep,
                                majorEvery: food.basis == .serving ? 4 : 10,
                                midEvery: food.basis == .serving ? 2 : 5,
                                spacing: food.basis == .serving ? 16 : 8,
                                accessibilityName: "Amount", spokenValue: { formatAmount($0) })
                        .frame(height: 96)
                    HStack(spacing: 8) {
                        ForEach(food.basis == .serving ? [1, 2, 3, 4] : [50, 100, 150, 200], id: \.self) { preset in
                            Button(food.basis == .serving ? "\(preset)×" : "\(preset) \(food.basis.rawValue)") { grams = Double(preset) }
                                .accessibilityLabel(food.basis == .serving ? "\(preset) serving\(preset == 1 ? "" : "s")" : "\(preset) \(food.basis.rawValue)")
                                .font(.caption).fontWeight(.semibold)
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.surfaceElevated, in: Capsule())
                        }
                        Spacer(minLength: 0)
                        TypeNumberButton(title: "Amount", unit: food.basis.rawValue,
                                         current: formatAmount(grams), identifier: "logFood.amount.type") { text in
                            if let n = TypedNumber.parse(text) {
                                grams = TypedNumber.fitted(n, range: food.minimumAmount...food.maximumAmount, step: amountStep)
                            }
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
                    if let url = food.sourceURL { Link(food.source == .cookbook ? "Open the recipe on Wikibooks (CC BY-SA 4.0)" : "View original nutrition record", destination: url) }
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
        .onChange(of: slot) { _, s in slotSelection?.wrappedValue = s }
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

    /// Which meal this serving goes to. Replaces a plain picker with the spring dropdown;
    /// it sits above the cards below so its menu can drop over them.
    private var mealPicker: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meal").font(.headline)
                Text("Choose where this serving is logged")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Spacer(minLength: 8)
            SpringDropdown(title: "Meal", selection: $slot, options: MealSlot.allCases,
                           label: \.title, systemImage: \.sfSymbol,
                           accessibilityIdentifier: "logFood.mealSlot")
                .frame(maxWidth: 200)
        }
        .padding(16)
        .premiumCard()
        .zIndex(1)
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
