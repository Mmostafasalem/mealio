# SmartMarket Agent — Fix All Agent Data Flow Bugs

Paste this into Claude Code. Fix every issue listed. Do not add new features or restructure files beyond what is specified.

---

## Bug 1 — CRITICAL: Onboarding never saves Int favorite food IDs

**File:** `Features/Onboarding/OnboardingViewModel.swift`

**Problem:** `finish()` saves `favoriteFoodIDs` (a `Set<String>` of Food catalog IDs like `"chicken"`) to `Constants.Storage.favoriteFoodIDs`, but `AgentLoop` and `AppState` read from `Constants.Storage.favoriteFoodIDsInt` which stores `[Int]` (backend deal IDs). After onboarding, `appState.favoriteFoodIDs` is always empty — the agent never matches any deals for notifications.

`Food.id` is a string slug (`"chicken"`, `"oats"`) from the local catalog. The backend `Deal.id` is an `Int`. These are two different ID spaces. The Food catalog has a `backendId: Int?` field — if it exists use it; otherwise the user's favorites will not match backend deals.

**Fix:** In `finish()`, after saving `favoriteFoodIDs` (String), also compute and save the Int IDs:

Find the `finish()` method. After this line:
```swift
UserDefaults.standard.set(Array(favoriteFoodIDs), forKey: Constants.Storage.favoriteFoodIDs)
```

Add:
```swift
// Also persist as Int IDs for AgentLoop deal matching
let intIDs = favoriteFoodIDs.compactMap { id in
    Food.catalog.first(where: { $0.id == id })?.backendId
}
UserDefaults.standard.set(intIDs, forKey: Constants.Storage.favoriteFoodIDsInt)
```

**If `Food` does not have a `backendId` property:** Add it to `Models/Food.swift`. Each `Food` struct needs `let backendId: Int?`. Set reasonable values for common foods matching the backend mock (e.g. chicken=1, milk=2, eggs=3, etc.). Look at `MarketDeal.mocked` to see what productIds the backend returns and align them. If the food catalog IDs don't map to backend IDs at all, set all to `nil` for now — but at minimum the property must exist so the code compiles.

---

## Bug 2 — CRITICAL: AgentLoop never generates meal plan on first launch

**File:** `App/AgentLoop.swift`

**Problem:** In `tick()`, meal plan regeneration only triggers when `currentCount > appState.lastGroceryCount`. On first launch both are `0`, so `0 > 0` is false and the meal plan is never generated. The Home tab shows no meal plan until the user manually adds something to the grocery list.

**Fix:** Change the condition to also fire when no plan exists yet:

Find:
```swift
// 4. Regenerate meal plan if grocery list grew
let currentCount = appState.groceryList.count
if currentCount > appState.lastGroceryCount && !appState.groceryList.isEmpty {
    appState.lastGroceryCount = currentCount
    await regenerateMealPlan(appState: appState)
}
```

Replace with:
```swift
// 4. Regenerate meal plan if no plan exists yet, or if grocery list grew
let currentCount = appState.groceryList.count
let needsPlan = appState.weeklyMealPlan == nil
let listGrew  = currentCount > appState.lastGroceryCount

if needsPlan || listGrew {
    appState.lastGroceryCount = currentCount
    await regenerateMealPlan(appState: appState)
}
```

---

## Bug 3 — CRITICAL: MealPlanViewModel always sends empty favorites and grocery list to AI

**File:** `Features/MealPlan/MealPlanViewModel.swift`

**Problem:** `fetchTodaysPlan()` builds the `MealPlanRequest` with `favoriteFoods: []` and `groceryList: []` hardcoded. The AI never receives the user's actual favorite foods or what they've bought, so the meal plan is completely generic and ignores the user's preferences.

**Fix:** Update `fetchTodaysPlan()` to read real data.

Find:
```swift
let request = MealPlanRequest(
    user: MealPlanUser(
        name:          profile.name,
        age:           profile.age,
        gender:        profile.gender == .male ? "male" : "female",
        weight:        profile.weight,
        height:        profile.height,
        goal:          profile.weightGoal.rawValue,
        activityLevel: profile.activityLevel.rawValue,
        dietaryOptions: [],
        allergies:     [],
        favoriteFoods: []
    ),
    bmrData: AppState.shared.bmrData ?? BMRResponse(
        bmr:              Int(profile.bmr),
        tdee:             Int(profile.tdee),
        loseCalories:     max(Int(profile.tdee) - 350, 1200),
        maintainCalories: Int(profile.tdee),
        gainCalories:     Int(profile.tdee) + 350,
        macros: BMRResponse.MacroTargets(protein: 150, carbs: 200, fat: 60)
    ),
    groceryList: [],
    goal: profile.weightGoal.rawValue,
    lang: AppState.shared.lang
)
```

