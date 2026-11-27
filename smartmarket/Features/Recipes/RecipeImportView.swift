import SwiftUI
import PhotosUI
import Vision

// MARK: - Add a recipe I'm following
//
// Paste the recipe, give its link, or take a photo of it. Nourlo reads the ingredient
// lines (on the phone: the page's recipe data, or Vision's text recognition for a
// photo), matches each to its own food data, and works out the nutrition. The person
// says how many servings the recipe makes and how many they ate, can cook it halved or
// doubled, and it's saved as their own recipe and logged.

extension Notification.Name {
    /// Opens "Add a recipe I'm following" (quick action id `addRecipe`).
    static let openAddRecipe = Notification.Name("openAddRecipe")
}

/// The food an ingredient line means. A recipe names what goes into the pot, so the
/// raw or dry record is preferred, the food's own word must lead the record's name
/// ("spaghetti" is pasta, never spaghetti squash), and food already in My Stock comes first.
@MainActor
enum RecipeFoodFinder {
    /// Recipe words the food data names differently.
    static let synonyms: [String: String] = [
        "spaghetti": "pasta dry", "penne": "pasta dry", "fusilli": "pasta dry", "macaroni": "pasta dry",
        "linguine": "pasta dry", "tagliatelle": "pasta dry", "pasta": "pasta dry", "noodles": "noodles egg dry",
        "minced beef": "beef ground raw", "ground beef": "beef ground raw", "beef mince": "beef ground raw",
        "minced pork": "pork ground raw", "ground pork": "pork ground raw", "minced meat": "beef ground raw",
        "chopped tomatoes": "tomatoes canned", "tinned tomatoes": "tomatoes canned", "canned tomatoes": "tomatoes canned",
        "olive oil": "oil olive", "vegetable oil": "oil vegetable", "plain flour": "wheat flour all-purpose",
        "flour": "wheat flour all-purpose", "caster sugar": "sugar granulated", "sugar": "sugar granulated",
        "chicken breast": "chicken breast raw", "chicken breasts": "chicken breast raw", "eggs": "egg whole raw",
        "egg": "egg whole raw", "butter": "butter salted", "milk": "milk whole", "rice": "rice white raw",
    ]

    static func foods(for name: String, limit: Int = 6) -> [NutritionFood] {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        let query = synonyms[lower] ?? lower
        let filler: Set<String> = ["fresh", "large", "small", "ripe", "dried", "whole", "raw", "dry", "canned", "chopped"]
        let wanted = KitchenMatcher.words(query).subtracting(filler)
        func fits(_ food: NutritionFood) -> Bool {
            guard food.isValid, food.basis != .serving else { return false }
            let lead = food.name.lowercased().split(separator: ",").prefix(2).joined(separator: " ")
            return wanted.isEmpty || !wanted.isDisjoint(with: KitchenMatcher.words(lead))
        }
        var out: [NutritionFood] = []
        func add(_ foods: [NutritionFood]) {
            for food in foods where fits(food) && !out.contains(where: { $0.id == food.id }) { out.append(food) }
        }
        // What's in the kitchen already.
        let line = CookbookRecipe.Line(text: name, food: nil, grams: nil, match: lower, pantry: nil)
        add(StockStore.shared.items.filter { KitchenMatcher(names: [$0.food.name]).has(line) }.map(\.food))
        let raw = VoiceFoodRanker.foods(for: query + (query.contains("raw") || query.contains("dry") ? "" : " raw"), limit: 6, recentIDs: [])
        add(raw.filter { !KitchenMatcher.words($0.name).isDisjoint(with: ["raw", "dry", "uncooked", "canned"]) })
        add(VoiceFoodRanker.foods(for: query, limit: 8, recentIDs: []))
        if out.isEmpty { out = VoiceFoodRanker.foods(for: lower, limit: limit, recentIDs: []).filter { $0.isValid && $0.basis != .serving } }
        return Array(out.prefix(limit))
    }
}

