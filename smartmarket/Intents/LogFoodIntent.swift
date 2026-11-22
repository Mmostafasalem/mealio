import AppIntents
import Foundation

// MARK: - Food entity

/// A food from Nourlo's on-device nutrition data: the bundled offline list,
/// products the user has already logged, and their own dishes. Siri never
/// searches products online.
nonisolated struct FoodEntity: AppEntity, Identifiable, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Food", numericFormat: "\(placeholder: .int) foods") }
    static var defaultQuery: FoodEntityQuery { FoodEntityQuery() }

    let id: String
    let name: String
    let subtitle: String
    /// "g", "ml" or "serving".
    let unit: String
    let defaultAmount: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)", image: .init(systemName: "fork.knife"))
    }

    @MainActor init(_ food: NutritionFood) {
        id = food.id
        name = food.name
        let per = food.basis == .serving ? "serving" : "100 " + food.basis.rawValue
        subtitle = "\(Int(food.kcal.rounded())) kcal / \(per)"
        unit = food.basis.rawValue
        defaultAmount = food.defaultAmount
    }
}

// Loading the offline catalogue (`NutritionCatalogService.shared`: about 13,600
// foods, a 3 MB JSON file decoded and indexed on the main actor) is the slow part
// of a cold Siri request. Recent foods are resolved from the food log's own
// snapshots instead, so suggestions (refreshed at every launch) and logging a
// recent food never load it; only a by-name search for something else does.

nonisolated struct FoodEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [FoodEntity.ID]) async throws -> [FoodEntity] {
        identifiers.compactMap(Self.resolve).map(FoodEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [FoodEntity] {
        Self.search(string, using: NutritionCatalogService.shared.searchLocal).map(FoodEntity.init)
    }

    /// Recent foods (they also fill "Log <food> in Nourlo"). Read from the log,
    /// without loading the offline catalogue.
    @MainActor
    func suggestedEntities() async throws -> [FoodEntity] {
        Self.suggestions().map(FoodEntity.init)
    }

    @MainActor static func suggestions() -> [NutritionFood] {
        let log = FoodLogStore.shared
        return Array(recentFoods(ids: log.recentFoodIDs, entries: log.allEntries).prefix(20))
    }

    /// The food for an id: a recent food from its logged snapshot when that is
    /// reference data (USDA, Open Food Facts), otherwise the catalogue (which
    /// also holds the person's own dishes, as last edited).
    @MainActor static func resolve(_ id: String) -> NutritionFood? {
        if let recent = recentFoods(ids: [id], entries: FoodLogStore.shared.allEntries).first { return recent }
        return NutritionCatalogService.shared.find(id)
    }

    /// The newest logged snapshot of each id, in `ids` order. Only reference
    /// foods, whose values don't change; own dishes can be edited, so they come
    /// from the catalogue. Ids without a usable snapshot are skipped.
    @MainActor static func recentFoods(ids: [String], entries: [FoodLogEntry]) -> [NutritionFood] {
        var latest: [String: (food: NutritionFood, at: Date)] = [:]
        for entry in entries {
            guard let id = entry.foodId, let food = entry.nutritionFood, food.id == id, food.isValid,
                  food.source == .usda || food.source == .openFoodFacts else { continue }
            if let seen = latest[id], seen.at > entry.loggedAt { continue }
            latest[id] = (food, entry.loggedAt)
        }
        var seen = Set<String>()
        return ids.compactMap { id in seen.insert(id).inserted ? latest[id]?.food : nil }
    }

    /// Local search that also forgives plurals ("bananas" finds "Banana").
    @MainActor
    static func search(_ query: String, using search: (String) -> [NutritionFood], limit: Int = 20) -> [NutritionFood] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var results = search(trimmed)
        // Also search the singular form ("Bananas" → "banana") and merge, keeping order.
        let singular = IntentSearch.words(trimmed).joined(separator: " ")
        if !singular.isEmpty, singular != trimmed.lowercased() {
            var seen = Set(results.map(\.id))
            for food in search(singular) where seen.insert(food.id).inserted { results.append(food) }
        }
        return Array(results.prefix(limit))
    }
}

// MARK: - Quick log

/// Logs a food without opening the app, exactly as the food logger's add button does.
struct LogFoodIntent: AppIntent {
    static var title: LocalizedStringResource { "Log food" }
    static var description: IntentDescription {
        IntentDescription("Adds a food to today's log. Uses Nourlo's offline food list, products you've logged before and your own dishes; it doesn't search online.",
                          categoryName: "Food log")
    }
    static var openAppWhenRun: Bool { false }
    /// Changes the person's food log, so only on an unlocked device.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Food", requestValueDialog: "Which food?")
    var food: FoodEntity

    @Parameter(title: "Amount", description: "Grams, millilitres or servings, as the food is measured. Leave empty for the usual amount.")
    var amount: Double?

    @Parameter(title: "Meal", description: "Leave empty to pick the meal by time of day.")
    var meal: MealSlotOption?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) of \(\.$food) to \(\.$meal)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let source = FoodEntityQuery.resolve(food.id) else { throw NourloIntentError.foodNotFound }
        let entry = try Self.makeEntry(food: source, amount: amount, slot: meal?.mealSlot)
        // Only products are saved (`remember` ignores the rest); skip the catalogue load otherwise.
        if source.source == .openFoodFacts { NutritionCatalogService.shared.remember(source) }
        FoodLogStore.shared.add(entry)
        // The app may be suspended again before the usual short pause: update the widgets now.
        WidgetSync.shared.syncNow()
        // The person has logged food, so the "Log food" tip has done its job.
        NourloTips.foodLogged()
        return .result(dialog: IntentDialog(stringLiteral: Self.confirmation(for: entry, food: source)))
    }

    /// The entry the food logger would add: same validation as
    /// `HomeViewModel.logFood` and the same `FoodLogEntry(nutritionFood:slot:amount:)`.
    @MainActor
    static func makeEntry(food: NutritionFood, amount: Double?, slot: MealSlot?, now: Date = Date(), kcal: Int? = nil) throws -> FoodLogEntry {
        guard food.isValid else { throw NourloIntentError.foodNotFound }
        let value = amount ?? food.defaultAmount
        guard value.isFinite, value >= food.minimumAmount, value <= food.maximumAmount else {
            throw NourloIntentError.invalidAmount(LogFoodSheet.amountText(food.minimumAmount, basis: food.basis) + " and "
                                                 + LogFoodSheet.amountText(food.maximumAmount, basis: food.basis))
        }
        return FoodLogEntry(nutritionFood: food, slot: slot ?? MealSlot.suggested(at: now), amount: value, kcal: kcal)
    }

    /// "Logged 100 g of Banana, raw to breakfast, 89 kcal."
    @MainActor
    static func confirmation(for entry: FoodLogEntry, food: NutritionFood, locale: Locale = .current) -> String {
        let amount = LogFoodSheet.amountText(entry.amount, basis: food.basis, locale: locale)
        let kcal = entry.calories.formatted(.number.locale(locale))
        return "Logged \(amount) of \(entry.name) to \(entry.slot.title.lowercased()), \(kcal) kcal."
    }
}