Replace with:
```swift
// Read actual user preferences
let favIntIDs = Array(AppState.shared.favoriteFoodIDs)   // Set<Int>
let dietaryPrefs = Set<DietaryPreference>.load()
let dietOptions = dietaryPrefs.map { $0.rawValue }
let allergies = dietaryPrefs.filter { $0.isAllergy }.map { $0.rawValue }

let request = MealPlanRequest(
    user: MealPlanUser(
        name:           profile.name,
        age:            profile.age,
        gender:         profile.gender == .male ? "male" : "female",
        weight:         profile.weight,
        height:         profile.height,
        goal:           profile.weightGoal.rawValue,
        activityLevel:  profile.activityLevel.rawValue,
        dietaryOptions: dietOptions,
        allergies:      allergies,
        favoriteFoods:  favIntIDs
    ),
    bmrData: AppState.shared.bmrData ?? BMRResponse(
        bmr:              Int(profile.bmr),
        tdee:             Int(profile.tdee),
        loseCalories:     max(Int(profile.tdee) - 350, 1200),
        maintainCalories: Int(profile.tdee),
        gainCalories:     Int(profile.tdee) + 350,
        macros: BMRResponse.MacroTargets(protein: 150, carbs: 200, fat: 60)
    ),
    groceryList: AppState.shared.groceryList,
    goal: profile.weightGoal.rawValue,
    lang: AppState.shared.lang
)
```

**Also check `DietaryPreference`:** It needs a computed var `isAllergy: Bool`. If it does not exist, add it to `Models/DietaryPreference.swift`:

```swift
var isAllergy: Bool {
    switch self {
    case .glutenFree, .dairyFree, .nutFree: return true
    default: return false
    }
}
```

Only add this if `isAllergy` does not already exist.

---

## Bug 4 — StoreDetailSheet decodes wrong type for meal plan matches

**File:** `Features/Map/StoreDetailSheet.swift`

**Problem:** `mealPlanMatches()` tries to decode `MealPlan.self` from `"currentMealPlan"` in UserDefaults. But `AppState.saveMealPlan()` encodes a `WeeklyMealPlan` under that key. The decode always fails, so the "Matches your current meal plan" section is always empty.

**Fix:** Replace the body of `mealPlanMatches()`:

Find:
```swift
private func mealPlanMatches() -> [(mealType: String, entry: MealEntry)] {
    let discountedNames = Set(
        vm.storeDeals.map { $0.productName.lowercased() }
    )
    let data = UserDefaults.standard.data(forKey: "currentMealPlan") ?? Data()
    guard
        let plan = try? JSONDecoder().decode(MealPlan.self, from: data)
    else { return [] }

    var results: [(String, MealEntry)] = []
    let sections: [(String, [MealEntry])] = [
        ("sunrise", plan.breakfast),
        ("sun.max", plan.lunch),
        ("moon", plan.dinner),
        ("sparkles", plan.snacks),
    ]
    for (symbol, entries) in sections {
        for entry in entries where discountedNames.contains(where: { entry.foodName.lowercased().contains($0) }) {
            results.append((symbol, entry))
        }
    }
    return results
}
```

Replace with:
```swift
private func mealPlanMatches() -> [(mealType: String, entry: MealEntry)] {
    let discountedNames = Set(vm.storeDeals.map { $0.productName.lowercased() })

    // AppState stores WeeklyMealPlan — bridge to today's MealPlan via MealPlan.from()
    let plan: MealPlan?
    if let weekly = AppState.shared.weeklyMealPlan {
        plan = MealPlan.from(weekly: weekly)
    } else if let data = UserDefaults.standard.data(forKey: Constants.Storage.currentMealPlan),
              let weekly = try? JSONDecoder().decode(WeeklyMealPlan.self, from: data) {
        plan = MealPlan.from(weekly: weekly)
    } else {
        plan = nil
    }
    guard let plan else { return [] }

    var results: [(String, MealEntry)] = []
    let sections: [(String, [MealEntry])] = [
        ("sunrise", plan.breakfast),
        ("sun.max", plan.lunch),
        ("moon", plan.dinner),
        ("sparkles", plan.snacks),
    ]
    for (symbol, entries) in sections {
        for entry in entries where discountedNames.contains(where: { entry.foodName.lowercased().contains($0) }) {
            results.append((symbol, entry))
        }
    }
    return results
}
```