/// One ingredient of the recipe, matched to a food (or not).
struct RecipeDraftItem: Identifiable, Equatable {
    let id = UUID()
    let line: RecipeLine
    var food: NutritionFood?
    var alternatives: [NutritionFood]
    /// For the recipe as written (scale 1), in the food's unit.
    var amount: Double
    var estimated: Bool

    static func == (a: RecipeDraftItem, b: RecipeDraftItem) -> Bool {
        a.id == b.id && a.food?.id == b.food?.id && a.amount == b.amount
    }
}

/// The recipe being reviewed: its foods, servings, scale and what was eaten.
@MainActor @Observable
final class RecipeDraft {
    var name: String
    var items: [RecipeDraftItem]
    /// Servings the recipe as written makes.
    var servings: Double
    /// Cooking half (0.5), as written (1) or double (2): amounts and servings change together.
    var scale: Double = 1
    /// Servings eaten.
    var eaten: Double = 1
    let servingsGiven: Bool

    typealias Search = (String) -> [NutritionFood]

    init(_ parsed: ParsedRecipe, search: Search? = nil) {
        let search = search ?? { RecipeFoodFinder.foods(for: $0) }
        name = parsed.title
        servings = parsed.servings ?? 4
        servingsGiven = parsed.servings != nil
        items = parsed.lines.map { line in
            let found = search(line.name).filter { $0.isValid && $0.basis != .serving }
            let food = found.first
            let piece = food.flatMap { VoiceAmounts.pieceWeight(of: line.name, food: $0) ?? $0.pieceAmount }
            let grams = RecipeAmounts.grams(for: line, pieceWeight: piece)
            return RecipeDraftItem(line: line, food: grams == nil ? nil : food, alternatives: found,
                                   amount: grams?.grams ?? 0, estimated: grams?.estimated ?? true)
        }
    }

    var counted: [RecipeDraftItem] { items.filter { $0.food != nil && $0.amount > 0 } }
    var notCounted: [RecipeDraftItem] { items.filter { $0.food == nil || $0.amount <= 0 } }

    /// The ingredients as cooked (scaled).
    var ingredients: [NutritionIngredient] {
        counted.compactMap { item in item.food.map { NutritionIngredient(food: $0, amount: max(1, item.amount * scale)) } }
    }

    var servingsMade: Double { max(0.25, servings * scale) }

    var total: NutritionFood.Portion {
        let parts = ingredients.map { $0.food.portion($0.amount) }
        return NutritionFood.Portion(kcal: parts.reduce(0) { $0 + $1.kcal }, protein: parts.reduce(0) { $0 + $1.protein },
                                     carbs: parts.reduce(0) { $0 + $1.carbs }, fat: parts.reduce(0) { $0 + $1.fat })
    }

    var perServing: NutritionFood.Portion {
        let t = total, n = servingsMade
        return NutritionFood.Portion(kcal: t.kcal / n, protein: t.protein / n, carbs: t.carbs / n, fat: t.fat / n)
    }

    var totalGrams: Double { ingredients.reduce(0) { $0 + $1.amount } }

    /// The recipe as one of the person's own foods, counted per serving.
    func food() -> NutritionFood? {
        let ingredients = self.ingredients
        guard !ingredients.isEmpty else { return nil }
        let identifier = UUID().uuidString
        let per = perServing
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var food = NutritionFood(id: "recipe:" + identifier, name: title.isEmpty ? "My recipe" : String(title.prefix(160)), brand: nil,
                                 basis: .serving, kcal: per.kcal, protein: per.protein, carbs: per.carbs, fat: per.fat,
                                 source: .recipe, sourceID: identifier,
                                 sourceDate: String(ISO8601DateFormatter().string(from: Date()).prefix(10)))
        food.recipeDetails = NutritionRecipe(ingredients: Array(ingredients.prefix(50)), cookedYieldG: max(1, totalGrams))
        food.summary = "Makes \(Self.number(servingsMade)) servings of about \(Int((totalGrams / servingsMade).rounded())) g (raw ingredient weight)."
        return food.isValid ? food : nil
    }

