# SmartMarket Agent — Full Error Fix Prompt

Paste this into Claude Code. Fix every issue listed below exactly as described. Do not add new features or restructure files beyond what is specified.

---

## Error 1 — CRITICAL: `OnboardingViewModel.swift` is declared twice

**File:** `Features/Onboarding/OnboardingViewModel.swift`

**Problem:** The file contains two complete `@Observable final class OnboardingViewModel` blocks. Swift refuses to compile: `invalid redeclaration of 'OnboardingViewModel'`.

**Fix:** Replace the entire file content with a single merged class that keeps the best of both versions. Use exactly this content:

```swift
import SwiftUI
import Observation

/// Single shared view model for the entire onboarding flow.
@Observable
final class OnboardingViewModel {

    // MARK: - Navigation
    var path: [OnboardingStep] = []

    // MARK: - Step 1: Body stats
    var firstName: String        = ""
    var lastName: String         = ""
    var weight: Double           = 70.0
    var height: Double           = 170.0
    var age: Int                 = 25
    var gender: Gender           = .male
    var activityLevel: ActivityLevel = .moderatelyActive

    // MARK: - Step 2: Goal
    var weightGoal: WeightGoal = .maintain
    var lossPace: LossPace     = .medium

    // MARK: - Step 3: Dietary preferences
    var selectedPreferences: Set<DietaryPreference> = []
    var otherAllergies: String = ""

    // MARK: - Step 4: Favorite foods
    var favoriteFoodIDs: Set<String> = []
    var selectedCategory: FoodCategory = .all
    var foodSearchQuery: String = "" {
        didSet { scheduleFilter() }
    }
    private(set) var filteredFoods: [Food] = Food.catalog
    @ObservationIgnored private var filterTask: Task<Void, Never>?

    // MARK: - Backend BMR (fetched after user fills in stats)
    var bmrResponse: BMRResponse?
    var isCalculatingBMR = false
    var bmrError: String?

    // MARK: - Live computed values (fall back to local calc if backend not called yet)
    var liveBMR: Int {
        bmrResponse?.bmr ?? Int(BMRCalculator.bmr(
            weight: weight, height: height, age: age, gender: gender
        ).rounded())
    }

    var liveTDEE: Int {
        bmrResponse?.tdee ?? Int(BMRCalculator.tdee(
            bmr: Double(liveBMR), activityLevel: activityLevel
        ).rounded())
    }

    var liveDailyGoal: Int {
        switch weightGoal {
        case .lose:     return bmrResponse?.loseCalories     ?? BMRCalculator.dailyGoal(tdee: Double(liveTDEE), goal: .lose,     pace: lossPace, gender: gender)
        case .maintain: return bmrResponse?.maintainCalories ?? liveTDEE
        case .gain:     return bmrResponse?.gainCalories     ?? BMRCalculator.dailyGoal(tdee: Double(liveTDEE), goal: .gain,     pace: lossPace, gender: gender)
        }
    }

    var isBelowSafeFloor: Bool {
        let floor: Int
        switch gender {
        case .male:   floor = Constants.Calories.minimumMale
        case .female: floor = Constants.Calories.minimumFemale
        case .other:  floor = Constants.Calories.minimumOther
        }
        return liveDailyGoal <= floor
    }

    // MARK: - Filtered food list
    func applyFilter(category: FoodCategory? = nil) {
        let cat = category ?? selectedCategory
        if let category { selectedCategory = category }
        scheduleFilter(category: cat)
    }

    private func scheduleFilter(category: FoodCategory? = nil) {
        filterTask?.cancel()
        filterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let cat  = category ?? selectedCategory
            let q    = foodSearchQuery.lowercased()
            let base = cat == .all ? Food.catalog : Food.catalog.filter { $0.category == cat }
            filteredFoods = q.isEmpty ? base : base.filter {
                $0.name.lowercased().contains(q) || $0.nameEn.lowercased().contains(q)
            }
        }
    }

    var favoritesCount: Int { favoriteFoodIDs.count }
    var canFinish: Bool { favoritesCount >= Constants.Onboarding.minimumFavorites }

    func toggleFavorite(_ food: Food) {
        if favoriteFoodIDs.contains(food.id) { favoriteFoodIDs.remove(food.id) }
        else { favoriteFoodIDs.insert(food.id) }
    }

    func togglePreference(_ pref: DietaryPreference) {
        if selectedPreferences.contains(pref) { selectedPreferences.remove(pref) }
        else { selectedPreferences.insert(pref) }
    }

    func advance(to step: OnboardingStep) { path.append(step) }

    // MARK: - Fetch BMR from backend
    @MainActor
    func fetchBMR() async {
        isCalculatingBMR = true
        bmrError = nil
        defer { isCalculatingBMR = false }

        let activityRaw: String = {
            switch activityLevel {
            case .sedentary:        return "sedentary"
            case .lightlyActive:    return "lightly_active"
            case .moderatelyActive: return "moderately_active"
            case .veryActive:       return "very_active"
            case .superActive:      return "very_active"
            }
        }()

        let request = BMRRequest(
            weight:        weight,
            height:        height,
            age:           age,
            gender:        gender == .male ? "male" : "female",
            activityLevel: activityRaw
        )

        do {
            let response = try await APIService.shared.calculateBMR(request)
            bmrResponse = response
            AppState.shared.saveBMR(response)
        } catch {
            bmrError = error.localizedDescription
        }
    }

    // MARK: - Finish onboarding
    @MainActor
    func finish() {
        var profile = UserProfile()
        let fullName = [firstName.trimmingCharacters(in: .whitespaces),
                        lastName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        profile.name          = fullName.isEmpty ? "SmartMarket User" : fullName
        profile.weight        = weight
        profile.height        = height
        profile.age           = age
        profile.gender        = gender
        profile.activityLevel = activityLevel
        profile.weightGoal    = weightGoal
        profile.lossPace      = lossPace
        BMRCalculator.populate(profile: &profile)
        profile.save()

        selectedPreferences.save()
        UserDefaults.standard.set(Array(favoriteFoodIDs), forKey: Constants.Storage.favoriteFoodIDs)

        AppState.shared.userProfile = profile
        AppState.shared.completeOnboarding()
        AppState.shared.agentLoop.start(appState: AppState.shared)
    }
}
```

