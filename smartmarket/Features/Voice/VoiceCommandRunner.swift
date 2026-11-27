import Foundation

// MARK: - A command made concrete
//
// The rule book says what was meant ("log two eggs"); this turns it into the
// exact thing the app will do (which food from the catalogue, how many grams)
// so it can be shown for confirmation, carried out and undone.

/// One spoken food matched to a food in Nourlo's on-device nutrition data.
struct VoiceFoodMatch: Identifiable, Equatable {
    let id = UUID()
    let phrase: VoiceFoodPhrase
    var food: NutritionFood
    var amount: Double
    /// Other foods the name could mean, best first (the chosen one included).
    var alternatives: [NutritionFood]
    /// The amount was worked out from a typical size ("2 eggs" → 100 g), not said in grams.
    var estimated: Bool
    /// The food or its amount is a guess (a bare name, grams said for a food
    /// counted in servings): shown for a tap, never saved by the countdown.
    var guessed = false
    /// The person's own calories for this portion, typed on the review card.
    var kcalOverride: Int? = nil
    /// One piece ("veggie burger", "slice"), in the food's unit, when it was counted
    /// ("2 veggie burgers") or the food comes in pieces; nil when it's only weighed.
    var pieceAmount: Double? = nil
    /// What one piece is called, singular ("veggie burger").
    var pieceName: String? = nil

    /// How many pieces the amount is ("2"), when the food is counted.
    var count: Double? {
        guard let piece = pieceAmount, piece > 0 else { return nil }
        return ((amount / piece) * 100).rounded() / 100
    }

    /// "2 × veggie burger · 220 g · 493 kcal" (or "150 g · 200 kcal" when not counted).
    var summary: String {
        let amountText = LogFoodSheet.amountText(amount, basis: food.basis)
        var parts: [String] = []
        if let count, let pieceName { parts.append("\(count.formatted(.number.precision(.fractionLength(0...2)))) × \(pieceName)") }
        parts.append(amountText)
        parts.append("\(kcal) kcal")
        return parts.joined(separator: " · ")
    }

    /// The calories that will be logged: the person's own figure, else the estimate.
    var kcal: Int { kcalOverride ?? estimatedKcal }
    var estimatedKcal: Int { Int(food.portion(amount).kcal.rounded()) }

    static func == (a: VoiceFoodMatch, b: VoiceFoodMatch) -> Bool {
        a.id == b.id && a.food.id == b.food.id && a.amount == b.amount && a.kcalOverride == b.kcalOverride && a.pieceAmount == b.pieceAmount
    }
}

enum VoicePlan: Equatable {
    case food(matches: [VoiceFoodMatch], missing: [String], slot: MealSlot)
    case cart(items: [CatalogItem], missing: [String])
    case checklist([String])
    case workout(kind: ExerciseKind?, minutes: Int?)
    case open(VoiceScreen)
    case exercise(Exercise)
    case answer(String)
    case notUnderstood(String)

    /// Changes saved data, so it is shown for confirmation before it runs.
    var needsConfirmation: Bool {
        switch self {
        case .food, .cart, .checklist: return true
        case .workout, .open, .exercise, .answer, .notUnderstood: return false
        }
    }

    /// Something in it was guessed, so it waits for a tap instead of saving itself.
    var isGuessed: Bool {
        if case .food(let matches, _, _) = self { return matches.contains { $0.guessed } }
        return false
    }

    /// Nothing was left unmatched, so it can be saved without the person choosing anything.
    var isComplete: Bool {
        switch self {
        case .food(let matches, let missing, _): return !matches.isEmpty && missing.isEmpty
        case .cart(let items, let missing): return !items.isEmpty && missing.isEmpty
        case .checklist(let names): return !names.isEmpty
        default: return true
        }
    }

    static func == (a: VoicePlan, b: VoicePlan) -> Bool {
        switch (a, b) {
        case let (.food(m1, x1, s1), .food(m2, x2, s2)): return m1 == m2 && x1 == x2 && s1 == s2
        case let (.cart(i1, x1), .cart(i2, x2)): return i1 == i2 && x1 == x2
        case let (.checklist(n1), .checklist(n2)): return n1 == n2
        case let (.workout(k1, m1), .workout(k2, m2)): return k1 == k2 && m1 == m2
        case let (.open(s1), .open(s2)): return s1 == s2
        case let (.exercise(e1), .exercise(e2)): return e1.id == e2.id
        case let (.answer(t1), .answer(t2)): return t1 == t2
        case let (.notUnderstood(t1), .notUnderstood(t2)): return t1 == t2
        default: return false
        }
    }
}

