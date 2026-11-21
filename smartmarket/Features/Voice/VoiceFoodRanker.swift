import Foundation

/// Picks the food a spoken name most likely means.
///
/// The catalogue search finds every food that mentions the words ("eggs" finds
/// egg yolk, eggnog and egg bread). Out loud, people mean the plain, common
/// form: whole eggs, a raw banana, cooked rice. This re-orders the search
/// results so that form comes first; the rest stay as alternatives to pick.
@MainActor
enum VoiceFoodRanker {

    /// What people say → how the catalogue names it.
    static let synonyms: [String: String] = [
        "toast": "bread white toasted", "fries": "french fries", "chips": "potato chips", "crisps": "potato chips",
        "porridge": "oatmeal", "oats": "oatmeal", "yoghurt": "yogurt", "greek yoghurt": "greek yogurt",
        "coke": "cola", "soda": "soft drink cola", "mince": "ground beef", "prawns": "shrimp", "prawn": "shrimp",
        "aubergine": "eggplant", "courgette": "zucchini", "coriander": "cilantro", "rocket": "arugula",
        "sweetcorn": "corn", "beetroot": "beets", "chickpeas": "chickpeas", "oj": "orange juice",
        "pb": "peanut butter", "protein shake": "high protein shake ready-to-drink", "spaghetti": "spaghetti cooked",
        "black coffee": "coffee brewed", "salad": "lettuce salad", "green salad": "lettuce salad", "burger": "hamburger", "chicken": "chicken breast", "turkey": "turkey breast", "cheddar": "cheese cheddar", "chocolate": "milk chocolate candy", "mozzarella": "cheese mozzarella",
        "feta": "cheese feta", "parmesan": "cheese parmesan", "halloumi": "cheese halloumi", "tea": "tea hot leaf black", "steak": "beef steak",
    ]

    /// Words that mark the plain form, strongest first.
    private static let plain: [(word: String, bonus: Double)] = [
        ("nf", 1.0), ("nfs", 1.0), ("whole", 0.8), ("raw", 0.8), ("plain", 0.6), ("cooked", 0.6), ("white", 0.5), ("brewed", 0.6),
        ("fresh", 0.5), ("regular", 0.5), ("tap", 0.4), ("boiled", 0.3), ("grilled", 0.3), ("roasted", 0.2), ("baked", 0.1),
    ]

    /// Words that mark a special form nobody means unless they say it.
    private static let special: Set<String> = [
        "dried", "dry", "canned", "frozen", "powder", "babyfood", "toddler", "mixture", "mix", "substitute", "yolk",
        "creamed", "deviled", "dehydrated", "sweetened", "flavored", "imitation", "fat", "skin", "feet", "back", "tail",
        "neck", "giblet", "liver", "gizzard", "heart", "oil", "flour", "sauce", "soup", "stew", "pie", "cake", "chip",
        "nectar", "pudding", "split", "dip", "dressing", "paper", "wine", "roll", "burrito", "taquito", "salad", "jerky",
        "curry", "patty", "pancake", "tube", "liquid", "puffed", "native", "alaska", "strained", "infant", "formula",
        "with", "and", "from", "restaurant", "fast", "school", "eaten", "ground", "bacon", "pickled", "evaporated",
        "condensed", "decaffeinated", "honey", "smoked", "fried", "light", "lowfat", "nonfat", "reduced", "meatless",
        "sandwich", "minced",
    ]

    /// Catalogue groups that lead a name ("Fish, salmon, raw"): the food is the word after them.
    private static let groups: Set<String> = ["fish", "nut", "beverage", "cereal", "vegetable", "fruit", "seed", "spice", "bean", "pork", "beef", "lamb"]

    /// Words said to the app, not eaten: never looked up as a food by themselves.
    private static let notFood: Set<String> = [
        "stop", "no", "yes", "yeah", "yep", "nope", "help", "hi", "hello", "hey", "run", "test", "ok", "okay",
        "cancel", "thanks", "start", "go", "back", "undo", "done", "what", "why", "how", "nothing", "never mind",
    ]

    /// True when a name said with nothing around it ("banana") plainly names this
    /// food: every word is a whole word of the food's name, one of them in its
    /// leading part ("Banana, raw"; "Fish, salmon, raw"). A word that only starts
    /// a food's name ("no" in "Noodles") doesn't count.
    static func plainlyNames(_ spoken: String, _ food: NutritionFood) -> Bool {
        let said = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        guard !said.isEmpty, !notFood.contains(said) else { return false }
        // A known everyday name ("toast", "fries") was searched by its catalogue name.
        if synonyms[said] != nil { return true }
        let wanted = Set(IntentSearch.words(said))
        guard !wanted.isEmpty else { return false }
        // A dish listed under these words ("cepelinai").
        if let names = food.searchNames, names.contains(where: { wanted.isSubset(of: Set(IntentSearch.words($0))) }) { return true }
        let segments = food.name.split(separator: ",").map { Set(IntentSearch.words(String($0))) }
        let all = segments.reduce(into: Set<String>()) { $0.formUnion($1) }
        guard wanted.isSubset(of: all), let first = segments.first else { return false }
        if !first.isDisjoint(with: wanted) { return true }
        return first.isSubset(of: groups) && segments.count > 1 && !segments[1].isDisjoint(with: wanted)
    }

