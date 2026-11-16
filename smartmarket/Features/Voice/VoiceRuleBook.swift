import Foundation

// MARK: - What a spoken phrase can mean

/// One food as it was said: "two eggs", "200 grams of chicken", "a cup of rice".
struct VoiceFoodPhrase: Equatable {
    var name: String
    /// nil when no amount was said ("some rice", "toast").
    var quantity: Double?
    var unit: VoiceUnit?
}

/// Units people say out loud. `piece` covers "2 eggs" said with a counting word.
enum VoiceUnit: String, Equatable, CaseIterable {
    case gram, kilogram, ounce, pound
    case millilitre, litre, cup, tablespoon, teaspoon, glass, bowl, can, bottle
    case slice, piece, handful, serving
}

/// Screens a phrase can ask for.
enum VoiceScreen: String, Equatable, CaseIterable {
    case home, meals, shop, train, cart, checklist, profile, logFood, chat, scan
}

/// What the rule book understood. `unknown` keeps the cleaned text, so a later
/// step (a food lookup, then AI) can still try.
enum VoiceCommand: Equatable {
    case logFood(items: [VoiceFoodPhrase], slot: MealSlot?)
    case addToCart([String])
    case addToChecklist([String])
    case startWorkout(kind: ExerciseKind?, minutes: Int?)
    case open(VoiceScreen)
    case showExercise(String)
    case caloriesLeft
    case unknown(String)
}

// MARK: - The rule book
//
// Plain rules, no network and no model: the same phrase always gives the same
// answer, instantly and offline. The logic below is the same for every
// language; all the words and sentence patterns live in a `VoiceLexicon`
// (English, German, Arabic, Lithuanian), so another language is another
// lexicon, not new logic.
//
// Order matters: the most specific meaning is tried first (a question about
// calories, a workout, a destination named in the phrase) and food logging
// last, because almost anything can be a food name.
//
// Foods, cart items and exercises come out with English names, because the
// food list, the catalogue and the exercise library are in English: each
// lexicon carries a small dictionary for that ("Eier" → "eggs").

enum VoiceRuleBook {

    /// `tolerant` also accepts a word that is a letter or two away from one the
    /// lexicon knows ("joutiana" for "jautiena"): speech models mishear, most of
    /// all in the smaller languages. The caller tries the exact reading first and
    /// shows a tolerant one for a tap instead of saving it by itself.
    static func parse(_ spoken: String, language: VoiceLanguage = .english, tolerant: Bool = false) -> VoiceCommand {
        var lexicon = language.lexicon
        lexicon.tolerant = tolerant
        let text = stripFillers(normalize(spoken, lexicon), lexicon)
        guard !text.isEmpty else { return .unknown("") }

        if isCaloriesQuestion(text, lexicon) { return .caloriesLeft }
        if let exercise = exerciseQuestion(text, lexicon) { return .showExercise(exercise) }
        if let workout = workout(text, lexicon) { return workout }
        if let list = shopping(text, lexicon) { return list }
        if let screen = destination(text, lexicon) { return .open(screen) }
        if let food = foodLog(text, lexicon) { return food }
        return .unknown(text)
    }

    // MARK: Cleaning

