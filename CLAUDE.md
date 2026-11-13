# Nourlo — Claude Code Context

## What This App Is
Nourlo (folder/target still named `smartmarket`; user-facing name is **Nourlo**) is an iOS app (SwiftUI) for Vilnius, Lithuania. It watches nearby grocery deals, matches them against the user's cart/favourites, builds AI meal plans around those foods within the user's weekly budget, and tracks daily calorie/macro intake with real food logging.

**Backend:** a Python Flask/WSGI app — `smartmarket-backend/server.py` wraps the business logic in `app.py` (run via gunicorn; deploy on **Render**, see `DEPLOY.md`). It serves a **curated product catalog** (`deals_data.json`) enriched with **Open Food Facts** nutrition (`openfoodfacts.py`), and uses **Groq** for AI meal plans / chat / recipes (model via `GROQ_MODEL` env, default `openai/gpt-oss-120b`; object endpoints use Groq JSON mode + a 25s/1-retry client). AI is only reachable when `AI_ACCOUNTS_ENABLED=1`; the hosted backend runs catalog-only until activation. No live scraping.

**Offline-first:** when the backend is unreachable the iOS app falls back to on-device data — bundled deals, local Mifflin-St Jeor BMR, and a **realistic meal plan composed from the user's Shop cart within budget** (`Services/FallbackData.swift`).

## Project Layout
```
smartmarket/
├── CLAUDE.md                         ← you are here
├── smartmarket.xcodeproj/
└── smartmarket/
    ├── App/
    │   ├── SmartMarketAgentApp.swift  ← @main, AppDelegate, Notification.Name extensions
    │   ├── AppState.swift             ← @Observable singleton — shared truth for profile, deals, plan
    │   ├── AgentLoop.swift            ← Background 30s tick: refresh deals → match → notify → regen plan
    │   ├── MainTabView.swift          ← 5-tab root (Home / MealPlan / Groceries / Map / Profile)
    │   └── OnboardingFlow.swift       ← NavigationStack + OnboardingStep; one question per screen (11 steps)
    ├── Features/
    │   ├── Home/                      ← Calorie ring, macro bars, deals carousel, meal preview, log sheet
    │   ├── MealPlan/                  ← Today / Week segmented view, regenerate button, recommendations
    │   ├── GroceryList/               ← Grouped-by-store list with price totals and share
    │   ├── Map/                       ← MapKit map with store pins, StoreDetailSheet (deals + recipes)
    │   ├── Profile/                   ← Body stats, dietary prefs, favourite foods, notification toggles
    │   └── Onboarding/               ← Name → Gender → Age → Height → Weight → Activity → Goal (→ Pace) → Location → Diet → Notifications → FavoriteFoods
    ├── Models/
    │   ├── BackendModels.swift        ← Deal, BMRRequest/Response, MealPlanRequest, WeeklyMealPlan, etc.
    │   ├── MealPlan.swift             ← MealEntry, MealPlan, GroceryItem, ShoppingRecommendation + bridge
    │   ├── MarketDeal.swift           ← MarketDeal, Store, DealType + mocked deals
    │   ├── UserProfile.swift          ← Gender, ActivityLevel, WeightGoal, LossPace, UserProfile
    │   ├── Food.swift                 ← FoodCategory, Food struct + static catalog (35 Lithuanian foods)
    │   ├── DietaryPreference.swift    ← DietaryPreference enum + UserDefaults persistence
    │   └── StoreRecipe.swift          ← StoreRecipe, StoreRecipeTemplate + catalog (14 recipes)
    ├── Services/
    │   ├── APIService.swift           ← actor; GET /deals, POST /bmr /meal-plan /gap-fillers /shopping-advice
    │   ├── LocationService.swift      ← @Observable CLLocationManager wrapper
    │   ├── NotificationService.swift  ← UNUserNotificationCenter, deal push with Buy/Skip actions
    │   └── BMRCalculator.swift        ← Pure Mifflin-St Jeor BMR/TDEE/macro math (no networking)
    ├── Components/
    │   ├── CalorieRingView.swift      ← Canvas-drawn animated ring
    │   ├── MacroProgressBarView.swift ← Protein/Carbs/Fat bars
    │   ├── DealCardView.swift         ← Horizontal scroll card (180×150)
    │   ├── DealNotificationBanner.swift ← In-app banner with 8s auto-dismiss
    │   ├── Shimmer.swift              ← Skeleton loader modifier
    │   ├── FlowLayout.swift           ← Wrapping chip layout (custom Layout)
    │   ├── OnboardingScaffold.swift   ← Shared onboarding frame: back, progress "3 / 11", title, pinned action; option rows
    │   └── RulerPicker.swift          ← Drag-to-pick tick ruler (replaces sliders) + kg/lb and cm/ft unit helpers
    └── Utilities/
        ├── Constants.swift            ← API URLs, UserDefaults keys, calorie floors, onboarding limits
        └── Color+Brand.swift          ← brandPrimary, brandDark, brandAmber, brandDanger + hex init
```