/// Where a finished command sends the app (handled by `MainTabView`).
enum VoiceNavigation: Equatable {
    case screen(VoiceScreen)
    case workout(kind: ExerciseKind?, minutes: Int?)
    case exercise(String)
}

/// What happened, in words, with a way back when data was changed.
struct VoiceOutcome {
    let message: String
    var undo: (() -> Void)?
    var navigation: VoiceNavigation?
}

// MARK: - Runner

@MainActor
enum VoiceCommandRunner {

    /// Searches Nourlo's on-device foods (offline list, logged products, own dishes).
    typealias FoodSearch = (String) -> [NutritionFood]

    static func plan(for command: VoiceCommand, language: VoiceLanguage = .english, now: Date = Date(), search: FoodSearch? = nil) -> VoicePlan {
        // The catalogue search, re-ordered so the plain, common form of a food comes first.
        let search = search ?? { VoiceFoodRanker.foods(for: $0) }
        switch command {
        case .logFood(let phrases, let slot):
            return foodPlan(phrases, slot: slot ?? MealSlot.suggested(at: now), search: search)
        case .addToCart(let names):
            var items: [CatalogItem] = []
            var missing: [String] = []
            for name in names {
                if let item = IntentSearch.filter(CatalogItem.all, query: name, name: \.name, limit: 1).first {
                    if !items.contains(item) { items.append(item) }
                } else {
                    missing.append(name)
                }
            }
            return .cart(items: items, missing: missing)
        case .addToChecklist(let names):
            return .checklist(names.map(displayName))
        case .startWorkout(let kind, let minutes):
            return .workout(kind: kind, minutes: minutes.map { min(max($0, 5), 120) })
        case .open(let screen):
            return .open(screen)
        case .showExercise(let name):
            if let exercise = ExerciseEntityQuery.search(name, limit: 1).first { return .exercise(exercise) }
            return .notUnderstood("I couldn't find an exercise called \"\(name)\".")
        case .caloriesLeft:
            return .answer(CaloriesLeftSummary.current(now: now).dialog())
        case .unknown(let text):
            // A bare food name ("banana") is still worth a try before giving up, but only
            // when it plainly names the food, and only as a guess: "stop" or "no" log nothing.
            let phrases = VoiceRuleBook.foodPhrases(text, language.lexicon).filter { !$0.name.isEmpty }
            if !phrases.isEmpty, phrases.count <= 4,
               case .food(let matches, let missing, let slot) = foodPlan(phrases, slot: MealSlot.suggested(at: now), search: search, bareNames: true),
               !matches.isEmpty, missing.isEmpty {
                return .food(matches: matches, missing: [], slot: slot)
            }
            return .notUnderstood(text.isEmpty ? "I didn't catch that." : "I'm not sure what to do with \"\(text)\".")
        }
    }

    /// `bareNames`: the phrase had no verb, meal or amount, so a food is taken
    /// only when the name plainly names it, and the match is marked as a guess.
    private static func foodPlan(_ phrases: [VoiceFoodPhrase], slot: MealSlot, search: FoodSearch, bareNames: Bool = false) -> VoicePlan {
        var matches: [VoiceFoodMatch] = []
        var missing: [String] = []
        for phrase in phrases {
            var found = search(phrase.name).filter { $0.isValid }
            if bareNames { found = found.filter { VoiceFoodRanker.plainlyNames(phrase.name, $0) } }
            guard let food = found.first else {
                missing.append(phrase.name)
                continue
            }
            let (amount, estimated) = VoiceAmounts.amount(for: phrase, food: food)
            var match = VoiceFoodMatch(phrase: phrase, food: food, amount: amount, alternatives: found, estimated: estimated)
            match.guessed = bareNames || VoiceAmounts.isUnsure(phrase, food: food)
            (match.pieceAmount, match.pieceName) = VoiceAmounts.pieces(for: phrase, food: food, amount: amount)
            matches.append(match)
        }
        return .food(matches: matches, missing: missing, slot: slot)
    }