    /// Lowercased, with punctuation removed (decimal points, fraction slashes
    /// and apostrophes kept) and spaces collapsed. "200g" becomes "200 g".
    static func normalize(_ spoken: String, _ lexicon: VoiceLexicon = .english) -> String {
        var text = lexicon.clean(spoken.lowercased())
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "،", with: ",")
        // "1,5" said the continental way is one and a half, not two foods.
        text = text.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)
        // Commas separate foods; keep them as their own token.
        text = text.replacingOccurrences(of: ",", with: " , ")
        // A decimal point stays only between digits ("1.5"); other dots go.
        text = text.replacingOccurrences(of: #"(?<!\d)\.|\.(?!\d)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[^\p{L}\p{M}\p{Nd}.,/' ]"#, with: " ", options: .regularExpression)
        // "200g", "250ml", "2kg": split the unit off the number.
        text = text.replacingOccurrences(of: #"(\d)(\p{L})"#, with: "$1 $2", options: .regularExpression)
        return text.split(separator: " ").joined(separator: " ")
    }

    /// Politeness and the app's name carry no meaning.
    private static func stripFillers(_ text: String, _ lexicon: VoiceLexicon) -> String {
        var text = text
        for _ in 0..<2 {
            for filler in lexicon.fillers + ["^, "] {
                text = text.replacingOccurrences(of: filler, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            }
        }
        return text.split(separator: " ").joined(separator: " ")
    }

    // MARK: Calories

    private static func isCaloriesQuestion(_ text: String, _ lexicon: VoiceLexicon) -> Bool {
        guard lexicon.calorieWords.contains(where: text.contains) else { return false }
        return lexicon.calorieCues.contains(where: text.contains)
    }

    // MARK: Exercises

    /// "how do i do a push up", "show me how to do squats", "show the plank exercise".
    private static func exerciseQuestion(_ text: String, _ lexicon: VoiceLexicon) -> String? {
        for pattern in lexicon.exercisePatterns {
            guard let name = firstCapture(pattern, in: text) else { continue }
            let cleaned = name.split(separator: " ").map(String.init).filter { !lexicon.exerciseNoise.contains($0) }.joined(separator: " ")
            if !cleaned.isEmpty { return lexicon.translate(cleaned, with: lexicon.exercises) }
        }
        return nil
    }

    // MARK: Workouts

    private static func workout(_ text: String, _ lexicon: VoiceLexicon) -> VoiceCommand? {
        let words = text.split(separator: " ").map(String.init)
        let namesWorkout = words.contains { lexicon.matches($0, lexicon.workoutNouns) } || lexicon.workoutPhrases.contains(where: text.contains)
        guard namesWorkout else { return nil }
        // "log my workout" isn't a request to build one, and a food phrase can't hold these nouns.
        let asksForOne = words.contains { lexicon.matches($0, lexicon.workoutVerbs) }
            || lexicon.workoutCues.contains(where: text.contains) || words.count <= 4
        guard asksForOne else { return nil }
        let kind = lexicon.workoutKinds.first { kind in words.contains { lexicon.matches($0, kind.words) } }?.kind
        return .startWorkout(kind: kind, minutes: minutes(in: text, lexicon))
    }

    /// "30 minute", "45 mins", "half an hour", "an hour", "1 hour".
    static func minutes(in text: String, _ lexicon: VoiceLexicon = .english) -> Int? {
        let numbered = numberWordsToDigits(text, lexicon)
        if let value = firstCapture(#"(\d+(?:\.\d+)?) ?(?:"# + lexicon.minuteWords + #")(?= |$)"#, in: numbered), let n = Double(value) {
            return Int(n.rounded())
        }
        if lexicon.halfHourPhrases.contains(where: numbered.contains) { return 30 }
        if let value = firstCapture(#"(\d+(?:\.\d+)?) ?(?:"# + lexicon.hourWords + #")(?= |$)"#, in: numbered), let n = Double(value) {
            return Int((n * 60).rounded())
        }
        if lexicon.oneHourPhrases.contains(where: numbered.contains) { return 60 }
        return nil
    }

    // MARK: Cart and checklist

    private static func shopping(_ text: String, _ lexicon: VoiceLexicon) -> VoiceCommand? {
        for pattern in lexicon.cartPatterns {
            if let items = firstCapture(pattern, in: text) {
                return named(items, lexicon, translated: true).map(VoiceCommand.addToCart)
            }
        }
        for pattern in lexicon.checklistPatterns {
            // The checklist is the person's own list: names stay as they said them.
            if let items = firstCapture(pattern, in: text) {
                return named(items, lexicon, translated: false).map(VoiceCommand.addToChecklist)
            }
        }
        return nil
    }

    /// Item names from "milk, eggs and two loaves of bread": amounts dropped, since the cart counts in whole products.
    private static func named(_ items: String, _ lexicon: VoiceLexicon, translated: Bool) -> [String]? {
        let names = foodPhrases(items, lexicon, translated: translated).map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    // MARK: Destinations

    private static func destination(_ text: String, _ lexicon: VoiceLexicon) -> VoiceScreen? {
        for pattern in lexicon.openPatterns {
            guard let target = firstCapture(pattern, in: text) else { continue }
            let cleaned = target.split(separator: " ").map(String.init).filter { !lexicon.screenNoise.contains($0) }.joined(separator: " ")
            return lexicon.screens.first { $0.names.contains(cleaned) }?.screen
        }
        // A bare screen name ("cart", "meal plan") is enough.
        return lexicon.screens.first { $0.names.contains(text) }?.screen
    }

    // MARK: Food

    private static func foodLog(_ text: String, _ lexicon: VoiceLexicon) -> VoiceCommand? {
        var rest = text
        var slot: MealSlot?
        // The meal can be anywhere: "for breakfast i had…", "…as a snack", "log to dinner…".
        for meal in lexicon.meals {
            for name in meal.names {
                let pattern = #"(?:^| )"# + lexicon.mealPrefix + name + lexicon.mealSuffix + #"(?= |$)"#
                if let range = rest.range(of: pattern, options: .regularExpression) {
                    slot = meal.slot
                    rest.replaceSubrange(range, with: " ")
                    break
                }
            }
            if slot != nil { break }
        }
        // A misheard meal: "bakarenei" for "vakarienei".
        if slot == nil, lexicon.tolerant {
            var words = rest.split(separator: " ").map(String.init)
            var best: (index: Int, slot: MealSlot, distance: Int)?
            for (index, word) in words.enumerated() {
                for meal in lexicon.meals {
                    for name in meal.names {
                        if let distance = VoiceSpelling.near(word, name), distance < best?.distance ?? .max { best = (index, meal.slot, distance) }
                    }
                }
            }
            if let best {
                slot = best.slot
                words.remove(at: best.index)
                rest = words.joined(separator: " ")
            }
        }
        rest = rest.split(separator: " ").joined(separator: " ")
        // Drop the verb: "log", "i just had", "add", "i ate"…
        var hadVerb = false
        for verb in lexicon.foodVerbs where rest == verb || rest.hasPrefix(verb + " ") {
            rest = String(rest.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
            hadVerb = true
            break
        }
        // A misheard one-word verb at the start: "sivalgiau" for "suvalgiau".
        if !hadVerb, lexicon.tolerant, let first = rest.split(separator: " ").first.map(String.init), first != rest,
           lexicon.foodVerbs.contains(where: { VoiceSpelling.near(first, $0) != nil }) {
            rest = String(rest.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
            hadVerb = true
        }
        let items = foodPhrases(rest, lexicon, translated: true).filter { !$0.name.isEmpty }
        guard !items.isEmpty else { return nil }
        // Without a verb or a meal, only a phrase that starts with an amount
        // ("two eggs and toast") is taken as food; anything else stays unknown.
        if !hadVerb, slot == nil, items.first?.quantity == nil { return nil }
        return .logFood(items: items, slot: slot)
    }

    /// Splits "2 eggs, a slice of toast and 200 g of yoghurt" into its foods.
    static func foodPhrases(_ text: String, _ lexicon: VoiceLexicon = .english, translated: Bool = true) -> [VoiceFoodPhrase] {
        var numbered = numberWordsToDigits(text, lexicon)
        // Fractions and vague amounts, before the word for "and" is used as a separator.
        for (pattern, replacement) in lexicon.amountRewrites + VoiceLexicon.fractionRewrites {
            numbered = numbered.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let parts = numbered.replacingOccurrences(of: lexicon.separators, with: " , ", options: .regularExpression)
            .components(separatedBy: ",")
        return parts.compactMap { phrase($0.trimmingCharacters(in: .whitespaces), lexicon, translated: translated) }
    }

    private static func phrase(_ text: String, _ lexicon: VoiceLexicon, translated: Bool) -> VoiceFoodPhrase? {
        var words = text.split(separator: " ").map(String.init)
        while let last = words.last, lexicon.trailingNoise.contains(last) { words.removeLast() }
        guard !words.isEmpty else { return nil }

        var quantity: Double?
        var unit: VoiceUnit?
        // "about 200 g": the vague word before an amount goes; "a" and "an" are looked at below.
        while words.count > 1, lexicon.leadingNoise.contains(words[0]), !lexicon.oneArticles.contains(words[0]) { words.removeFirst() }
        // Amount first: "2 eggs", "200 g of chicken", "a cup of rice".
        if let value = Double(words[0]) {
            quantity = value
            words.removeFirst()
        } else if lexicon.oneArticles.contains(words[0]), words.count > 1, lexicon.units[words[1]] != nil {
            quantity = 1
            words.removeFirst()
        }
        if let first = words.first, let found = lexicon.units[first], words.count > 1 {
            unit = found
            if quantity == nil { quantity = 1 }
            words.removeFirst()
            if let next = words.first, lexicon.ofWords.contains(next) { words.removeFirst() }
        }
        // Amount last: "chicken breast 200 grams".
        if quantity == nil, words.count >= 3, let found = lexicon.units[words[words.count - 1]], let value = Double(words[words.count - 2]) {
            quantity = value
            unit = found
            words.removeLast(2)
        }
        while let first = words.first, lexicon.leadingNoise.contains(first) || lexicon.oneArticles.contains(first) { words.removeFirst() }
        var name = words.joined(separator: " ")
        guard !name.isEmpty, quantity ?? 1 > 0 else { return nil }
        if translated { name = lexicon.translate(name, with: lexicon.foods) }
        return VoiceFoodPhrase(name: name, quantity: quantity, unit: unit)
    }

    // MARK: Numbers

    /// "two eggs" → "2 eggs", "twenty five" → "25", "a hundred and fifty" → "150".
    static func numberWordsToDigits(_ text: String, _ lexicon: VoiceLexicon = .english) -> String {
        var output: [String] = []
        var total: Double?
        var lastWasTens = false
        func flush() {
            if let value = total {
                output.append(value == value.rounded() ? String(Int(value)) : String(value))
            }
            total = nil
            lastWasTens = false
        }
        let words = text.split(separator: " ").map(String.init)
        var index = 0
        while index < words.count {
            let word = words[index]
            // Arabic writes "and" onto the next number: "خمسه وعشرين" is five-and-twenty.
            if let joiner = lexicon.attachedJoiner, word.hasPrefix(joiner), let value = total, value < 10,
               let tens = lexicon.numbers[String(word.dropFirst(joiner.count))], tens >= 20, tens < 100 {
                total = value + tens
                lastWasTens = false
            } else if let unit = lexicon.numbers[word] {
                if let value = total, lastWasTens, unit < 10 {
                    total = value + unit              // "twenty" + "five"
                } else if let value = total, value >= 100, value.truncatingRemainder(dividingBy: 100) == 0, unit < 100 {
                    total = value + unit              // "a hundred" + "fifty"
                } else {
                    flush()
                    total = unit
                }
                lastWasTens = unit >= 20 && unit < 100 && unit.truncatingRemainder(dividingBy: 10) == 0
            } else if lexicon.hundredWords.contains(word) {
                total = (total ?? 1) * 100
                lastWasTens = false
                // "a hundred and fifty": skip the "and" inside a number.
                if index + 2 < words.count, lexicon.numberJoiners.contains(words[index + 1]), lexicon.numbers[words[index + 2]] != nil { index += 1 }
            } else if lexicon.oneArticles.contains(word), index + 1 < words.count, lexicon.hundredWords.contains(words[index + 1]) {
                flush()
                total = 1
            } else {
                flush()
                output.append(word)
            }
            index += 1
        }
        flush()
        return output.joined(separator: " ")
    }

    // MARK: Helpers

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Languages

/// The languages voice commands understand.
enum VoiceLanguage: String, CaseIterable, Identifiable {
    case english = "en", german = "de", arabic = "ar", lithuanian = "lt"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .arabic: return "العربية"
        case .lithuanian: return "Lietuvių"
        }
    }

    /// The speech model's language. English follows the phone's own English variant.
    var locale: Locale {
        switch self {
        case .english:
            let current = Locale.current
            return current.language.languageCode?.identifier == "en" ? current : Locale(identifier: "en-US")
        case .german: return Locale(identifier: "de-DE")
        case .arabic: return Locale(identifier: "ar-SA")
        case .lithuanian: return Locale(identifier: "lt-LT")
        }
    }

    var lexicon: VoiceLexicon {
        switch self {
        case .english: return .english
        case .german: return .german
        case .arabic: return .arabic
        case .lithuanian: return .lithuanian
        }
    }

    /// The phone's language when voice commands know it, else English.
    static var deviceDefault: VoiceLanguage {
        VoiceLanguage(rawValue: Locale.current.language.languageCode?.identifier ?? "") ?? .english
    }

    static let storageKey = "voiceLanguage_v1"

    /// The language chosen in Profile (the phone's language until one is chosen).
    static var current: VoiceLanguage {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(VoiceLanguage.init) ?? deviceDefault }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }
}

// MARK: - A language's words

/// Every word and sentence pattern the rule book needs for one language.
/// Patterns are regular expressions over the cleaned, lowercased text; the
/// part in the first capture group is what the command is about.
struct VoiceLexicon {
    /// Extra cleaning before the shared rules (Arabic letter forms, folding accents).
    var clean: (String) -> String = { $0 }
    var fillers: [String]

    var calorieWords: [String]
    var calorieCues: [String]

    var exercisePatterns: [String]
    var exerciseNoise: Set<String>
    /// Exercise names → the library's English names.
    var exercises: [VoiceTranslation] = []

    /// Words ending in `*` match as stems ("treniruot*").
    var workoutNouns: Set<String>
    var workoutPhrases: [String] = []
    var workoutVerbs: Set<String>
    var workoutCues: [String]
    var workoutKinds: [(kind: ExerciseKind, words: Set<String>)]
    /// Alternations without the group: "minutes|minute|mins|min".
    var minuteWords: String
    var hourWords: String
    var halfHourPhrases: [String]
    var oneHourPhrases: [String]

    var cartPatterns: [String]
    var checklistPatterns: [String]

    var openPatterns: [String]
    var screenNoise: Set<String>
    var screens: [(screen: VoiceScreen, names: Set<String>)]

    /// Regex before a meal's name ("for my "), and after it (" today").
    var mealPrefix: String
    var mealSuffix: String
    var meals: [(slot: MealSlot, names: [String])]
    /// Longest first, so "i just had" wins over "i".
    var foodVerbs: [String]
    /// Regex for the words between foods (" and ", " plus ").
    var separators: String
    /// Language-specific amounts ("half a" → "0.5"), applied before splitting.
    var amountRewrites: [(String, String)]
    var units: [String: VoiceUnit]
    var ofWords: Set<String>
    /// "a", "an": one of something before a unit, or before "hundred".
    var oneArticles: Set<String>
    var leadingNoise: Set<String>
    var trailingNoise: Set<String>

    var numbers: [String: Double]
    var hundredWords: Set<String>
    var numberJoiners: Set<String>
    /// A joiner written onto the next word (Arabic "و").
    var attachedJoiner: String?

    /// Food words → the catalogue's English names. Empty for English.
    var foods: [VoiceTranslation] = []
    /// Prefixes dropped from a word before it is looked up (the Arabic article).
    var wordPrefixes: [String] = []
    /// Also accept a word a letter or two away from a known one (see `VoiceRuleBook.parse`).
    var tolerant = false

    static let fractionRewrites: [(String, String)] = [
        (#"(?<![\d/.])1/2(?![\d/])"#, "0.5"), (#"(?<![\d/.])1/4(?![\d/])"#, "0.25"),
        (#"(?<![\d/.])3/4(?![\d/])"#, "0.75"), (#"(?<![\d/.])1/3(?![\d/])"#, "0.33"),
    ]

    /// True when `word` is in `set`, either whole or by a stem ending in `*`.
    func matches(_ word: String, _ set: Set<String>) -> Bool {
        if set.contains(word) { return true }
        return set.contains { $0.hasSuffix("*") && word.hasPrefix($0.dropLast()) }
    }

    /// Replaces words this language has a translation for; the rest stay as said
    /// (a product saved under its local name can still be found by it).
    func translate(_ name: String, with table: [VoiceTranslation]) -> String {
        guard !table.isEmpty else { return name }
        let words = name.split(separator: " ").map { strip(String($0)) }
        var result: [String] = []
        var index = 0
        while index < words.count {
            var matched = false
            // Longest run of words first: "griechischer joghurt" before "joghurt".
            for length in stride(from: min(3, words.count - index), through: 1, by: -1) {
                let run = words[index..<(index + length)].joined(separator: " ")
                if let english = table.first(where: { $0.matches(run) })?.english {
                    result.append(english)
                    index += length
                    matched = true
                    break
                }
            }
            if !matched {
                result.append(tolerant ? nearest(words[index], in: table) ?? words[index] : words[index])
                index += 1
            }
        }
        return result.joined(separator: " ")
    }

    /// The translation whose one-word form is closest to a misheard word, if any is close enough.
    private func nearest(_ word: String, in table: [VoiceTranslation]) -> String? {
        var best: (english: String, distance: Int)?
        for line in table {
            for form in line.forms where !form.contains(" ") {
                if let distance = VoiceSpelling.near(word, form), distance < best?.distance ?? .max { best = (line.english, distance) }
            }
        }
        return best?.english
    }

    private func strip(_ word: String) -> String {
        for prefix in wordPrefixes where word.hasPrefix(prefix) && word.count >= prefix.count + 3 {
            return String(word.dropFirst(prefix.count))
        }
        return word
    }
}

/// One dictionary line: the forms a word takes, and what the catalogue calls it.
/// A form ending in `*` is a stem ("kiausin*" matches every case ending).
struct VoiceTranslation {
    let forms: [String]
    let english: String

    init(_ english: String, _ forms: String...) {
        self.english = english
        self.forms = forms
    }

    func matches(_ text: String) -> Bool {
        let words = text.split(separator: " ").count
        return forms.contains { form in
            guard form.contains("*") else { return text == form }
            // Stems match word by word, over a run of the same number of words:
            // "vistienos krutinel*", "cepelin* su varsk*".
            let stems = form.split(separator: " ")
            let said = text.split(separator: " ")
            guard stems.count == words else { return false }
            return zip(stems, said).allSatisfy { stem, word in
                stem.hasSuffix("*") ? word.hasPrefix(stem.dropLast()) : word == stem
            }
        }
    }
}

// MARK: - Misheard words

/// How far a heard word may be from a known one and still count as it.
enum VoiceSpelling {

    /// The number of wrong letters between `word` and `form` when that is small
    /// enough to be a mishearing: one for a form of 5 or 6 letters, two for 7 or
    /// more, never for shorter ones. A form ending in `*` is a stem and is
    /// compared with the start of the word. nil when they are the same or too far apart.
    static func near(_ word: String, _ form: String) -> Int? {
        let isStem = form.hasSuffix("*")
        let known = Array(isStem ? String(form.dropLast()) : form)
        let said = Array(word)
        let allowed = known.count >= 7 ? 2 : known.count >= 5 ? 1 : 0
        guard allowed > 0, !known.contains(" "), said.count >= known.count - 1 else { return nil }
        var best = Int.max
        if isStem {
            for length in (known.count - 1)...(known.count + 1) where length <= said.count {
                best = min(best, distance(Array(said.prefix(length)), known))
            }
        } else {
            best = distance(said, known)
        }
        return (1...allowed).contains(best) ? best : nil
    }

    /// Edit distance: letters changed, added or dropped.
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = current
            }
        }
        return row[b.count]
    }
}