---

## Error 2 — CRITICAL: `StoreMapViewModel` decodes wrong type from UserDefaults

**File:** `Features/Map/StoreMapViewModel.swift`

**Problem:** `load()` tries to decode `[MarketDeal]` from `Constants.Storage.groceryList`, but that key stores `[GroceryItem]`. The decode always fails silently. The map always shows only mocked stores regardless of what the API returns.

**Fix:** Replace the `load()` method body with one that calls the API directly and falls back to mocked data:

Find:
```swift
func load() async {
    isLoadingDeals = true
    defer { isLoadingDeals = false }

    // Try to decode cached deals from UserDefaults grocery list key.
    // Fall back to mocked data so the map is always populated.
    if let data = UserDefaults.standard.data(forKey: Constants.Storage.groceryList),
       let cached = try? JSONDecoder().decode([MarketDeal].self, from: data),
       !cached.isEmpty {
        deals = cached
    } else {
        deals = MarketDeal.mocked
    }

    // Centre camera on the user's current location if available,
    // otherwise default to Vilnius city centre.
    let vilnius = CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797)
    let centre = LocationService.shared.userLocation?.coordinate ?? vilnius
    cameraPosition = MapCameraPosition.region(MKCoordinateRegion(
        center: centre,
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
}
```

Replace with:
```swift
func load() async {
    isLoadingDeals = true
    defer { isLoadingDeals = false }

    do {
        deals = try await APIService.shared.fetchMarketDeals()
    } catch {
        deals = MarketDeal.mocked
        errorMessage = nil   // silent fallback — map still shows mocked stores
    }

    let vilnius = CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797)
    let centre = LocationService.shared.userLocation?.coordinate ?? vilnius
    cameraPosition = MapCameraPosition.region(MKCoordinateRegion(
        center: centre,
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
}
```

---

## Error 3 — Check `Color+Brand.swift` for missing helpers

**File:** `Utilities/Color+Brand.swift`

`StoreDetailSheet` uses `Color.labelSecondary` and `Color.labelTertiary`. If these are missing from `Color+Brand.swift`, add them inside the `extension Color` block:

