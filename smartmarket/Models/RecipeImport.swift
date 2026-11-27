import Foundation

// MARK: - A recipe the person is following
//
// "Add a recipe I'm following": the recipe arrives as pasted text, a web page (its
// schema.org Recipe JSON-LD when it has one, else the page's text) or a photo read on
// the phone with Vision. Each ingredient line ("200 g spaghetti", "1 ½ cups milk",
// "2 eggs") is read into an amount and a name, matched to Nourlo's own food data,
// and turned into grams; the nutrition is the sum, divided by the servings it makes.

/// One ingredient line as written, read into an amount, a unit and a name.
nonisolated struct RecipeLine: Hashable, Sendable {
    let text: String
    let quantity: Double?
    let unit: String?
    let name: String
}

nonisolated struct ParsedRecipe: Hashable, Sendable {
    var title: String
    /// How many servings the recipe says it makes (nil when it doesn't say).
    var servings: Double?
    var lines: [RecipeLine]
}

nonisolated enum RecipeTextParser {
    static let fractions: [Character: String] = ["½": " 1/2", "¼": " 1/4", "¾": " 3/4", "⅓": " 1/3", "⅔": " 2/3",
                                                 "⅛": " 1/8", "⅜": " 3/8", "⅝": " 5/8", "⅞": " 7/8", "⅕": " 1/5"]

    /// Units as written → the canonical name `RecipeAmounts` understands.
    static let units: [String: String] = [
        "g": "g", "gr": "g", "gram": "g", "grams": "g", "gramme": "g", "grammes": "g",
        "kg": "kg", "kilo": "kg", "kilos": "kg", "kilogram": "kg", "kilograms": "kg",
        "mg": "mg", "ml": "ml", "millilitre": "ml", "milliliter": "ml", "millilitres": "ml", "milliliters": "ml",
        "l": "l", "litre": "l", "liter": "l", "litres": "l", "liters": "l", "dl": "dl", "cl": "cl",
        "cup": "cup", "cups": "cup", "c": "cup",
        "tbsp": "tbsp", "tbs": "tbsp", "tbl": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "T": "tbsp",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp", "t": "tsp",
        "oz": "oz", "ounce": "oz", "ounces": "oz", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "pinch": "pinch", "pinches": "pinch", "dash": "pinch",
        "clove": "clove", "cloves": "clove", "can": "can", "cans": "can", "tin": "can", "tins": "can",
        "slice": "slice", "slices": "slice", "stick": "stick", "sticks": "stick",
        "handful": "handful", "handfuls": "handful", "package": "package", "packages": "package", "pack": "package",
        "packet": "package", "bunch": "bunch", "bunches": "bunch",
    ]

    /// Words that describe the cut or state, not the food ("2 large onions, finely chopped").
    static let preparation: Set<String> = ["chopped", "diced", "sliced", "grated", "shredded", "crushed", "fresh",
                                           "freshly", "finely", "roughly", "thinly", "large", "small", "medium", "big",
                                           "peeled", "cubed", "melted", "softened", "beaten", "optional",
                                           "about", "approximately", "heaped", "level", "packed", "room", "temperature"]

    /// Headers that end the ingredients ("Method", "Instructions" …).
    static let stepHeaders = ["method", "instructions", "directions", "steps", "preparation", "how to make", "to make"]

    /// "1 1/2" → 1.5, "3/4" → 0.75, "2,5" → 2.5, "2-3" → 2.5.
    static func number(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        var total = 0.0
        for part in parts {
            if part.contains("/") {
                let bits = part.split(separator: "/")
                guard bits.count == 2, let a = Double(bits[0]), let b = Double(bits[1]), b != 0 else { return nil }
                total += a / b
            } else if let value = Double(part.replacingOccurrences(of: ",", with: ".")) {
                total += value
            } else { return nil }
        }
        return total
    }

    /// Reads "1 ½ cups whole milk" into (1.5, "cup", "whole milk").
    static func line(_ raw: String) -> RecipeLine? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bullets and numbering.
        text = text.replacingOccurrences(of: #"^[\-•*·▪◦–—]+\s*"#, with: "", options: .regularExpression)
        guard !text.isEmpty, text.count <= 200 else { return nil }
        var expanded = ""
        for ch in text { expanded += fractions[ch] ?? String(ch) }
        expanded = expanded.replacingOccurrences(of: #"(\d)\s+(\d/\d)"#, with: "$1 $2", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var quantity: Double?
        var rest = expanded
        let pattern = #"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?)(?:\s*(?:-|–|to)\s*(\d+(?:[.,]\d+)?))?"#
        if let range = rest.range(of: pattern, options: .regularExpression) {
            let matched = String(rest[range])
            let pieces = matched.components(separatedBy: CharacterSet(charactersIn: "-–")).flatMap { $0.components(separatedBy: " to ") }
            let values = pieces.compactMap(number)
            quantity = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            rest = String(rest[range.upperBound...])
        } else if let range = rest.range(of: #"^(a|an|one)\s+"#, options: [.regularExpression, .caseInsensitive]) {
            quantity = 1
            rest = String(rest[range.upperBound...])
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        // "200g" written together leaves "g pasta".
        var unit: String?
        if let word = rest.split(separator: " ", maxSplits: 1).first.map(String.init) {
            let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            // A unit only right after a number; "T" is a tablespoon, "t" a teaspoon.
            if quantity != nil, let canonical = units[bare] ?? units[bare.lowercased()] {
                unit = canonical
                rest = String(rest.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if rest.lowercased().hasPrefix("of ") { rest = String(rest.dropFirst(3)) }
        let name = cleanName(rest)
        guard !name.isEmpty else { return nil }
        return RecipeLine(text: text, quantity: quantity, unit: unit, name: name)
    }

    /// "large onions, finely chopped (about 300 g)" → "onions".
    static func cleanName(_ text: String) -> String {
        var name = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        if let comma = name.firstIndex(of: ",") { name = String(name[..<comma]) }
        name = name.replacingOccurrences(of: #"(?i)\b(to taste|for serving|for garnish|or more|as needed)\b.*$"#, with: "", options: .regularExpression)
        let words = name.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            .filter { !preparation.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
    }

    /// "Serves 4", "Makes 6 servings", "Yield: 4 portions", "4 servings".
    static func servings(_ text: String) -> Double? {
        let patterns = [#"(?i)\b(?:serves|servings?|yield|yields|makes|portions?)\s*[:\-]?\s*(\d+(?:[.,]\d+)?)"#,
                        #"(?i)(\d+(?:[.,]\d+)?)\s*(?:servings|portions|people|persons)\b"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let value = Double(text[range].replacingOccurrences(of: ",", with: ".")), value > 0, value <= 100 else { continue }
            return value
        }
        return nil
    }

    /// A whole recipe as text: its title, servings and ingredient lines. With an
    /// "Ingredients" heading, the lines under it (to the method); otherwise every line
    /// that starts with an amount.
    static func parse(_ text: String) -> ParsedRecipe {
        let rawLines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var title = ""
        var servingsFound: Double?
        var lines: [RecipeLine] = []
        let headerIndex = rawLines.firstIndex { $0.lowercased().trimmingCharacters(in: .punctuationCharacters).hasPrefix("ingredients") }
        for (index, raw) in rawLines.enumerated() {
            let lower = raw.lowercased()
            if servingsFound == nil, let s = servings(raw), raw.count < 60 { servingsFound = s; continue }
            if title.isEmpty, headerIndex.map({ index < $0 }) ?? true, raw.count <= 80,
               raw.range(of: #"^\s*[\-•*]?\s*\d"#, options: .regularExpression) == nil { title = raw; continue }
            if let headerIndex {
                guard index > headerIndex else { continue }
                if stepHeaders.contains(where: { lower.trimmingCharacters(in: .punctuationCharacters).hasPrefix($0) }) { break }
                if let line = line(raw) { lines.append(line) }
            } else if raw.range(of: #"^\s*[\-•*]?\s*(\d|[½¼¾⅓⅔⅛]|a |an |one )"#, options: [.regularExpression, .caseInsensitive]) != nil,
                      raw.count <= 120, let line = line(raw) {
                lines.append(line)
            }
        }
        return ParsedRecipe(title: title.isEmpty ? "My recipe" : String(title.prefix(80)), servings: servingsFound, lines: lines)
    }
}

/// A recipe in a web page's schema.org JSON-LD (`"@type": "Recipe"`).
nonisolated enum RecipeWebReader {
    static func recipe(fromHTML html: String) -> ParsedRecipe? {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let data = String(html[range]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = findRecipe(json), let parsed = parsed(recipe) { return parsed }
        }
        return nil
    }

    static func findRecipe(_ json: Any) -> [String: Any]? {
        if let list = json as? [Any] { return list.lazy.compactMap(findRecipe).first }
        guard let object = json as? [String: Any] else { return nil }
        let type = object["@type"]
        let types = (type as? [String]) ?? (type as? String).map { [$0] } ?? []
        if types.contains(where: { $0.lowercased() == "recipe" }) { return object }
        if let graph = object["@graph"] { return findRecipe(graph) }
        if let main = object["mainEntity"] { return findRecipe(main) }
        return nil
    }

    static func parsed(_ recipe: [String: Any]) -> ParsedRecipe? {
        let ingredients = (recipe["recipeIngredient"] as? [String]) ?? (recipe["ingredients"] as? [String]) ?? []
        let lines = ingredients.map(decodeEntities).compactMap(RecipeTextParser.line)
        guard !lines.isEmpty else { return nil }
        let title = (recipe["name"] as? String).map(decodeEntities) ?? "My recipe"
        var servings: Double?
        let yields: [Any] = (recipe["recipeYield"] as? [Any]) ?? recipe["recipeYield"].map { [$0] } ?? []
        for value in yields {
            if let number = value as? NSNumber { servings = number.doubleValue; break }
            if let text = value as? String {
                if let found = RecipeTextParser.servings(text) ?? RecipeTextParser.number(text.components(separatedBy: " ").first ?? "") {
                    servings = found
                    break
                }
            }
        }
        return ParsedRecipe(title: String(title.prefix(80)), servings: servings.flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }, lines: lines)
    }

    /// The page as plain text, one block per line, for pages without JSON-LD.
    static func text(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: #"<(script|style)[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<(br|/p|/li|/h\d|/div|/tr)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(text).components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func decodeEntities(_ text: String) -> String {
        var out = text
        for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
                               "&nbsp;": " ", "&frac12;": "½", "&frac14;": "¼", "&frac34;": "¾", "&#x27;": "'"] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: &#189; → ½
        if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            for match in regex.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(match.range, in: out), let digits = Range(match.range(at: 1), in: out),
                      let code = UInt32(out[digits]), let scalar = Unicode.Scalar(code) else { continue }
                out.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return out
    }
}

/// Grams for an ingredient amount ("1.5 cup" of flour → 187.5 g).
nonisolated enum RecipeAmounts {
    /// One cup of a food, in grams, by a word in its name (240 ml of it).
    static let cupGrams: [(word: String, grams: Double)] = [
        ("flour", 125), ("powdered", 120), ("icing", 120), ("brown sugar", 220), ("sugar", 200), ("rice", 185),
        ("oat", 90), ("butter", 227), ("milk", 245), ("water", 240), ("cream", 240), ("yogurt", 245), ("yoghurt", 245),
        ("cheese", 113), ("oil", 218), ("honey", 340), ("syrup", 320), ("broth", 240), ("stock", 240), ("bean", 180),
        ("lentil", 190), ("pasta", 100), ("nut", 140), ("almond", 140), ("berry", 150), ("berries", 150), ("chip", 170),
        ("cocoa", 85), ("spinach", 30), ("lettuce", 50), ("tomato", 180), ("corn", 165), ("pea", 145), ("quinoa", 170),
        ("coconut", 85), ("raisin", 150), ("breadcrumb", 110), ("juice", 245), ("wine", 240), ("sauce", 250),
    ]

    static func perCup(_ name: String) -> Double {
        let lower = name.lowercased()
        return cupGrams.first { lower.contains($0.word) }?.grams ?? 200
    }

    /// The grams, and whether it's an estimate (a volume or a count, not a weight).
    static func grams(for line: RecipeLine, pieceWeight: Double?) -> (grams: Double, estimated: Bool)? {
        guard let quantity = line.quantity, quantity > 0 else { return nil }
        switch line.unit {
        case "g"?: return (quantity, false)
        case "kg"?: return (quantity * 1000, false)
        case "mg"?: return (quantity / 1000, false)
        case "oz"?: return (quantity * 28.35, false)
        case "lb"?: return (quantity * 453.6, false)
        case "ml"?: return (quantity * perCup(line.name) / 240, true)
        case "l"?: return (quantity * 1000 * perCup(line.name) / 240, true)
        case "dl"?: return (quantity * 100 * perCup(line.name) / 240, true)
        case "cl"?: return (quantity * 10 * perCup(line.name) / 240, true)
        case "cup"?: return (quantity * perCup(line.name), true)
        case "tbsp"?: return (quantity * perCup(line.name) / 16, true)
        case "tsp"?: return (quantity * perCup(line.name) / 48, true)
        case "pinch"?: return (quantity * 0.4, true)
        case "clove"?: return (quantity * 3, true)
        case "can"?: return (quantity * 400, true)
        case "slice"?: return (quantity * (pieceWeight ?? 30), true)
        case "stick"?: return (quantity * 113, true)
        case "handful"?: return (quantity * 30, true)
        case "package"?: return (quantity * 250, true)
        case "bunch"?: return (quantity * 100, true)
        default: return (quantity * (pieceWeight ?? 100), true)
        }
    }
}