    func choose(_ food: NutritionFood, for item: RecipeDraftItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].food = food
        if items[index].amount <= 0 {
            let piece = VoiceAmounts.pieceWeight(of: item.line.name, food: food)
            items[index].amount = RecipeAmounts.grams(for: item.line, pieceWeight: piece)?.grams ?? 100
        }
    }

    func setAmount(_ amount: Double, for item: RecipeDraftItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), amount.isFinite, amount >= 0 else { return }
        items[index].amount = amount / scale
        items[index].estimated = false
    }

    func remove(_ item: RecipeDraftItem) { items.removeAll { $0.id == item.id } }

    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}

// MARK: - Reading the recipe

enum RecipeSource: String, CaseIterable, Identifiable {
    case text, link, photo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return "Paste text"
        case .link: return "Link"
        case .photo: return "Photo"
        }
    }
}

enum RecipeReader {
    enum Failure: LocalizedError {
        case badLink, unreachable, nothingFound
        var errorDescription: String? {
            switch self {
            case .badLink: return "That doesn't look like a web link. It should start with https://"
            case .unreachable: return "Couldn't open that page. Check the link and your connection, or paste the recipe's text."
            case .nothingFound: return "Couldn't find ingredient lines with amounts. Paste just the ingredients, one per line (\"200 g pasta\")."
            }
        }
    }