## Architecture
- **State management:** `@Observable` (Swift 5.9 Observation framework). `AppState.shared` is the central singleton. ViewModels are `@State` on their Views.
- **Concurrency:** Swift async/await throughout. `APIService` is an `actor`. `AgentLoop` and all ViewModels are `@MainActor`.
- **Navigation:** `NavigationStack` with typed `.navigationDestination`. Tab selection via `@State` binding passed to `GroceryListView`.
- **Persistence:** `UserDefaults` only — no CoreData or SwiftData. See `Constants.Storage` for all keys.
- **No third-party dependencies** in the iOS app (pure Apple frameworks).

## API (Python mock, `smartmarket-backend/app.py`)
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health` | Liveness check |
| GET | `/api/deals` | All deals (optional `?lat=&lon=&radius=` filter) |
| POST | `/api/bmr` | BMR/TDEE calc from `{weight,height,age,gender,activityLevel}` (web only; iOS computes BMR on-device via `BMRCalculator`) |
| POST | `/api/meal-plan` | 7-day meal plan from `{user,bmrData,groceryList,goal,lang}` |
| POST | `/api/gap-fillers` | Filler foods for calorie gaps |
| POST | `/api/shopping-advice` | Ranked shopping recommendations |

**Backend field names use camelCase in BMR request but the iOS `BMRRequest` sends `activityLevel` (camelCase). The backend also uses `activityLevel` as the key — be consistent.**

The backend returns `WeeklyMealPlan` with Lithuanian day keys (`pirmadienis`…`sekmadienis`). The iOS `DayPlan` uses `pietūs` (with accent) as a `CodingKey` alias for `pietus`.

## Current State (most audit items resolved)
The app builds clean (0 errors / 0 warnings) for the iOS 17 simulator. Verify with:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project smartmarket.xcodeproj -scheme smartmarket -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build CODE_SIGNING_ALLOWED=NO`

Key architecture notes:
- **Calorie/macro tracking** is real per-food logging in `FoodLogStore` (`Models/FoodLog.swift`), persisted to UserDefaults with automatic **daily reset**. The dashboard ring + macro tracks reflect what's actually logged (optimistic updates). Logging UI: `Features/Home/LogFoodSheet.swift` (3-tap, with a "From today's plan" one-tap section and household portions).
- **Grocery sources:** `ShoppingCartService` `[CartItem]` (Shop tab + budget) is the source of truth; on every change it **one-way mirrors into `GroceryStorage`** (`[GroceryItem]`) as `cart_`-prefixed rows, so the Groceries tab reflects the cart. `AppState.groceryList` `[Deal]` remains the legacy agent list. The offline meal plan reads the cart first (`FallbackData.resolveStock`). The cart posts `.cartDidChange`; `AgentLoop` debounce-regenerates the plan on it.
- **`APIService` is `@MainActor final class`** (not an actor) for Swift-6 isolation consistency; every method has an **offline fallback** (deals, BMR, meal plan, recipe).
- **API base URL + key** are read from `Info.plist` (`API_BASE_URL` / `API_KEY`); for production inject `API_KEY` via a gitignored xcconfig, not committed.
- **Backend security:** `X-API-Key` auth (timing-safe), 256 KB body cap, per-IP rate limiting, input clamps on AI handlers, security headers.