    /// Foods for a spoken name, most likely first.
    static func foods(for name: String, limit: Int = 6,
                      search: (String) -> [NutritionFood]? = { _ in nil },
                      recentIDs: [String]? = nil) -> [NutritionFood] {
        let spoken = name.lowercased().trimmingCharacters(in: .whitespaces)
        let query = synonyms[spoken] ?? spoken
        func lookup(_ text: String) -> [NutritionFood] {
            search(text) ?? FoodEntityQuery.search(text, using: NutritionCatalogService.shared.searchLocal, limit: 60)
        }
        var candidates = lookup(query)
        // A synonym narrows the search; keep the literal words too, in case it found nothing.
        if query != spoken {
            var seen = Set(candidates.map(\.id))
            for food in lookup(spoken) where seen.insert(food.id).inserted { candidates.append(food) }
        }
        let wanted = Set(IntentSearch.words(query))
        let recent = Set(recentIDs ?? FoodLogStore.shared.recentFoodIDs)
        struct Ranked {
            let food: NutritionFood
            let score: Double
            let index: Int
        }
        var ranked: [Ranked] = []
        for (index, food) in candidates.enumerated() where food.isValid {
            ranked.append(Ranked(food: food, score: score(food, wanted: wanted, isRecent: recent.contains(food.id)), index: index))
        }
        ranked.sort { a, b in a.score != b.score ? a.score < b.score : a.index < b.index }
        // The same food from two datasets shows once.
        var names = Set<String>()
        var result: [NutritionFood] = []
        for item in ranked where names.insert(item.food.name.lowercased()).inserted {
            result.append(item.food)
            if result.count == limit { break }
        }
        return result
    }

    /// Lower is better.
    static func score(_ food: NutritionFood, wanted: Set<String>, isRecent: Bool) -> Double {
        let segments = food.name.split(separator: ",").map { Set(IntentSearch.words(String($0))) }
        let all = segments.reduce(into: Set<String>()) { $0.formUnion($1) }
        let first = segments.first ?? []
        let firstTwo = first.union(segments.dropFirst().first ?? [])

        var score: Double
        if first == wanted {
            score = 0                                   // "Banana, raw" for "banana"
        } else if wanted.isSubset(of: firstTwo), first.isSubset(of: wanted) {
            score = 0.5                                 // "Chicken, breast, …" for "chicken breast"
        } else if first.isSubset(of: groups), segments.count > 1, segments[1] == wanted {
            score = 0.3                                 // "Fish, salmon, raw" for "salmon"
        } else if wanted.isSubset(of: first) {
            score = 2 + 0.8 * Double(first.count - wanted.count)   // "Banana split"
        } else if wanted.isSubset(of: all) {
            score = 3                                   // "Fish, salmon, raw" for "salmon"
        } else {
            score = 5 + Double(wanted.subtracting(all).count)
        }
        // A dish listed under exactly these words ("cepelinai") is the one meant, not a variant of it.
        if let names = food.searchNames, names.contains(where: { Set(IntentSearch.words($0)) == wanted }) { score -= 5 }
        // Own dishes and scanned products are things the person actually eats.
        if food.source == .recipe || food.source == .menu { score -= 1 }
        // What the person has logged before outweighs any guess about the plain form.
        if isRecent { score -= 2.5 }

        let extras = all.subtracting(wanted)
        // "Whole wheat" and "whole grain" are kinds, not the plain form.
        let wholeIsAKind = extras.contains("wheat") || extras.contains("grain")
        // The strongest plain word counts in full, a second one a little ("plain, whole milk").
        let bonuses = plain.filter { extras.contains($0.word) && !($0.word == "whole" && wholeIsAKind) }
            .map(\.bonus).sorted(by: >)
        score -= (bonuses.first ?? 0) + 0.3 * (bonuses.dropFirst().first ?? 0)
        // A restaurant or brand in capitals ("DENNY'S, french fries") is never the general food.
        if let lead = food.name.split(separator: ",").first, lead.count > 2, lead == lead.uppercased(), lead.contains(where: \.isLetter) {
            score += 2
        }
        score += 1.5 * Double(extras.intersection(special).count)
        // Shorter names are the more general food.
        score += 0.015 * Double(food.name.count)
        return score
    }
}
