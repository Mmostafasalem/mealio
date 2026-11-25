import Foundation

// MARK: - Features the person chose
//
// During onboarding the person picks what they want Nourlo for. The choice
// decides which tabs, quick actions, Home cards, quests and onboarding steps
// appear. Stored as a comma-separated string under
// `Constants.Storage.enabledFeatures`; a missing or unreadable value means
// every feature, so people who finished onboarding before this existed see no
// change. At least one feature is always on.

enum AppFeature: String, CaseIterable, Identifiable, Hashable {
    /// Calorie ring and macros, the food log, Log food, voice logging, logging quests, History.
    case tracking
    /// The Meals tab, the meal plan, Cook with what I have.
    case meals
    /// The Shop tab, the cart, weekly groceries and budget, My Stock.
    case groceries
    /// The Train tab, workout quests and workout entry points.
    case workouts

    var id: String { rawValue }

    static let all = Set(allCases)

    /// Short name, used in Profile and the "turned off" prompt.
    var name: String {
        switch self {
        case .tracking: return "Calorie and food tracking"
        case .meals: return "Meal planning"
        case .groceries: return "Groceries and budget"
        case .workouts: return "Workouts"
        }
    }

    /// The onboarding question's answer.
    var choiceTitle: String {
        switch self {
        case .tracking: return "Track calories and food"
        case .meals: return "Plan my meals"
        case .groceries: return "Plan groceries and budget"
        case .workouts: return "Work out"
        }
    }

    var detail: String {
        switch self {
        case .tracking: return "Log meals, calories and macros"
        case .meals: return "Weekly meals and recipes"
        case .groceries: return "List, cart, budget and stock"
        case .workouts: return "Build workouts and follow along"
        }
    }

    var symbol: String {
        switch self {
        case .tracking: return "flame.fill"
        case .meals: return "fork.knife"
        case .groceries: return "cart.fill"
        case .workouts: return "figure.run"
        }
    }

    // MARK: Storage