    /// "olive oil" → "Olive oil".
    static func displayName(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: Carrying it out

    static func perform(_ plan: VoicePlan, now: Date = Date(), loggedAt: Date? = nil) -> VoiceOutcome {
        switch plan {
        case .food(let matches, _, let slot):
            var added: [FoodLogEntry] = []
            for match in matches {
                guard var entry = try? LogFoodIntent.makeEntry(food: match.food, amount: match.amount, slot: slot, now: now,
                                                               kcal: match.kcalOverride) else { continue }
                // A meal photo finished later is logged at the time it was taken.
                if let loggedAt {
                    entry = FoodLogEntry(nutritionFood: match.food, slot: slot, amount: match.amount, kcal: match.kcalOverride, loggedAt: loggedAt)
                }
                if match.food.source == .openFoodFacts { NutritionCatalogService.shared.remember(match.food) }
                FoodLogStore.shared.add(entry)
                added.append(entry)
            }
            guard !added.isEmpty else { return VoiceOutcome(message: "Nothing was logged.") }
            NourloTips.foodLogged()
            let kcal = added.reduce(0) { $0 + $1.calories }
            let what = added.count == 1 ? added[0].name : "\(added.count) foods"
            let fromStock = added.filter { !StockStore.shared.draws(for: $0.id).isEmpty }.count
            let stockNote = fromStock == 0 ? "" : fromStock == added.count ? " Taken out of My Stock." : " \(fromStock) taken out of My Stock."
            // Undo takes the food off the log and puts what it took back into My Stock.
            return VoiceOutcome(message: "Logged \(what) to \(slot.title.lowercased()), \(kcal) kcal.\(stockNote)",
                                undo: { added.forEach { FoodLogStore.shared.remove($0) } })

        case .cart(let items, _):
            guard !items.isEmpty else { return VoiceOutcome(message: "Nothing was added.") }
            let cart = ShoppingCartService.shared
            items.forEach { cart.add($0, store: .catalog) }
            let what = items.count == 1 ? items[0].name : "\(items.count) items"
            return VoiceOutcome(message: "Added \(what) to your cart.",
                                undo: { items.forEach { cart.remove($0.id, store: ShopStore.catalog.name) } })

        case .checklist(let names):
            var list = GroceryStorage.load()
            var addedIDs: [String] = []
            for name in names where !list.contains(where: { $0.foodName.caseInsensitiveCompare(name) == .orderedSame && !$0.isBought }) {
                let id = "voice_" + UUID().uuidString
                list.append(GroceryItem(id: id, foodId: id, foodName: name, quantity: "1", estimatedPrice: 0,
                                        storeId: "unassigned", storeName: "", isBought: false, priceKnown: false))
                addedIDs.append(id)
            }
            guard !addedIDs.isEmpty else { return VoiceOutcome(message: "Already on your checklist.") }
            GroceryStorage.save(list)
            NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
            let what = addedIDs.count == 1 ? names.first ?? "1 item" : "\(addedIDs.count) items"
            return VoiceOutcome(message: "Added \(what) to your checklist.", undo: {
                GroceryStorage.save(GroceryStorage.load().filter { !addedIDs.contains($0.id) })
                NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
            })

        case .workout(let kind, let minutes):
            let length = minutes.map { "\($0)-minute " } ?? ""
            let name = kind.map { $0.title.lowercased() + " " } ?? ""
            return VoiceOutcome(message: "Opening a \(length)\(name)workout.", navigation: .workout(kind: kind, minutes: minutes))

        case .open(let screen):
            return VoiceOutcome(message: "Opening \(screen.spokenName).", navigation: .screen(screen))

        case .exercise(let exercise):
            return VoiceOutcome(message: "Showing \(exercise.name).", navigation: .exercise(exercise.id))

        case .answer(let text), .notUnderstood(let text):
            return VoiceOutcome(message: text)
        }
    }
}

extension VoiceScreen {
    var spokenName: String {
        switch self {
        case .home: return "Home"
        case .meals: return "your meal plan"
        case .shop: return "the shop"
        case .train: return "Train"
        case .cart: return "your cart"
        case .checklist: return "your checklist"
        case .profile: return "your profile"
        case .logFood: return "the food logger"
        case .chat: return "the chat"
        case .scan: return "the barcode scanner"
        }
    }
}

// MARK: - Amounts

/// Turns a spoken amount into the food's own measure (grams, millilitres or servings).
enum VoiceAmounts {

