import AppIntents
import Foundation

// MARK: - Shared pieces for Siri, Shortcuts and Spotlight
//
// Intents in this folder are compiled into the app target only. Ones that
// read or change the user's data (calories left, today's meals, quick log)
// run in the app's process without opening it; the rest open a screen
// through `AppRouter` / `NourloLinkInbox`.

/// A meal slot as Siri and Shortcuts show it.
nonisolated enum MealSlotOption: String, AppEnum, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snacks

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Meal" }
    static var caseDisplayRepresentations: [MealSlotOption: DisplayRepresentation] {
        [
            .breakfast: DisplayRepresentation(title: "Breakfast", image: .init(systemName: "sunrise.fill")),
            .lunch: DisplayRepresentation(title: "Lunch", image: .init(systemName: "sun.max.fill")),
            .dinner: DisplayRepresentation(title: "Dinner", image: .init(systemName: "moon.fill")),
            .snacks: DisplayRepresentation(title: "Snacks", image: .init(systemName: "sparkles"), synonyms: ["Snack"]),
        ]
    }

    @MainActor var mealSlot: MealSlot {
        switch self {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snacks: return .snack
        }
    }

    @MainActor init(_ slot: MealSlot) {
        switch slot {
        case .breakfast: self = .breakfast
        case .lunch: self = .lunch
        case .dinner: self = .dinner
        case .snack: self = .snacks
        }
    }
}

/// A workout kind as Siri and Shortcuts show it.
nonisolated enum WorkoutKindOption: String, AppEnum, CaseIterable, Sendable {
    case gym, cardio, home, mobility

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Workout kind" }
    static var caseDisplayRepresentations: [WorkoutKindOption: DisplayRepresentation] {
        [
            .gym: DisplayRepresentation(title: "Gym", image: .init(systemName: "dumbbell.fill"), synonyms: ["Weights", "Strength"]),
            .cardio: DisplayRepresentation(title: "Cardio", image: .init(systemName: "figure.run"), synonyms: ["Running", "Run"]),
            .home: DisplayRepresentation(title: "Home", image: .init(systemName: "house.fill"), synonyms: ["Bodyweight"]),
            .mobility: DisplayRepresentation(title: "Mobility", image: .init(systemName: "figure.flexibility"), synonyms: ["Stretching", "Stretch"]),
        ]
    }

    @MainActor var exerciseKind: ExerciseKind {
        switch self {
        case .gym: return .gym
        case .cardio: return .cardio
        case .home: return .home
        case .mobility: return .mobility
        }
    }
}

/// What Siri says when an intent can't do its job.
nonisolated enum NourloIntentError: Error, CustomLocalizedStringResourceConvertible {
    case foodNotFound
    case invalidAmount(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .foodNotFound:
            return "That food isn't in Nourlo's offline list or your saved foods. Open Nourlo to search products."
        case .invalidAmount(let range):
            return "Choose an amount between \(range)."
        }
    }
}

// MARK: - Forgiving name search

/// Matching for spoken or typed names: ignores case, accents, punctuation
/// and simple plurals ("Lunges" finds "Walking lunge", "bananas" finds "Banana").
nonisolated enum IntentSearch {
    /// Lowercased, accent-free words with simple plurals made singular.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(singular)
    }

    static func singular(_ word: String) -> String {
        guard word.count >= 3, word.allSatisfy({ $0.isLetter }) else { return word }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("es") {
            let stem = word.dropLast(2)
            if ["s", "x", "z", "ch", "sh", "o"].contains(where: { stem.hasSuffix($0) }) { return String(stem) }
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") { return String(word.dropLast()) }
        return word
    }

    /// How well `name` matches `query`: 0 = exact, 1 = starts with it,
    /// 2 = every query word starts a word in the name, `nil` = no match.
    static func rank(_ name: String, query: String) -> Int? {
        let q = words(query), n = words(name)
        guard !q.isEmpty else { return nil }
        if q == n { return 0 }
        if n.starts(with: q) { return 1 }
        if q.allSatisfy({ word in n.contains { $0.hasPrefix(word) } }) { return 2 }
        return nil
    }

    /// The items whose name matches, best first, then shortest name.
    static func filter<T>(_ items: [T], query: String, name: (T) -> String, limit: Int = 25) -> [T] {
        items.compactMap { item in rank(name(item), query: query).map { (item, $0) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return name(a.0).count < name(b.0).count
            }
            .prefix(limit).map(\.0)
    }
}

// MARK: - Launch

/// Keeps Siri's phrase vocabulary (recent foods) current. Call `start()` once at launch.
@MainActor
enum NourloIntents {
    private static var observer: NSObjectProtocol?
    private static var lastRecents: [String]?

    static func start() {
        refreshShortcutParameters()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .foodLogDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { refreshShortcutParameters() }
        }
    }

    /// Recent foods appear in "Log <food> in Nourlo"; only refresh when they change.
    static func refreshShortcutParameters() {
        let recents = FoodLogStore.shared.recentFoodIDs
        guard recents != lastRecents else { return }
        lastRecents = recents
        NourloShortcuts.updateAppShortcutParameters()
    }
}