    /// Every feature for nil, empty or unreadable text; otherwise the features named.
    static func decode(_ text: String?) -> Set<AppFeature> {
        guard let text else { return all }
        let features = Set(text.split(separator: ",").compactMap {
            AppFeature(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
        return features.isEmpty ? all : features
    }

    /// The features in a fixed order, so the stored text is stable.
    static func encode(_ features: Set<AppFeature>) -> String {
        allCases.filter(features.contains).map(\.rawValue).joined(separator: ",")
    }

    static func load(from defaults: UserDefaults = .standard) -> Set<AppFeature> {
        decode(defaults.string(forKey: Constants.Storage.enabledFeatures))
    }

    /// Saves the features; an empty set is not saved (one feature is always on).
    static func save(_ features: Set<AppFeature>, to defaults: UserDefaults = .standard) {
        guard !features.isEmpty else { return }
        defaults.set(encode(features), forKey: Constants.Storage.enabledFeatures)
    }
}

// MARK: - Tabs

/// The tab bar's slots. Tags stay fixed whatever is shown, so the bowl guide
/// and links keep using the same numbers.
enum AppTab: Int, CaseIterable, Identifiable {
    case home = 0, meals = 1, shop = 2, train = 3, quickActions = 4

    var id: Int { rawValue }

    /// Kept for VoiceOver and the UI tests (`app.tabBars.buttons["Home"]`).
    var name: String {
        switch self {
        case .home: return "Home"
        case .meals: return "Meals"
        case .shop: return "Shop"
        case .train: return "Train"
        case .quickActions: return "Quick actions"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .meals: return "fork.knife"
        case .shop: return "storefront.fill"
        case .train: return "figure.run"
        case .quickActions: return "bolt.fill"
        }
    }

    /// The feature a tab belongs to; Home and "+" are always there.
    var feature: AppFeature? {
        switch self {
        case .meals: return .meals
        case .shop: return .groceries
        case .train: return .workouts
        case .home, .quickActions: return nil
        }
    }
}

// MARK: - What each choice shows

/// Pure rules for which parts of the app appear for a set of features.
enum FeatureLayout {

    /// Tabs left to right: Home, then the chosen feature tabs, then quick actions at the end.
    static func tabs(for features: Set<AppFeature>) -> [AppTab] {
        var tabs: [AppTab] = [.home]
        tabs += [AppTab.meals, .shop, .train].filter { $0.feature.map(features.contains) ?? true }
        // Quick actions sits in the middle of the bar, in the same dock as the screens.
        tabs.insert(.quickActions, at: (tabs.count + 1) / 2)
        return tabs
    }

    /// Row ids in the quick actions sheet (matching `quickActions.<id>` identifiers).
    /// Rows that also depend on AI or the camera are filtered again by the sheet.
    static func quickActionIDs(for features: Set<AppFeature>) -> [String] {
        var ids: [String] = []
        if showsVoice(features) { ids.append("voice") }
        if features.contains(.tracking) {
            ids.append("mealPhoto")
            ids.append(MealioQuickAction.logFood.rawValue)
        }
        if features.contains(.groceries) {
            ids.append(MealioQuickAction.cart.rawValue)
            ids.append(MealioQuickAction.groceries.rawValue)
        }
        ids.append("chat")
        ids.append(MealioQuickAction.profile.rawValue)
        return ids
    }

    /// Voice commands log food, fill the cart and start workouts; meal planning alone has none.
    static func showsVoice(_ features: Set<AppFeature>) -> Bool {
        !features.isDisjoint(with: [.tracking, .groceries, .workouts])
    }

    /// My Stock feeds the meal plan as well as the groceries, so it stays with either.
    static func showsStock(_ features: Set<AppFeature>) -> Bool {
        !features.isDisjoint(with: [.meals, .groceries])
    }

    /// The feature a quick action needs, if any.
    static func feature(for action: MealioQuickAction) -> AppFeature? {
        switch action {
        case .meals: return .meals
        case .shop, .cart, .groceries: return .groceries
        case .train: return .workouts
        case .logFood: return .tracking
        case .home, .profile: return nil
        }
    }

    /// The feature an outside link opens, if any.
    static func feature(for link: NourloLink) -> AppFeature? {
        switch link {
        case .home: return nil
        case .logFood, .scan: return .tracking
        case .meals: return .meals
        case .groceries: return .groceries
        case .train: return .workouts
        }
    }

    /// The feature a quest belongs to. Cooking from stock needs the food log and the stock.
    static func allows(_ quest: QuestID, _ features: Set<AppFeature>) -> Bool {
        switch quest {
        case .logAny, .breakfast, .threeMeals, .protein, .onTarget, .newFood, .vegetables, .fruit:
            return features.contains(.tracking)
        case .workout, .anyWorkout:
            return features.contains(.workouts)
        case .budget:
            return features.contains(.groceries)
        case .fromStock:
            return features.contains(.tracking) && showsStock(features)
        }
    }

    // MARK: Onboarding

    /// Body stats set calorie targets and workouts' calorie estimates.
    static func asksBodyStats(_ features: Set<AppFeature>) -> Bool {
        !features.isDisjoint(with: [.tracking, .meals, .workouts])
    }

    /// The goal sets calories and Train's focus.
    static func asksGoal(_ features: Set<AppFeature>) -> Bool { asksBodyStats(features) }

    /// The pace only changes the calorie deficit.
    static func asksPace(_ features: Set<AppFeature>) -> Bool {
        !features.isDisjoint(with: [.tracking, .meals])
    }

    /// Diet shapes meals and groceries, and keto changes the macro targets.
    static func asksDiet(_ features: Set<AppFeature>) -> Bool {
        !features.isDisjoint(with: [.tracking, .meals, .groceries])
    }

    /// The favourite foods start the meal plan and the weekly groceries.
    static func asksFavorites(_ features: Set<AppFeature>) -> Bool { showsStock(features) }

    /// "Your week and meals": the week start (groceries, budget, plan) and the
    /// day's meal split (plan and calorie targets per meal).
    static func asksWeek(_ features: Set<AppFeature>) -> Bool {
        !features.isDisjoint(with: [.tracking, .meals, .groceries])
    }

    /// Workout reminders need workouts; the meal and log-your-day ones need food tracking.
    static func offersReminder(_ kind: Reminder.Kind, _ features: Set<AppFeature>) -> Bool {
        kind == .workout ? features.contains(.workouts) : features.contains(.tracking)
    }

    /// Onboarding screens in order for these features. `pace` is included only
    /// while the goal is to lose weight. Reminders and Health always end it.
    static func onboardingSteps(for features: Set<AppFeature>, losingWeight: Bool, offersAI: Bool = false) -> [OnboardingStep] {
        var steps: [OnboardingStep] = [.name, .features]
        if asksBodyStats(features) { steps += [.height, .weight, .activity] }
        if asksGoal(features) { steps.append(.goal) }
        if asksGoal(features), asksPace(features), losingWeight { steps.append(.pace) }
        if asksDiet(features) { steps.append(.diet) }
        if asksFavorites(features) { steps.append(.favorites) }
        if asksWeek(features) { steps.append(.week) }
        // Only when the backend offers online AI (guest or Apple accounts).
        if offersAI { steps.append(.account) }
        steps.append(.alerts)
        return steps
    }
}