Still open / nice-to-have: fully unify the grocery stores (current cart→GroceryStorage sync is one-way; bought/delete state on cart rows doesn't round-trip); add a test target + CI; per-device auth tokens instead of a shared API key; real per-product nutrition for cart items (currently catalog/category estimates offline, Open Food Facts online); include cart items in the *online* meal-plan request (offline already does).

## ID Mapping (critical — easy to get wrong)
- `Food.catalog` uses **string IDs** like `"visc-file"`, `"lasisa"` (catalog IDs).
- `Food.backendId` is an optional `Int` that maps to `Deal.id` (backend integer).
- `MarketDeal.productId` is the backend integer **as a String** (e.g. `"101"`).
- `GroceryItem.foodId` should store the **catalog string ID**, not the backend integer string.
- When bridging favorites to deal matching: `favoriteFoodIDs (Set<String> catalog IDs)` → `Food.catalog.filter{favIDs.contains($0.id)}.compactMap{$0.backendId}` → compare to `Deal.id (Int)` or `MarketDeal.productId (String)`.

## Data Flow
```
AgentLoop (30s tick)
  └─ APIService.getDeals() → AppState.activeDeals [Deal]
  └─ match against AppState.favoriteFoodIDs → push notifications
  └─ APIService.generateMealPlan() → AppState.weeklyMealPlan [WeeklyMealPlan]
       └─ NotificationCenter.post(.mealPlanDidUpdate)
            └─ HomeViewModel listens → re-renders

User adds deal to grocery:
  HomeView banner → HomeViewModel.respondToDeal() → GroceryStorage.save([GroceryItem])
  Notification action → AppDelegate → GroceryStorage.add(GroceryItem)
  AppState.addDealToGrocery() → AppState.groceryList [Deal]   ← DIVERGES from above
```

## UserDefaults Keys (`Constants.Storage`)
| Key | Type | Contents |
|-----|------|----------|
| `hasCompletedOnboarding` | Bool | Onboarding gate |
| `userProfile` | Data | Encoded `UserProfile` |
| `bmrResponse` | Data | Encoded `BMRResponse` |
| `favoriteFoodIDs` | [String] | Catalog string IDs |
| `selectedDietaryFilters` | [String] | `DietaryPreference` raw values |
| `groceryList` | Data | Encoded `[GroceryItem]` (UI list) |
| `groceryDeals` | Data | Encoded `[Deal]` (agent list — duplicate, to be removed) |
| `currentMealPlan` | Data | Encoded `WeeklyMealPlan` |
| `caloriesConsumedToday` | Int | Logged kcal (no date — needs daily reset) |
| `loggedMealEntries` | [String] | MealEntry IDs marked as eaten |
| `lang` | String | `"en"` or `"lt"` |

## Brand Colors
```swift
Color.brandPrimary    // #E8698A  pink — buttons, active states
Color.brandDark       // #C94E70  darker pink — nav bars
Color.brandAmber      // #EF9F27  amber — discounts, warnings
Color.brandAmberLight // #FAEEDA  soft amber — chip backgrounds
Color.brandDanger     // #E24B4A  red — over-limit, errors
```

## Xcode / Build Info
- **Bundle ID:** `com.mostafa.mealio` · **Display name:** Nourlo · **Swift:** 5.0
- **iOS Deployment Target:** 17.0
- **No SPM/CocoaPods dependencies** (pure Apple frameworks)
- Backend dev: `cd smartmarket/smartmarket-backend && python app.py` (Flask dev server; `GROQ_API_KEY` only needed with `AI_ACCOUNTS_ENABLED=1`) or `gunicorn server:app` (prod). The Docker image defaults to `MEALIO_ENV=production` (fail-closed); pass `-e MEALIO_ENV=development` locally. See `DEPLOY.md`.
- Backend tests: `python -m pytest -q` in the backend folder (needs `pip install -r requirements.lock pytest`).
- Point the app at a backend by setting `API_BASE_URL` (and `API_KEY`) in `smartmarket/Info.plist`.

## Conventions
- Views own a `@State private var vm = XViewModel()` — never passed as environment unless explicitly needed
- All `@Observable` ViewModels are `@MainActor final class`
- `cardBackground()` helper defined as `private extension View` in `HomeView.swift` — copy the pattern elsewhere as needed
- Onboarding uses a single shared `OnboardingViewModel` passed via `@Bindable` to each screen (not environment)
- SF Symbols only — no custom image assets
- All monetary values are EUR (`€`), formatted as `String(format: "%.2f", value)`
- All weights kg, heights cm, distances metres (5000 = 5 km). Lbs / ft are display-only preferences (`Constants.Storage.weightUnit` / `heightUnit`); stored values stay metric
- Numeric input uses `RulerPicker`, not `Slider` (the two-thumb price `RangeSlider` is the exception)
- Onboarding screens don't scroll: use `OnboardingScaffold`, which pins the action and caps Dynamic Type at accessibility1
