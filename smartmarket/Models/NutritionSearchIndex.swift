import Foundation

/// Translations broaden ingredient matches; they never rename records or assign nutrients to dishes.
struct NutritionSearchIndex {
    private let rows: [(NutritionFood, String)]
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
        "فلافل": ["falafel"], "طعمية": ["falafel"], "طحينه": ["tahini"]
    ]
    init(foods: [NutritionFood]) {
        rows = foods.map { food in
            (food, Self.normalize(([food.name, food.brand ?? ""] + (food.searchNames ?? [])).joined(separator: " ")))
        }
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
        return rows.filter { row in groups.allSatisfy { options in options.contains { row.1.contains($0) } } }
            .map(\.0).sorted { a, b in
                if a.name.count != b.name.count { return a.name.count < b.name.count }
                return a.id < b.id
            }.prefix(limit).map { $0 }
    }
}