    /// Typical weight of one piece, in grams, by a word in the food's name.
    /// Used for counts ("2 eggs", "a banana"); matched on singular words.
    static let pieceGrams: [(word: String, grams: Double)] = [
        ("egg", 50), ("banana", 120), ("apple", 180), ("orange", 130), ("pear", 170), ("peach", 150), ("kiwi", 70),
        ("mandarin", 75), ("clementine", 75), ("plum", 65), ("apricot", 35), ("fig", 50), ("date", 8), ("strawberry", 12),
        ("grape", 5), ("cherry", 8), ("avocado", 150), ("tomato", 120), ("potato", 170), ("carrot", 60), ("cucumber", 200),
        ("onion", 110), ("pepper", 150), ("clove", 3), ("mushroom", 18), ("olive", 4), ("almond", 1.2), ("walnut", 5),
        ("cashew", 1.5), ("toast", 30), ("bread", 30), ("bagel", 95), ("croissant", 60), ("muffin", 110), ("donut", 60),
        ("doughnut", 60), ("pancake", 40), ("waffle", 75), ("tortilla", 45), ("wrap", 60), ("pita", 60), ("cookie", 15),
        ("biscuit", 12), ("cracker", 5), ("sausage", 75), ("nugget", 18), ("meatball", 30), ("patty", 110), ("burger", 110),
        ("breast", 170), ("thigh", 110), ("drumstick", 75), ("wing", 35), ("fillet", 150), ("steak", 200), ("chop", 150),
        ("dumpling", 20), ("sushi", 30), ("falafel", 17), ("pizza", 110), ("sandwich", 150), ("bar", 45), ("shrimp", 12), ("prawn", 12),
    ]

    private static let sliceGrams: [(word: String, grams: Double)] = [
        ("pizza", 110), ("cheese", 20), ("cake", 80), ("pie", 120), ("ham", 20), ("turkey", 20), ("salami", 8),
        ("bacon", 12), ("melon", 150), ("watermelon", 280), ("pineapple", 85), ("tomato", 20), ("cucumber", 7), ("lemon", 8),
    ]

    /// The amount to log, in the food's basis, and whether it was estimated
    /// from a typical size instead of said outright.
    static func amount(for phrase: VoiceFoodPhrase, food: NutritionFood) -> (amount: Double, estimated: Bool) {
        let result = rawAmount(for: phrase, food: food)
        let clamped = min(max(result.amount, food.minimumAmount), food.maximumAmount)
        return ((clamped * 100).rounded() / 100, result.estimated || clamped != result.amount)
    }

    private static func rawAmount(for phrase: VoiceFoodPhrase, food: NutritionFood) -> (amount: Double, estimated: Bool) {
        let count = phrase.quantity ?? 1
        // Foods measured in servings (own dishes, menu items) are counted.
        if food.basis == .serving {
            // "200 grams" of one is not 200 servings: one serving, for the person to set.
            if isUnsure(phrase, food: food) { return (1, true) }
            let exact = phrase.unit == nil || phrase.unit == .serving || phrase.unit == .piece
            return (count, !exact)
        }
        let piece = pieceWeight(of: phrase.name, food: food)
        guard let unit = phrase.unit else {
            // No amount at all: one piece, or the usual 100. A bare count: typical pieces.
            guard phrase.quantity != nil else { return (piece ?? food.defaultAmount, true) }
            return (count * (piece ?? food.defaultAmount), true)
        }
        switch unit {
        case .gram: return (count, food.basis != .grams)
        case .kilogram: return (count * 1000, food.basis != .grams)
        case .ounce: return (count * 28.35, food.basis != .grams)
        case .pound: return (count * 453.6, food.basis != .grams)
        // Volumes of a food measured by weight are taken 1 ml ≈ 1 g: an estimate.
        case .millilitre: return (count, food.basis != .millilitres)
        case .litre: return (count * 1000, food.basis != .millilitres)
        case .cup: return (count * 240, true)
        case .tablespoon: return (count * 15, true)
        case .teaspoon: return (count * 5, true)
        case .glass: return (count * 250, true)
        case .bowl: return (count * 300, true)
        case .can: return (count * 330, true)
        case .bottle: return (count * 500, true)
        case .handful: return (count * 30, true)
        case .slice: return (count * (sliceWeight(of: phrase.name) ?? 30), true)
        case .piece: return (count * (piece ?? food.defaultAmount), true)
        case .serving: return (count * food.defaultAmount, true)
        }
    }

