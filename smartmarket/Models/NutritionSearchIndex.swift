import Foundation

/// Translations broaden ingredient matches; they never rename records or assign nutrients to dishes.
///
/// Results are ranked by how well the name answers the query, not by length: "chicken"
/// leads with foods that are chicken ("Chicken, breast…", "Chicken, NFS"), then foods
/// with chicken in them, and only last names that merely contain the letters ("tea" in
/// "steak").
nonisolated struct NutritionSearchIndex: Sendable {
    private struct Row: Sendable {
        let food: NutritionFood
        let text: String
        /// Every word of the name, and the words of its leading part (before the first comma).
        let words: [String]
        let lead: [String]
        let plain: Bool
        /// Everyday forms come first (a chicken breast before chicken giblets).
        let rarity: Int
    }
    private static let uncommon: Set<String> = ["giblets", "liver", "heart", "gizzard", "capons", "stewing", "roasting", "meatless",
        "feet", "skin", "neck", "back", "dried", "dehydrated", "powder", "canned", "babyfood", "infant", "reduced", "imitation",
        "substitute", "sprouted", "pickled", "frozen", "glutinous", "malted", "sheep", "goat", "overripe", "low", "sodium",
        "fortified", "restaurant", "school", "fast", "separable", "tongue", "kidney", "brain", "tripe", "cornish", "wild"]
    private static let everyday: Set<String> = ["breast", "thigh", "drumstick", "wing", "whole", "white", "brown", "fillet",
        "boneless", "skinless", "ground", "plain", "fresh", "long"]
    private let rows: [Row]
    private static let aliases: [String: [String]] = [
        "ryziai": ["rice"], "virti": ["cooked", "boiled"], "virtas": ["cooked", "boiled"],
        "zalias": ["raw"], "zali": ["raw"], "vistiena": ["chicken"], "vistienos": ["chicken"],
        "krutinele": ["breast"], "bulves": ["potato", "potatoes"], "bulviu": ["potato", "potatoes"],
        "kiausiniai": ["egg", "eggs"], "pienas": ["milk"], "duona": ["bread"],
        "varske": ["cottage", "quark"], "grikiai": ["buckwheat"], "jogurtas": ["yogurt"],
        "avizos": ["oats"], "suris": ["cheese"], "lasisa": ["salmon"], "obuoliai": ["apple", "apples"],
        "lesiai": ["lentils"], "pupeles": ["beans"], "agurkai": ["cucumber"], "pomidorai": ["tomato", "tomatoes"],
        "رز": ["rice"], "ارز": ["rice"], "مطبوخ": ["cooked", "boiled"], "مسلوق": ["cooked", "boiled"],
        "ني": ["raw"], "نيء": ["raw"], "فراخ": ["chicken"], "دجاج": ["chicken"],
        "صدور": ["breast"], "لحم": ["beef", "lamb", "meat"], "لحمة": ["beef", "lamb", "meat"],
        "سمك": ["fish"], "بيض": ["egg", "eggs"], "لبن": ["milk", "yogurt"], "حليب": ["milk"],
        "زبادي": ["yogurt"], "جبنة": ["cheese"], "جبن": ["cheese"], "عدس": ["lentils"],
        "فول": ["fava", "broadbeans"], "حمص": ["chickpeas", "hummus"], "عيش": ["bread"], "خبز": ["bread"],
        "بطاطس": ["potato", "potatoes"], "طماطم": ["tomato", "tomatoes"], "خيار": ["cucumber"],
        "بصل": ["onion", "onions"], "زيت": ["oil"], "زيتون": ["olive"], "مكرونة": ["pasta", "macaroni"],
        "مكرونه": ["pasta", "macaroni"], "شوفان": ["oats"], "موز": ["banana", "bananas"],
        "تفاح": ["apple", "apples"], "برتقال": ["orange", "oranges"], "طحينة": ["tahini"],
        "فلافل": ["falafel"], "طعمية": ["falafel"], "طحينه": ["tahini"],
        // Spellings and names the data doesn't use.
        "yoghurt": ["yogurt"], "yoghurts": ["yogurt"], "aubergine": ["eggplant"], "courgette": ["zucchini"],
        "prawn": ["shrimp"], "prawns": ["shrimp"], "mince": ["ground"], "minced": ["ground"], "porridge": ["oatmeal"],
        "beetroot": ["beets"], "rocket": ["arugula"], "coriander": ["cilantro"], "chilli": ["chili"],
        "wholemeal": ["whole wheat"], "sweetcorn": ["corn"], "crisps": ["chips"], "biscuit": ["cookie"],
        "biscuits": ["cookies"], "courgettes": ["zucchini"], "aubergines": ["eggplant"]
    ]
    init(foods: [NutritionFood]) {
        rows = foods.map { food in
            let name = Self.normalize(food.name)
            let text = Self.normalize(([food.name, food.brand ?? ""] + (food.searchNames ?? [])).joined(separator: " "))
            let lead = name.split(separator: ",").first.map(String.init) ?? name
            let lowered = " " + name + " "
            let plain = lowered.contains(" raw") || lowered.contains(" nfs") || lowered.contains(" cooked")
            let words = Self.tokens(text)
            let rarity = (words.contains(where: Self.uncommon.contains) ? 25 : 0) - (words.contains(where: Self.everyday.contains) ? 10 : 0)
            return Row(food: food, text: text, words: words, lead: Self.tokens(lead), plain: plain, rarity: rarity)
        }
    }
    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
    /// The same word, allowing a plural ending ("egg" for "eggs", "tomato" for "tomatoes").
    private static func same(_ word: String, _ query: String) -> Bool {
        word == query || word == query + "s" || word == query + "es" || query == word + "s" || query == word + "es"
    }
    static func normalize(_ input: String) -> String {
        input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا").replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "ـ", with: "")
    }
    func search(_ query: String, limit: Int = 60) -> [NutritionFood] {
        let words = Self.normalize(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        let groups = words.map { word in [word] + (Self.aliases[word] ?? []) }
        var scored: [(score: Int, food: NutritionFood)] = []
        for row in rows {
            var score = 0
            var matched = true
            for (g, options) in groups.enumerated() {
                // 0 the food is this (leading word), 1 a whole word of the name, 2 a word starts
                // with it, 5 the letters only appear inside another word.
                var best = Int.max
                for option in options {
                    let kind: Int
                    if option.contains(" ") { kind = row.text.contains(option) ? 1 : Int.max }
                    // "Chicken, breast…" is chicken (0); "Chicken skin" or "Fried chicken" has chicken in it (1).
                    else if row.lead.contains(where: { Self.same($0, option) }) { kind = row.lead.count == 1 && g == 0 ? 0 : 1 }
                    else if row.words.contains(where: { Self.same($0, option) }) { kind = 2 }
                    else if row.words.contains(where: { $0.hasPrefix(option) }) { kind = 3 }
                    else if option.count >= 4, row.text.contains(option) { kind = 6 }
                    else { kind = Int.max }
                    best = min(best, kind)
                }
                guard best != Int.max else { matched = false; break }
                score += best * 100
            }
            guard matched else { continue }
            // Then the plain, common form (raw, cooked, "NFS"), then the shorter name.
            score += (row.plain ? 0 : 30) + row.rarity + min(row.food.name.count, 60) / 2
            scored.append((score, row.food))
        }
        scored.sort { a, b in a.score != b.score ? a.score < b.score : a.food.id < b.food.id }
        // The catalogue lists some foods twice with the same values: show one.
        var seen = Set<String>()
        var out: [NutritionFood] = []
        for item in scored {
            let key = item.food.name.lowercased() + "|" + String(Int(item.food.kcal.rounded()))
            guard seen.insert(key).inserted else { continue }
            out.append(item.food)
            if out.count == limit { break }
        }
        return out
    }
}