---

## Bug 5 — HomeViewModel loads meal plan at cold start before AgentLoop has run

**File:** `Features/Home/HomeViewModel.swift`

**Problem:** `loadPlan()` reads `AppState.shared.weeklyMealPlan`. On the very first launch this is `nil` (AgentLoop hasn't fired yet), so `mealPlan` stays `nil` and the Home tab shows an empty meal plan card. After `AgentLoop` generates a plan (30+ seconds later), HomeViewModel is not notified to refresh.

**Fix:** After `load()` sets `mealPlan = loadedPlan`, observe `AppState.shared.weeklyMealPlan` for changes. Add a method to re-read the plan and call it from a `.onChange` or via NotificationCenter.

In the `init()` (or wherever NotificationCenter observers are added), add:

```swift
NotificationCenter.default.addObserver(
    forName: .mealPlanDidUpdate,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in
        if let weekly = AppState.shared.weeklyMealPlan {
            self?.mealPlan = MealPlan.from(weekly: weekly)
        }
    }
}
```

Then in `AppState.saveMealPlan(_:)`, after saving, post the notification:

**File:** `App/AppState.swift`

Find:
```swift
func saveMealPlan(_ plan: WeeklyMealPlan) {
    weeklyMealPlan = plan
    if let data = try? JSONEncoder().encode(plan) {
        UserDefaults.standard.set(data, forKey: Constants.Storage.currentMealPlan)
    }
}
```

Replace with:
```swift
func saveMealPlan(_ plan: WeeklyMealPlan) {
    weeklyMealPlan = plan
    if let data = try? JSONEncoder().encode(plan) {
        UserDefaults.standard.set(data, forKey: Constants.Storage.currentMealPlan)
    }
    NotificationCenter.default.post(name: .mealPlanDidUpdate, object: nil)
}
```

Add the notification name extension if it does not exist. Check `Features/Home/HomeViewModel.swift` for where `.groceryListDidChange` is declared and add alongside it:

```swift
extension Notification.Name {
    static let mealPlanDidUpdate = Notification.Name("mealPlanDidUpdate")
}
```

Only add if it does not already exist.

---

## Bug 6 — AgentLoop sends `[Int]` favorites to `MealPlanUser.favoriteFoods` which expects `[Int]` ✓ but also passes them as `Array(appState.favoriteFoodIDs)` — verify type safety

**File:** `App/AgentLoop.swift`

`appState.favoriteFoodIDs` is `Set<Int>` and `MealPlanUser.favoriteFoods` is `[Int]` — this is correct. No change needed. Just confirm it compiles after Bug 1 is fixed.

---

## Bug 7 — `GroceryListViewModel` notification observer uses `[weak self]` on `@MainActor` class

**File:** `Features/GroceryList/GroceryListViewModel.swift`

**Problem:** The `NotificationCenter.addObserver` closure captures `[weak self]` and calls `self?.loadItems()` on `queue: .main`. Because `GroceryListViewModel` is `@MainActor`, this cross-actor call from a closure can produce a warning or crash in strict concurrency checking.

**Fix:** Replace the observer with a safer async/await version:

Find:
```swift
NotificationCenter.default.addObserver(
    forName: .groceryListDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.loadItems()
}
```

Replace with:
```swift
Task { @MainActor [weak self] in
    for await _ in NotificationCenter.default.notifications(named: .groceryListDidChange) {
        self?.loadItems()
    }
}
```

---

## Bug 8 — `MealPlanViewModel.loadRecommendations()` passes empty `groceryList` to ShoppingAdvice

**File:** `Features/MealPlan/MealPlanViewModel.swift`

**Problem:** `loadRecommendations()` calls `getShoppingAdvice` with `groceryList: []`. The AI has no context of what the user already has, producing irrelevant recommendations.

Find:
```swift
let adviceRequest = ShoppingAdviceRequest(
    groceryList: [],
```

Replace with:
```swift
let adviceRequest = ShoppingAdviceRequest(
    groceryList: AppState.shared.groceryList,
```

---

## After all fixes

1. Run **Cmd+B** — zero errors required.
2. Run the app in Simulator.
3. Complete onboarding with at least 5 favorite foods selected.
4. On the Home tab: the meal plan card should populate within ~30 seconds (first AgentLoop tick).
5. Add a deal to the Groceries tab — the meal plan should regenerate.
6. Open the Map tab, tap a store — the "Matches your current meal plan" section should show today's meals that overlap with that store's deals.
7. Verify deal notification banners appear on Home when a favorited item is on discount.
