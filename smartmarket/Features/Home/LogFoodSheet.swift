import SwiftUI
import TipKit

/// Source-backed food logging. Quick-add uses the explicitly displayed 100 g/ml basis;
/// the row opens the source and portion editor.
struct LogFoodSheet: View {

    @Bindable var vm: HomeViewModel
    var onSelect: ((NutritionFood, Double) -> Void)? = nil
    /// With `onSelect`: the foods are picked for something else (a meal photo), not added to stock.
    var pickTitle: String? = nil
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
    @State private var pending = PendingMealStore.shared
    @State private var clarifying: PendingMeal?
    @State private var showRecipeImport = false
    @State private var showPhoto = false
    @State private var stock = StockStore.shared

    /// Where a barcode lookup stands; shown at the top of the list.
    private enum ScanState: Equatable {
        case idle
        case looking(String)
        case noMatch(String)
        case failed(String, String)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Offline matches for the current text: searched once per change, not on every redraw.
    @State private var results: [NutritionFood] = []
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
                        if onSelect == nil && !pending.meals.isEmpty {
                            Section {
                                ForEach(pending.meals) { meal in
                                    Button { clarifying = meal } label: { PendingMealRow(meal: meal) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("logFood.toClarify")
                                }
                            } header: {
                                Label("To clarify", systemImage: "camera.viewfinder")
                            } footer: {
                                Text("Meal photos you saved for later. Tap one to say what was in it.")
                            }
                        }
                        if onSelect == nil {
                            Section {
                                Button { showRecipeImport = true } label: {
                                    Label("Add a recipe I'm following", systemImage: "text.book.closed")
                                }
                                .accessibilityIdentifier("logFood.addRecipe")
                                NavigationLink {
                                    CookbookBrowserView(slot: slot)
                                } label: {
                                    Label("Browse Wikibooks recipes", systemImage: "book")
                                }
                                .accessibilityIdentifier("logFood.browseRecipes")
                            } footer: {
                                Text("Paste, link or photograph a recipe you're cooking and Nourlo works out a serving. Or log one of \(cookbook.isEmpty ? "about 1,500" : "\(cookbook.count)") Wikibooks recipes per serving. Nutrition is estimated from USDA values for the ingredients." as String)
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
                                    planRow(entry)
                                }
                                Text("One tap logs the planned portions of each food and takes them out of My Stock where you have them.")
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
                .scrollDismissesKeyboard(.immediately)
                .navigationDestination(item: $detailFood) { food in
                    ServingDetailView(food: food, slot: slot, actionTitle: onSelect == nil ? nil : (pickTitle ?? "Add to stock"),
                                      stocking: onSelect != nil && pickTitle == nil,
                                      slotSelection: onSelect == nil ? $slot : nil) { food, grams, kcal in
                        // A scanned or searched product is saved only once it's actually used
                        // (`HomeViewModel.logFood` saves it when logging). Going to stock, it
                        // carries the package size and pieces set on the screen.
                        if let onSelect { catalog.remember(food); onSelect(food, grams) }
                        else { vm.logFood(food, slot: slot, amount: grams, kcal: kcal); LogFoodTip().invalidate(reason: .actionPerformed) }
                        dismiss()
                    }
                }
            }
            .task {
                guard onSelect == nil, cookbook.isEmpty else { return }
                let prefs = Set<DietaryPreference>.load()
                cookbook = await Task.detached(priority: .utility) { CookbookLibrary.recipes.filter { $0.fits(prefs) } }.value
            }
            .navigationTitle(onSelect == nil ? "Add Food" : pickTitle == nil ? "Add to Stock" : "Choose a food")
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
            .sheet(isPresented: $showRecipeImport) {
                RecipeImportSheet(slot: slot) { showRecipeImport = false }
            }
            .sheet(isPresented: $showPhoto) {
                VoiceCommandSheet(photoMode: true, close: { showPhoto = false }, navigate: { _ in showPhoto = false })
            }
            .sheet(item: $clarifying) { meal in
                ClarifyMealSheet(meal: meal) { clarifying = nil }
            }
            .sheet(isPresented: $showScanner, onDismiss: {
                if let code = scanned { scanned = nil; lookUp(code) }
            }) {
                BarcodeScannerSheet { scanned = $0 }
            }
            .overlay(alignment: .bottom) { toast }
            .task(id: query) {
                // A short pause while typing fast, then one search of the catalogue.
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
                guard !Task.isCancelled else { return }
                results = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : catalog.searchLocal(query)
            }
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
                accessibilityIdentifier: pickTitle == nil ? "logFood.search" : "pickFood.search",
                returnKey: .search,
                acceptIdentifier: "logFood.acceptSuggestion"
            ) {
                searchProducts()
                return true
            }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.labelSecondary)
                        .minTapTarget()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            // A meal photo: online AI names the foods when it's offered; otherwise (or if you
            // don't finish now) the photo waits under "To clarify".
            if onSelect == nil {
                Button { showPhoto = true } label: {
                    Image(systemName: "camera.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .minTapTarget()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Snap a meal")
                .accessibilityHint(MealPhotoAccess.isUsable ? "Online AI names the foods in a photo of your meal" : "Saves a photo of your meal to clarify later")
                .accessibilityIdentifier("logFood.photo")
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
                        Text(food.source == .usda ? "\(food.subtitle) · \(food.dataset == "survey" ? "as eaten" : food.dataset == "foundation" ? "lab-measured" : "reference")" : food.subtitle)
                            .font(.caption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text("\(Int(food.kcal.rounded())) kcal / \(food.basis == .serving ? "serving" : "100 " + food.basis.rawValue)" as String)
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
        let summary = stock.summary(for: food, amount: food.defaultAmount)
        guard vm.logFood(food, slot: slot, amount: food.defaultAmount) else {
            showToast("Couldn't add \(food.name)")
            return
        }
        LogFoodTip().invalidate(reason: .actionPerformed)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Added \(Self.amountText(food.defaultAmount, basis: food.basis)) · \(food.name)"
                  + (summary.inStock ? " · from your stock" : ""))
    }

    /// A planned meal, logged in one tap: each food's planned portion (taken out of My Stock
    /// where it's there), or opened in the review when it has no portions.
    private func planRow(_ entry: MealEntry) -> some View {
        let ingredients = entry.nutritionIngredients ?? []
        let inStock = ingredients.filter { stock.summary(for: $0.food, amount: $0.amount).inStock }.count
        return Button {
            guard !ingredients.isEmpty else { return }
            var logged = 0
            for ingredient in ingredients where vm.logFood(ingredient.food, slot: slot, amount: ingredient.amount) { logged += 1 }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showToast(logged == 0 ? "Couldn't log \(entry.foodName)" : "Logged \(entry.foodName) · \(entry.calories) kcal"
                      + (inStock > 0 ? " · from your stock" : ""))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(slot.accent)
                    .frame(width: 34, height: 34)
                    .background(slot.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.foodName).font(.subheadline.weight(.medium)).foregroundStyle(Color.labelPrimary)
                    Text(ingredients.isEmpty ? "No portions to log" : "\(entry.calories) kcal · \(inStock) of \(ingredients.count) in your stock" as String)
                        .font(.caption2).foregroundStyle(Color.labelSecondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(ingredients.isEmpty ? Color.labelTertiary : slot.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ingredients.isEmpty)
        .accessibilityLabel("Log \(entry.foodName), \(entry.calories) kcal" as String)
        .accessibilityIdentifier("logFood.plan")
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
                    Text("Looking up \(code)…" as String).font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            case .noMatch(let code):
                Text("No match for \(code). Enter it yourself." as String)
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
        // A typed barcode takes the scanner's path: check digit, UPC as 13 digits, the same parsing.
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loadMore, (8...14).contains(typed.count), typed.allSatisfy({ $0.isASCII && $0.isNumber }) {
            lookUp(ScannedBarcode(payload: typed, symbology: .unknown))
            return
        }
        let submitted = query
        let submittedMarket = market
        let nextPage = loadMore ? productPage + 1 : 1
        isSearching = true
        productNotice = nil
        lookupTask = Task { @MainActor in
            defer { isSearching = false }
            // Open Food Facts asks for a few seconds between searches: wait, with the spinner showing.
            while !Task.isCancelled, catalog.secondsUntilNextSearch > 0 {
                try? await Task.sleep(for: .seconds(min(catalog.secondsUntilNextSearch + 0.05, 1)))
            }
            guard !Task.isCancelled, submitted == query else { return }
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
        }
    }

}

// MARK: - Serving detail (fine-tune grams before logging)

struct ServingDetailView: View {
    let food: NutritionFood
    let actionTitle: String?
    /// When set, the meal can be changed here (spring dropdown) and is written back.
    let slotSelection: Binding<MealSlot>?
    /// The food (with the package size and pieces set here, going to stock), the amount,
    /// and the person's own calories when they typed them (logging only).
    let onAdd: (NutritionFood, Double, Int?) -> Void

    @State private var grams: Double
    @State private var slot: MealSlot
    @State private var didAdd = false
    /// The person's own calories for this portion, replacing the estimate.
    @State private var kcalOverride: Int?
    @State private var showEntry = false
    @State private var typingField = PortionField.amount
    /// The amount as typed in the portion box; read when typing stops or the box loses focus.
    @State private var amountText = ""
    @FocusState private var amountFocused: Bool
    /// Going to stock: how many pieces the package holds, and what a piece is called.
    @State private var piecesInPackage: Double?
    @State private var pieceWord: String
    @State private var stock = StockStore.shared

    /// Own calories belong to a logged portion; food going to My Stock keeps its record's values.
    private var canTypeKcal: Bool { actionTitle == nil }
    /// This screen adds a package to My Stock rather than logging a portion.
    private let isStocking: Bool

    init(food: NutritionFood, slot: MealSlot, actionTitle: String? = nil, stocking: Bool? = nil,
         slotSelection: Binding<MealSlot>? = nil, onAdd: @escaping (NutritionFood, Double, Int?) -> Void) {
        self.food = food
        self.onAdd = onAdd
        self.actionTitle = actionTitle
        self.slotSelection = slotSelection
        let stocking = stocking ?? (actionTitle != nil)
        isStocking = stocking
        // Going to stock, the whole package (from the barcode) is the starting amount.
        let start = stocking ? (food.packageAmount ?? food.defaultAmount) : food.defaultAmount
        _grams = State(initialValue: min(max(food.basis == .serving ? start : start.rounded(), food.minimumAmount), food.maximumAmount))
        _slot = State(initialValue: slotSelection?.wrappedValue ?? slot)
        _piecesInPackage = State(initialValue: food.piecesPerPackage.map { $0.rounded() }.flatMap { $0 >= 1 ? $0 : nil })
        _pieceWord = State(initialValue: food.pieceName ?? "piece")
    }

    /// What one piece weighs: the food's own (from its label or as stocked), else the stock
    /// item this portion comes out of. Nil when the food isn't counted in pieces.
    private var piece: (amount: Double, name: String)? {
        if let amount = food.pieceAmount, amount > 0 { return (amount, food.pieceName ?? "piece") }
        if let item = stock.preview(for: food, amount: grams).first?.item, item.food.basis == food.basis,
           let amount = item.food.pieceAmount, amount > 0 {
            return (amount, item.food.pieceName ?? "piece")
        }
        return nil
    }

    /// The food as it goes to stock: with the package size and pieces set here.
    private var stockedFood: NutritionFood {
        food.withPieces(piecesInPackage, name: pieceWord, package: grams)
    }

    // Portion stepper: whole steps of 0.25 serving or 1 g / ml, same as before.
    private var amountStep: Double { food.basis == .serving ? 0.25 : 1 }
    private var amountStepRange: ClosedRange<Int> {
        Int((food.minimumAmount / amountStep).rounded())...Int((food.maximumAmount / amountStep).rounded())
    }
    private var amountSteps: Binding<Int> {
        Binding(
            get: { Int((grams / amountStep).rounded()) },
            set: { setAmount(Double($0) * amountStep) }
        )
    }
    /// The ruler, the stepper, the presets and typing all land here; the person's own
    /// calories (if any) follow the amount.
    private var gramsBinding: Binding<Double> {
        Binding(get: { grams }, set: { setAmount($0) })
    }
    /// Reads the typed amount; anything unreadable goes back to the current amount.
    private func commitTypedAmount() {
        if let amount = PortionInput.amount(amountText, for: food) { setAmount(amount) }
        amountText = formatAmount(grams)
    }

    private func setAmount(_ amount: Double) {
        kcalOverride = PortionInput.rescaled(kcalOverride, from: grams, to: amount)
        grams = amount
    }
    private var portion: NutritionFood.Portion { PortionInput.portion(of: food, amount: grams, kcal: kcalOverride) }
    private var estimatedKcal: Int { Int(food.portion(grams).kcal.rounded()) }
    private var amountLabel: String {
        let unit = food.basis == .grams ? "grams" : "millilitres"
        if isStocking { return food.basis == .serving ? "Servings in the package" : "Total in the package, in " + unit }
        return food.basis == .serving ? "Number of servings" : "Amount in " + unit
    }
    private func formatAmount(_ amount: Double) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        // Servings say "1×" so the number fits beside the stepper ("1 serving" didn't).
        return food.basis == .serving ? "\(number)×" : "\(number) \(food.basis.rawValue)"
    }
    private var kcal: Int { Int(portion.kcal.rounded()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Calorie hero for this serving; tap the number to type your own.
                VStack(spacing: 4) {
                    Button { if canTypeKcal { typingField = .kcal; showEntry = true } } label: {
                        Text("\(kcal)" as String)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold)).scaleEffect(1.35, anchor: .center)
                            .foregroundStyle(kcalOverride == nil ? Color.labelPrimary : Color.brandPrimary).monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(minWidth: 88, minHeight: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canTypeKcal)
                    .accessibilityLabel("Calories")
                    .accessibilityValue(kcalOverride == nil ? "\(kcal) kcal, estimated" : "\(kcal) kcal, your value")
                    .accessibilityHint(canTypeKcal ? "Type your own calories" : "")
                    .accessibilityIdentifier("logFood.kcal")
                    Text("kcal · \(grams.formatted(.number.precision(.fractionLength(0...2)))) \(food.basis.rawValue)" as String).font(.subheadline).foregroundStyle(Color.labelSecondary)
                    if kcalOverride != nil {
                        HStack(spacing: Spacing.sm) {
                            Label("Your value · estimate \(estimatedKcal) kcal" as String, systemImage: "pencil")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Color.brandPrimary)
                            Button("Use estimate") { kcalOverride = nil }
                                .font(.footnote.weight(.semibold))
                                .accessibilityIdentifier("logFood.kcal.reset")
                        }
                        .accessibilityElement(children: .contain)
                    } else if canTypeKcal {
                        Button { typingField = .kcal; showEntry = true } label: {
                            Label("Know the calories? Type your own", systemImage: "pencil")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Color.labelSecondary)
                                .frame(minHeight: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("logFood.kcal.type")
                    }
                    Text(food.brand ?? "Match the food's preparation to your portion")
                        .font(.subheadline).foregroundStyle(Color.labelSecondary)

                }
                .padding(.top, 12)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: grams)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: kcalOverride)

                // Macro chips (scaled to your own calories when you typed them)
                HStack(spacing: 10) {
                    macroChip("Protein", portion.protein, .proteinAccent)
                    macroChip("Carbs", portion.carbs, .carbsAccent)
                    macroChip("Fat", portion.fat, .fatAccent)
                }

                if slotSelection != nil { mealPicker }
                // Counted food first: "2 slices" is how people think of it.
                if !isStocking, let piece { piecesRow(piece) }
                if !isStocking {
                    // Which item in My Stock this comes out of (logging takes it out).
                    StockSummaryLine(summary: stock.summary(for: food, amount: grams))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                // Serving stepper
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isStocking ? "Amount in package" : "Portion").font(.headline)
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
                            font: .system(.headline, design: .rounded).weight(.bold),
                            onTapNumber: { typingField = .amount; showEntry = true }
                        )
                        .accessibilityIdentifier("logFood.amount")
                    }
                    // Type the amount straight in (no ruler).
                    HStack(spacing: 10) {
                        TextField(formatAmount(grams), text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                .strokeBorder(amountFocused ? Color.progress : Color.clear, lineWidth: 2))
                            .accessibilityLabel("Amount in " + (food.basis == .serving ? "servings" : food.basis.rawValue))
                            .accessibilityIdentifier("logFood.amount.field")
                            .onSubmit { commitTypedAmount() }
                            .onChange(of: amountFocused) { _, focused in if !focused { commitTypedAmount() } }
                        Text(food.basis == .serving ? "servings" : food.basis.rawValue)
                            .font(.headline).foregroundStyle(Color.labelSecondary)
                    }
                    .onAppear { amountText = formatAmount(grams) }
                    .onChange(of: grams) { _, new in if !amountFocused { amountText = formatAmount(new) } }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { amountFocused = false }
                        }
                    }
                    if !labelPresets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(labelPresets, id: \.id) { preset in
                                    Button(preset.title) { setAmount(preset.amount) }
                                        .font(.caption).fontWeight(.semibold)
                                        .lineLimit(1)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.progress.opacity(0.14), in: Capsule())
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                        .accessibilityIdentifier("logFood.preset." + preset.id)
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(food.basis == .serving ? [1, 2, 3, 4] : [50, 100, 150, 200], id: \.self) { preset in
                            Button(food.basis == .serving ? "\(preset)×" : "\(preset) \(food.basis.rawValue)") { setAmount(Double(preset)) }
                                .accessibilityLabel(food.basis == .serving ? "\(preset) serving\(preset == 1 ? "" : "s")" : "\(preset) \(food.basis.rawValue)")
                                .font(.caption).fontWeight(.semibold)
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.surfaceElevated, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(16)
                .premiumCard()

                if isStocking, food.basis != .serving { packagePieces }

                if food.packageAmount != nil || food.servingLabel != nil || food.servingAmount != nil {
                    packageFacts
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(food.sourceName).font(.headline)
                    if food.source == .openFoodFacts, let date = food.sourceDate {
                        Text("Retrieved \(date)" as String).font(.caption).foregroundStyle(Color.labelSecondary)
                    }
                    Text("\(food.referenceLabel): \(Self.oneDecimal(food.kcal)) kcal · Protein \(Self.oneDecimal(food.protein)) g · Carbs \(Self.oneDecimal(food.carbs)) g · Fat \(Self.oneDecimal(food.fat)) g" as String)
                        .font(.footnote)
                    if let url = food.sourceURL { Link(food.source == .cookbook ? "Open the recipe on Wikibooks (CC BY-SA 4.0)" : "View original nutrition record", destination: url) }
                    if let recipe = food.recipeDetails {
                        Text("Final weighed yield: \(recipe.cookedYieldG.formatted(.number.grouping(.never))) g" as String).font(.footnote)
                        ForEach(recipe.ingredients) { ingredient in
                            Text("\(ingredient.food.name) · \(Self.oneDecimal(ingredient.amount)) \(ingredient.food.basis.rawValue)" as String)
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
        // One dialog for both numbers (two alerts on one view show only one).
        .numberEntry(isPresented: $showEntry,
                     title: typingField == .kcal ? "Your calories" : typingField == .count ? (isStocking ? "Pieces in the package" : "How many") : "Amount",
                     current: typingField == .kcal ? "\(kcal)" : typingField == .count ? countText : formatAmount(grams),
                     message: typingField == .kcal
                        ? VoiceCommandSheet.kcalHint(estimate: estimatedKcal, amount: formatAmount(grams))
                        : typingField == .count
                            ? (isStocking ? "How many slices, pieces or cans the whole package holds. Logging by pieces then divides its grams and calories." : "The grams and calories follow the number of pieces.")
                            : VoiceCommandSheet.amountHint(food),
                     keyboard: typingField == .kcal ? .numberPad : .decimalPad,
                     identifier: typingField == .kcal ? "logFood.kcal.entry" : "logFood.amount.entry",
                     resetTitle: typingField == .kcal && kcalOverride != nil ? "Use the estimate" : nil,
                     onReset: { kcalOverride = nil }) { text in
            switch typingField {
            case .amount: if let amount = PortionInput.amount(text, for: food) { setAmount(amount) }
            case .kcal: if let typed = PortionInput.kcal(text) { kcalOverride = typed }
            case .count:
                if let value = TypedNumber.parse(text), value.isFinite, value > 0 {
                    if isStocking { piecesInPackage = min(value.rounded(), 500) }
                    else if let piece { setAmount(min(max(value * piece.amount, food.minimumAmount), food.maximumAmount)) }
                }
            }
        }
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
                onAdd(isStocking ? stockedFood : food, grams, canTypeKcal ? kcalOverride : nil)
            }
            .disabled(didAdd)
            .accessibilityIdentifier("logFood.addServing")
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    /// "22.7", never "22.727273".
    static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    private struct Preset { let id: String; let title: String; let amount: Double }

    /// The whole package and the label's serving, as chips (from the barcode data).
    private var labelPresets: [Preset] {
        var out: [Preset] = []
        let unit = food.basis.rawValue
        if let package = food.packageAmount, package >= food.minimumAmount, package <= food.maximumAmount {
            out.append(Preset(id: "package", title: "Whole package · \(Self.oneDecimal(package)) \(unit)", amount: package.rounded()))
        }
        if let serving = food.servingAmount, serving >= food.minimumAmount, serving <= food.maximumAmount {
            out.append(Preset(id: "serving", title: "One serving · \(Self.oneDecimal(serving)) \(unit)", amount: serving.rounded()))
        }
        return out
    }

    private var countText: String {
        if isStocking { return piecesInPackage.map { Self.oneDecimal($0) } ?? "" }
        guard let piece else { return "" }
        return Self.oneDecimal(grams / piece.amount)
    }

    /// What the package says, from Open Food Facts: its size, the label's serving and its pieces.
    private var packageFacts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("On the package", systemImage: "shippingbox")
                .font(.headline)
            if let package = food.packageAmount {
                Text("Package: \(Self.oneDecimal(package)) \(food.basis.rawValue)" as String).font(.footnote)
            }
            if let serving = food.servingAmount {
                Text("Serving: \(food.servingLabel ?? "\(Self.oneDecimal(serving)) \(food.basis.rawValue)") · \(Self.oneDecimal(food.portion(serving).kcal)) kcal" as String)
                    .font(.footnote)
            } else if let label = food.servingLabel {
                Text("Serving: \(label)" as String).font(.footnote)
            }
            if let pieces = food.piecesPerPackage, let name = food.pieceName {
                Text("About \(PieceWords.count(pieces.rounded(), name)) in a package" as String).font(.footnote)
            }
            if food.source == .openFoodFacts {
                Text("Filled in from the barcode (Open Food Facts). Check it against your package.")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("logFood.packageFacts")
    }

    /// Going to stock: how many slices, pieces or cans the package holds.
    private var packagePieces: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pieces in package").font(.headline)
                    Text(piecesInPackage.map { "One \(pieceWord) is about \(Self.oneDecimal(grams / $0)) \(food.basis.rawValue)" }
                         ?? "Optional: slices, pieces, cans …")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
                Spacer(minLength: 8)
                SpringStepper(
                    value: Binding(get: { Int(piecesInPackage ?? 0) }, set: { piecesInPackage = $0 > 0 ? Double($0) : nil }),
                    in: 0...500,
                    format: { $0 == 0 ? "None" : "\($0)" },
                    label: "Pieces in package",
                    decrementLabel: "Fewer pieces",
                    incrementLabel: "More pieces",
                    font: .system(.headline, design: .rounded).weight(.bold),
                    onTapNumber: { typingField = .count; showEntry = true }
                )
                .accessibilityIdentifier("logFood.piecesInPackage")
            }
            if piecesInPackage != nil {
                Picker("A piece is a", selection: $pieceWord) {
                    ForEach(Self.pieceWords(including: pieceWord), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("logFood.pieceWord")
            }
        }
        .padding(16)
        .premiumCard()
    }

    static func pieceWords(including word: String) -> [String] {
        let words = ["piece", "slice", "can", "bottle", "bar", "cookie", "biscuit", "egg", "samosa", "sausage", "patty",
                     "roll", "bun", "wrap", "tortilla", "pot", "pouch", "sachet", "stick", "square", "portion"]
        return words.contains(word) ? words : [word] + words
    }

    /// Logging: the portion by pieces ("2 slices · 42 g"), when the food is counted.
    private func piecesRow(_ piece: (amount: Double, name: String)) -> some View {
        let count = grams / piece.amount
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PieceWords.plural(piece.name).capitalized).font(.headline)
                Text("\(PieceWords.count((count * 2).rounded() / 2, piece.name)) · one is \(Self.oneDecimal(piece.amount)) \(food.basis.rawValue)" as String)
                    .font(.caption).foregroundStyle(Color.labelSecondary)
                    .accessibilityIdentifier("logFood.piecesText")
            }
            Spacer(minLength: 8)
            SpringStepper(
                value: Binding(get: { Int((count * 2).rounded()) }, set: { halves in
                    setAmount(min(max(Double(max(halves, 1)) / 2 * piece.amount, food.minimumAmount), food.maximumAmount))
                }),
                in: 1...200,
                format: { (Double($0) / 2).formatted(.number.precision(.fractionLength(0...1))) + " ×" },
                label: "Number of \(PieceWords.plural(piece.name))",
                decrementLabel: "Half fewer",
                incrementLabel: "Half more",
                font: .system(.headline, design: .rounded).weight(.bold),
                onTapNumber: { typingField = .count; showEntry = true }
            )
            .accessibilityIdentifier("logFood.pieces")
        }
        .padding(16)
        .premiumCard()
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
            Text("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g" as String)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