```swift
static let labelSecondary  = Color(.secondaryLabel)
static let labelTertiary   = Color(.tertiaryLabel)
```

Only add these if they don't already exist in the file.

---

## Error 4 — `OnboardingProgressBar` total steps

**File:** `Components/OnboardingProgressBar.swift`

The onboarding now has 5 steps (BMR → Location → Goal → Diet → Notifications → Favorites = wait, that's 6 including the start? Let's count):
1. BMRInputView (step 1)
2. LocationPermissionView (step 2)
3. GoalSelectionView (step 3)
4. DietaryPreferencesView (step 4)
5. NotificationPermissionView (step 4 — same as dietary in the current file, needs to be 4)
6. FavoriteFoodsView (step 5)

Wait — check current step arguments:
- `BMRInputView`: `OnboardingProgressBar(currentStep: 1)` ✓
- `LocationPermissionView`: `OnboardingProgressBar(currentStep: 2)` ✓
- `GoalSelectionView`: `OnboardingProgressBar(currentStep: 2)` — **needs to be 3**
- `DietaryPreferencesView`: `OnboardingProgressBar(currentStep: 3)` — **needs to be 4**
- `NotificationPermissionView`: `OnboardingProgressBar(currentStep: 4)` ✓ (already correct)
- `FavoriteFoodsView`: `OnboardingProgressBar(currentStep: 4)` — **needs to be 5**

**Fix 4a — `GoalSelectionView.swift`:**
Change `OnboardingProgressBar(currentStep: 2)` → `OnboardingProgressBar(currentStep: 3)`

**Fix 4b — `DietaryPreferencesView.swift`:**
Change `OnboardingProgressBar(currentStep: 3)` → `OnboardingProgressBar(currentStep: 4)`

**Fix 4c — `FavoriteFoodsView.swift`:**
Change `OnboardingProgressBar(currentStep: 4)` → `OnboardingProgressBar(currentStep: 5)`

**Fix 4d — `OnboardingProgressBar.swift`:**
Find the total number of steps (likely `let totalSteps = 4` or hardcoded as `4`). Change it to `5`.

---

## Error 5 — `MealPlanRequest` potential conflict

**Files:** `Models/BackendModels.swift` and `Models/MealPlan.swift`

Check whether `MealPlanRequest` or `NutritionalGaps` are declared in both files. If `MealPlan.swift` contains a `struct MealPlanRequest` or `struct NutritionalGaps`, delete those from `MealPlan.swift` — keep only the ones in `BackendModels.swift`. Duplicate struct names cause `invalid redeclaration` errors.

---

## Error 6 — `BMRInputView` references `vm.fetchBMR()` and `vm.bmrResponse`

**File:** `Features/Onboarding/BMRInputView.swift`

After the `OnboardingViewModel` merge in Error 1, `fetchBMR()`, `isCalculatingBMR`, `bmrError`, and `bmrResponse` are all present. Verify BMRInputView's "Continue" button calls `vm.fetchBMR()` asynchronously:

```swift
Button {
    Task { await vm.fetchBMR() }
} label: { ... }
```

If BMRInputView uses a synchronous `NavigationLink(value: OnboardingStep.location)` without calling `fetchBMR()`, that is fine — the BMR call is optional (local calculation is the fallback). Do not break the NavigationLink.

---

## Error 7 — `AppState` has no `lang` key in Constants

**File:** `App/AppState.swift` reads `Constants.Storage.lang`

**File:** `Utilities/Constants.swift`

Verify `Constants.Storage.lang` exists. If it is missing, add it to the `Storage` enum:
```swift
static let lang = "lang"
```
It should already be present — just confirm.

---

## After all fixes

1. Run **Cmd+B** — zero errors required.
2. If any `invalid redeclaration` errors remain after Error 1 fix, search the entire project for any other files that declare `OnboardingViewModel` and remove the duplicate.
3. If any error mentions `extremelyActive`, that case was in the old duplicate class — confirm it is gone after the full file replacement in Error 1.
4. Run the app in Simulator — complete the full onboarding flow (6 screens), land on Home tab, all 5 tabs must be tappable without crashing.