    /// The page's schema.org recipe when it has one, else its text read line by line.
    static func fromLink(_ text: String, session: URLSession = .shared) async throws -> ParsedRecipe {
        var link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.lowercased().hasPrefix("http") { link = "https://" + link }
        guard let url = URL(string: link), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { throw Failure.badLink }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { throw Failure.unreachable }
            data = body
        } catch let failure as Failure { throw failure } catch { throw Failure.unreachable }
        let html = String(data: data.prefix(3_000_000), encoding: .utf8) ?? String(decoding: data.prefix(3_000_000), as: UTF8.self)
        if let recipe = RecipeWebReader.recipe(fromHTML: html) { return recipe }
        let parsed = RecipeTextParser.parse(RecipeWebReader.text(fromHTML: html))
        guard !parsed.lines.isEmpty else { throw Failure.nothingFound }
        return parsed
    }

    /// The text in a photo of a recipe, read on the phone (Vision), top to bottom.
    nonisolated static func text(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return "" }
            return (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - The sheet

/// "Add a recipe I'm following". Present it from the food logger or the quick actions.
struct RecipeImportSheet: View {
    var slot: MealSlot? = nil
    let close: () -> Void

    var body: some View {
        NavigationStack {
            RecipeImportView(slot: slot ?? .suggested(), close: close)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct RecipeImportView: View {
    let close: () -> Void
    @State private var source: RecipeSource = .text
    @State private var pasted = ""
    @State private var link = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var reading = false
    @State private var problem: String?
    @State private var draft: RecipeDraft?
    @State private var slot: MealSlot

    init(slot: MealSlot, close: @escaping () -> Void) {
        self.close = close
        _slot = State(initialValue: slot)
    }

    /// UI tests hand in a recipe with `-NourloRecipeTestText "…"` (lines split by "|").
    private static var testText: String? {
        guard NourloTips.isUITesting() else { return nil }
        return UserDefaults.standard.string(forKey: "NourloRecipeTestText")?.replacingOccurrences(of: "|", with: "\n")
    }

    var body: some View {
        Group {
            if let draft {
                RecipeReviewView(draft: draft, slot: $slot, close: close)
            } else {
                input
            }
        }
        .navigationTitle("Add a recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } }
        }
        .onAppear { if pasted.isEmpty, let text = Self.testText { pasted = text } }
    }

    private var input: some View {
        Form {
            Section {
                Picker("Recipe from", selection: $source) {
                    ForEach(RecipeSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("recipe.source")
            } footer: {
                Text("Nourlo reads the ingredient lines with their amounts, works out the nutrition from its own food data, and asks how many servings it makes.")
            }
            switch source {
            case .text:
                Section("Recipe text") {
                    TextEditor(text: $pasted)
                        .frame(minHeight: 180)
                        .font(.body)
                        .accessibilityLabel("Recipe text")
                        .accessibilityIdentifier("recipe.text")
                    if pasted.isEmpty {
                        Text("For example:\nSpaghetti bolognese\nServes 4\n400 g spaghetti\n500 g minced beef\n1 onion\n2 tbsp olive oil")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                }
            case .link:
                Section {
                    TextField("https://", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("recipe.link")
                } header: { Text("Link to the recipe") } footer: {
                    Text("Nourlo opens the page and reads its recipe. Only the page is fetched; nothing about you is sent.")
                }
            case .photo:
                Section {
                    if MealCameraPicker.isAvailable {
                        Button { showCamera = true } label: { Label("Take a photo of the recipe", systemImage: "camera.fill") }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("recipe.photo")
                } footer: {
                    Text("The text is read on your iPhone. Nothing is uploaded.")
                }
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Color.brandDanger) }
            }
            if source != .photo {
                Section {
                    Button {
                        Task { await read() }
                    } label: {
                        HStack {
                            Text(reading ? "Reading…" : "Read the recipe").fontWeight(.semibold)
                            if reading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(reading || (source == .text ? pasted : link).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("recipe.read")
                }
            } else if reading {
                Section { HStack { ProgressView(); Text("Reading the photo…") } }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $showCamera) {
            MealCameraPicker { image in
                showCamera = false
                if let image { Task { await readPhoto(image) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await readPhoto(image)
            }
        }
    }

    private func read() async {
        problem = nil
        reading = true
        defer { reading = false }
        do {
            let parsed: ParsedRecipe
            switch source {
            case .text: parsed = RecipeTextParser.parse(pasted)
            case .link: parsed = try await RecipeReader.fromLink(link)
            case .photo: return
            }
            open(parsed)
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that recipe."
        }
    }

    private func readPhoto(_ image: UIImage) async {
        problem = nil
        reading = true
        defer { reading = false }
        let text = await RecipeReader.text(in: image)
        open(RecipeTextParser.parse(text), fallbackText: text)
    }

    private func open(_ parsed: ParsedRecipe, fallbackText: String? = nil) {
        guard !parsed.lines.isEmpty else {
            if let fallbackText, !fallbackText.isEmpty {
                // Show what was read, so it can be fixed by hand.
                pasted = fallbackText
                source = .text
            }
            problem = RecipeReader.Failure.nothingFound.errorDescription
            return
        }
        draft = RecipeDraft(parsed)
    }
}

// MARK: - Review

struct RecipeReviewView: View {
    @Bindable var draft: RecipeDraft
    @Binding var slot: MealSlot
    let close: () -> Void

    @State private var stock = StockStore.shared
    @State private var takeFromStock = true
    @State private var customScale = ""
    @State private var showCustomScale = false
    @State private var editing: RecipeDraftItem?
    @State private var amountText = ""
    @State private var logged: (entry: FoodLogEntry, food: NutritionFood)?
    @State private var problem: String?

    private static let scales: [Double] = [0.5, 1, 2]

    var body: some View {
        Form {
            if let logged {
                Section {
                    Label("Logged \(RecipeDraft.number(logged.entry.amount)) serving\(logged.entry.amount == 1 ? "" : "s") of \(logged.food.name), \(logged.entry.calories) kcal" as String,
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.ringProtein)
                        .accessibilityIdentifier("recipe.done")
                    Text("Saved under Your dishes in Add Food, to log again.")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                    Button("Undo") { undo(logged) }.accessibilityIdentifier("recipe.undo")
                    Button("Done") { close() }.fontWeight(.semibold)
                }
            } else {
                Section("Recipe") {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("recipe.name")
                }
                servingsSection
                scaleSection
                totalsSection
                ingredientsSection
                if !draft.notCounted.isEmpty {
                    Section {
                        ForEach(draft.notCounted) { item in
                            Menu {
                                ForEach(item.alternatives) { food in
                                    Button(food.name) { draft.choose(food, for: item) }
                                }
                                Button("Leave it out", role: .destructive) { draft.remove(item) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.line.text).foregroundStyle(Color.labelPrimary)
                                    Text(item.alternatives.isEmpty ? "No match in Nourlo's foods" : "No amount: tap to choose a food")
                                        .font(.caption).foregroundStyle(Color.labelSecondary)
                                }
                            }
                        }
                    } header: { Text("Not counted") } footer: {
                        Text("Lines without an amount (salt to taste) or a matching food add nothing.")
                    }
                }
                Section {
                    Picker("Meal", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                    Toggle("Take the ingredients out of My Stock", isOn: $takeFromStock)
                        .toggleStyle(.spring)
                        .accessibilityIdentifier("recipe.useStock")
                } footer: {
                    Text("Takes the amounts you cooked (scaled) from the matching foods in stock. Undo puts them back.")
                }
                if let problem { Section { Text(problem).foregroundStyle(Color.brandDanger) } }
                Section {
                    Button {
                        saveAndLog()
                    } label: {
                        Text("Save and log \(Int((draft.perServing.kcal * draft.eaten).rounded())) kcal" as String)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(draft.ingredients.isEmpty || draft.eaten <= 0)
                    .accessibilityIdentifier("recipe.log")
                }
            }
        }
        .toolbar {
            if logged == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { saveAndLog() }
                        .fontWeight(.semibold)
                        .disabled(draft.ingredients.isEmpty || draft.eaten <= 0)
                        .accessibilityIdentifier("recipe.logToolbar")
                }
            }
        }
        .alert("Amount", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Grams", text: $amountText).keyboardType(.decimalPad)
            Button("Save") {
                if let item = editing, let value = TypedNumber.parse(amountText) { draft.setAmount(value, for: item) }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            Text("The amount in the recipe as you're cooking it, in \(editing?.food?.basis.rawValue ?? "g").")
        }
        .alert("Scale the recipe", isPresented: $showCustomScale) {
            TextField("For example 1.5", text: $customScale).keyboardType(.decimalPad)
            Button("Use") {
                if let value = TypedNumber.parse(customScale), value > 0, value <= 20 { draft.scale = value }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("1.5 cooks one and a half times the recipe; 0.25 cooks a quarter.")
        }
    }

    private var servingsSection: some View {
        Section {
            Stepper(value: $draft.servings, in: 1...50, step: 1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How many servings does this recipe make?")
                    Text("\(RecipeDraft.number(draft.servings)) as written\(draft.servingsGiven ? "" : " (the recipe doesn't say; check it)")" as String)
                        .font(.caption).foregroundStyle(draft.servingsGiven ? Color.labelSecondary : Color.brandAmber)
                }
            }
            .accessibilityIdentifier("recipe.servings")
            Stepper(value: $draft.eaten, in: 0.25...20, step: 0.25) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How many did you eat?")
                    Text("\(RecipeDraft.number(draft.eaten)) serving\(draft.eaten == 1 ? "" : "s")" as String)
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
            }
            .accessibilityIdentifier("recipe.eaten")
        } header: { Text("Servings") }
    }

    private var scaleSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(Self.scales, id: \.self) { value in
                    scaleChip("×" + RecipeDraft.number(value), selected: draft.scale == value) { draft.scale = value }
                        .accessibilityIdentifier("recipe.scale.\(RecipeDraft.number(value))")
                }
                scaleChip(Self.scales.contains(draft.scale) ? "Custom" : "×" + RecipeDraft.number(draft.scale),
                          selected: !Self.scales.contains(draft.scale)) {
                    customScale = Self.scales.contains(draft.scale) ? "" : RecipeDraft.number(draft.scale)
                    showCustomScale = true
                }
                .accessibilityIdentifier("recipe.scale.custom")
            }
        } header: { Text("Cooking more or less?") } footer: {
            Text("Scaling changes every amount and the servings it makes together, so a serving stays the same. Now it makes \(RecipeDraft.number(draft.servingsMade)) servings." as String)
        }
    }

    private func scaleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.onAccent : Color.labelPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? Color.progress : Color.surfaceSecondary, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var totalsSection: some View {
        let per = draft.perServing, total = draft.total
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Int((per.kcal * draft.eaten).rounded())) kcal for what you ate" as String)
                    .font(.title3.weight(.bold)).monospacedDigit()
                    .accessibilityIdentifier("recipe.eatenKcal")
                Text("A serving: \(Int(per.kcal.rounded())) kcal · P \(ServingDetailView.oneDecimal(per.protein)) g · C \(ServingDetailView.oneDecimal(per.carbs)) g · F \(ServingDetailView.oneDecimal(per.fat)) g" as String)
                    .font(.footnote).monospacedDigit()
                Text("Whole recipe: \(Int(total.kcal.rounded())) kcal, \(Int(draft.totalGrams.rounded())) g of ingredients" as String)
                    .font(.footnote).foregroundStyle(Color.labelSecondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        } header: { Text("Nutrition") }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(draft.counted) { item in
                if let food = item.food {
                    let amount = item.amount * draft.scale
                    VStack(alignment: .leading, spacing: 4) {
                        Menu {
                            ForEach(item.alternatives) { option in Button(option.name) { draft.choose(option, for: item) } }
                        } label: {
                            HStack(spacing: 4) {
                                Text(food.name).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                                if item.alternatives.count > 1 { Image(systemName: "chevron.up.chevron.down").font(.caption2) }
                            }
                            .foregroundStyle(Color.labelPrimary)
                        }
                        .accessibilityHint("Choose a different food")
                        Button {
                            amountText = RecipeDraft.number(amount.rounded())
                            editing = item
                        } label: {
                            Text("\(LogFoodSheet.amountText(amount.rounded(), basis: food.basis))\(item.estimated ? " (est.)" : "") · \(Int(food.portion(amount).kcal.rounded())) kcal" as String)
                                .font(.footnote.monospacedDigit())
                                .underline(pattern: .dot)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Type the amount")
                        Text("“\(item.line.text)”" as String).font(.caption).foregroundStyle(Color.labelSecondary)
                        if takeFromStock {
                            StockSummaryLine(summary: stock.summary(for: food, amount: amount.rounded()))
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { draft.remove(item) } }
                    .accessibilityIdentifier("recipe.ingredient")
                }
            }
        } header: { Text("Ingredients (\(draft.counted.count))" as String) } footer: {
            Text("Amounts in cups and spoons are converted to grams and marked est. Tap an amount to type the weight.")
        }
    }

    private func saveAndLog() {
        problem = nil
        guard let food = draft.food() else { problem = "Add at least one ingredient with an amount."; return }
        do { try NutritionCatalogService.shared.saveCustom(food) } catch {
            problem = (error as? LocalizedError)?.errorDescription
            return
        }
        let entry = FoodLogEntry(nutritionFood: food, slot: slot, amount: draft.eaten)
        FoodLogStore.shared.add(entry, takeFromStock: false)
        if takeFromStock { stock.takeOut(for: entry.id, ingredients: draft.ingredients) }
        NourloTips.foodLogged()
        logged = (entry, food)
    }

    private func undo(_ logged: (entry: FoodLogEntry, food: NutritionFood)) {
        FoodLogStore.shared.remove(logged.entry)
        NutritionCatalogService.shared.removeCustom(logged.food.id)
        self.logged = nil
    }
}