    /// The weight of one piece and its name, for counting on the review card:
    /// "2 veggie burgers" → (110 g, "veggie burger"); "3 slices of bread" → (30 g, "slice");
    /// a weighed product whose label gives its slices → (21 g, "slice"). Nil when the food is only weighed.
    static func pieces(for phrase: VoiceFoodPhrase, food: NutritionFood, amount: Double) -> (Double?, String?) {
        guard food.basis != .serving, amount > 0 else { return (nil, nil) }
        let name = pieceLabel(phrase.name)
        if let count = phrase.quantity, count > 0 {
            switch phrase.unit {
            case nil, .piece?:
                if let piece = pieceWeight(of: phrase.name, food: food) ?? food.pieceAmount { return (piece, name) }
            case .slice?: return (amount / count, "slice")
            case .can?: return (amount / count, "can")
            case .bottle?: return (amount / count, "bottle")
            case .glass?: return (amount / count, "glass")
            case .bowl?: return (amount / count, "bowl")
            case .cup?: return (amount / count, "cup")
            case .handful?: return (amount / count, "handful")
            default: break
            }
        }
        // Weighed (a photo, "200 g"): counted only when the package says what a piece is.
        if let piece = food.pieceAmount, piece > 0 { return (piece, food.pieceName ?? name) }
        return (nil, nil)
    }

    /// "Veggie burgers" → "veggie burger".
    static func pieceLabel(_ name: String) -> String {
        var words = name.lowercased().split(separator: " ").map(String.init)
        if let last = words.last { words[words.count - 1] = OFFPackage.singular(last) }
        return words.joined(separator: " ")
    }

    /// A weight or volume was said for a food that is counted in servings, so
    /// the amount can't be worked out and must not save by itself.
    static func isUnsure(_ phrase: VoiceFoodPhrase, food: NutritionFood) -> Bool {
        guard food.basis == .serving, let unit = phrase.unit else { return false }
        switch unit {
        case .gram, .kilogram, .ounce, .pound, .millilitre, .litre: return true
        default: return false
        }
    }

    /// Catalogue groups whose foods are never eaten by the piece ("Spices, pepper, black").
    private static let notPieces: Set<String> = ["spice", "seasoning", "sauce", "powder", "juice", "soup", "oil", "beverage", "babyfood"]

    /// The typical weight of one piece, when the piece word is what the food is:
    /// the last word of the spoken name ("boiled eggs"), not a word describing
    /// something else ("almond milk", "potato chips", "apple pie").
    static func pieceWeight(of name: String, food: NutritionFood) -> Double? {
        let lead = Set(IntentSearch.words(food.name.split(separator: ",").first.map(String.init) ?? ""))
        guard lead.isDisjoint(with: notPieces) else { return nil }
        let spoken = IntentSearch.words(name)
        if let head = spoken.last, let grams = pieceGrams.first(where: { $0.word == head })?.grams { return grams }
        // One word that isn't a piece word, for a food named by one ("Egg, whole, raw").
        if spoken.count == 1, lead.count == 1, let word = lead.first {
            return pieceGrams.first { $0.word == word }?.grams
        }
        return nil
    }

    /// The typical weight of one slice: the last word first ("cheese cake" is a cake), then any word.
    private static func sliceWeight(of name: String) -> Double? {
        let spoken = IntentSearch.words(name)
        if let head = spoken.last, let grams = sliceGrams.first(where: { $0.word == head })?.grams { return grams }
        return sliceGrams.first { spoken.contains($0.word) }?.grams
    }
}
