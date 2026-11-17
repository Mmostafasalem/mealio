# Nourlo — Claude Code Context

## What This App Is
Nourlo (folder/target still named `smartmarket`; user-facing name is **Nourlo**) is an iOS app (SwiftUI). It builds meal plans on the device around the user's cart/favourites within their weekly budget, tracks daily calorie/macro intake with real food logging, keeps a home stock, and builds workouts (Train tab). It shows **no retailer names and uses no location**: one product catalogue with one estimated price per item.

**Backend:** a Python Flask/WSGI app — `smartmarket-backend/server.py` wraps the business logic in `app.py` (run via gunicorn; deploy on **Render**, see `DEPLOY.md`). It serves a **curated product catalog** (`deals_data.json`) enriched with **Open Food Facts** nutrition (`openfoodfacts.py`), and uses **Groq** for chat and recipes only (meal plans, workouts and shopping suggestions are always built on the phone: `AgentLoop.onlineMealPlans`, `MealPlanViewModel.onlineShoppingAdvice` are off) (model via `GROQ_MODEL` env, default `openai/gpt-oss-120b`; object endpoints use Groq JSON mode + a 25s/1-retry client). AI is only reachable when `AI_ACCOUNTS_ENABLED=1`; the hosted backend runs catalog-only until activation. No live scraping.

**Meal plans are always built on the phone** (`FallbackData.mealPlan`): one rule set for every day (breakfast grain + fruit + dairy; lunch/dinner a plate of ½ protein, ¼ carb, ¼ veg; snack fruit + nuts), the day split by the user's `MealSplit` (Profile › Your week and meals), foods from the cart and My Stock first; a role nothing owned fills takes a catalogue food marked `missing` (banner on Meals adds them). The weekly groceries (`WeeklyGroceryPlanner`, Shop) come from the onboarding foods plus staples for a balanced week, fitted to the budget left after the cart (two-per-group cap only when the budget is tight); the plan follows the groceries, not the other way round. `WeeklyReset` handles the user's week start and the once-a-week fresh-start question. UI tests pass `-NourloEmptyKitchen` to start with an empty cart, stock and plan.

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
    │   ├── MainTabView.swift          ← system tab bar, icons only: Home / Meals / + quick actions / Shop / Train; Profile opens from the avatar on Home
    │   └── OnboardingFlow.swift       ← NavigationStack + OnboardingStep; 7 steps: name, age and gender share the first page (gender is a segmented switch; age is a typed number with minus and plus), then one question per screen
    ├── Features/
    │   ├── Home/                      ← Calorie ring, macro bars, deals carousel, meal preview, log sheet
    │   ├── MealPlan/                  ← Today / Week segmented view, regenerate button, recommendations
    │   ├── GroceryList/               ← Grouped-by-store list with price totals and share
    │   ├── Profile/                   ← Body stats, dietary prefs, favourite foods, notification toggles
    │   └── Onboarding/               ← About you (name, surname, age, gender) → Height → Weight → Activity → Goal (→ Pace) → Diet → FavoriteFoods
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
- **One dependency** in the iOS app: the vendored, speech-only `Vendor/FluidAudio` local package (the optional offline speech model). Everything else is Apple frameworks.

## API (Python mock, `smartmarket-backend/app.py`)
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health` | Liveness check |
| GET | `/api/deals` | All deals (optional `?lat=&lon=&radius=` filter) |
| POST | `/api/bmr` | BMR/TDEE calc from `{weight,height,age,gender,activityLevel}` (web only; iOS computes BMR on-device via `BMRCalculator`) |
| POST | `/api/meal-plan` | 7-day meal plan from `{user,bmrData,groceryList,goal,lang}` |
| POST | `/api/gap-fillers` | Filler foods for calorie gaps |
| POST | `/api/shopping-advice` | Ranked shopping recommendations |
| POST | `/api/workout` | One training session from `{kind,level,minutes,focus,request,user}` (AI, metered; validated + clamped, static fallback) |

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
- **No remote SPM/CocoaPods dependencies**: the only package is the local `Vendor/FluidAudio`
- Backend dev: `cd smartmarket/smartmarket-backend && python app.py` (Flask dev server; `GROQ_API_KEY` only needed with `AI_ACCOUNTS_ENABLED=1`) or `gunicorn server:app` (prod). The Docker image defaults to `MEALIO_ENV=production` (fail-closed); pass `-e MEALIO_ENV=development` locally. See `DEPLOY.md`.
- Backend tests: `python -m pytest -q` in the backend folder (needs `pip install -r requirements.lock pytest`).
- Point the app at a backend by setting `API_BASE_URL` (and `API_KEY`) in `smartmarket/Info.plist`.

## Conventions
- Views own a `@State private var vm = XViewModel()` — never passed as environment unless explicitly needed
- All `@Observable` ViewModels are `@MainActor final class`
- `cardBackground()` helper defined as `private extension View` in `HomeView.swift` — copy the pattern elsewhere as needed
- Onboarding uses a single shared `OnboardingViewModel` passed via `@Bindable` to each screen (not environment)
- SF Symbols only — no custom image assets (the one bundled model is the exercise body mesh)
- All monetary values are EUR (`€`), formatted as `String(format: "%.2f", value)`
- All weights kg, heights cm, distances metres (5000 = 5 km). Lbs / ft are display-only preferences (`Constants.Storage.weightUnit` / `heightUnit`); stored values stay metric
- **Train:** `Features/Train/` (builder, workout detail, exercise library, history). `Models/Exercise.swift` holds the catalogue and workout types; `Services/WorkoutService.swift` has `WorkoutBuilder` (on-device fallback) and `WorkoutStore` (UserDefaults). Workouts are built by `WorkoutBuilder` on the phone (`/api/workout` is no longer called); workout mode (`WorkoutModeView`/`WorkoutModeModel`) logs sets into `TrainingLogStore`, Progress (`TrainingProgressView`) charts them, and `WorkoutBuilderView` builds custom workouts with `CustomExerciseStore`. `Components/ExerciseFigure.swift` draws the animated how-to stick figure (`ExerciseMotion` poses; every catalogue exercise must map to one)
- **Reminders:** `Services/ReminderStore.swift` (local repeating `UNCalendarNotificationTrigger`s, ids prefixed `reminder_`, off until the bell is turned on; `due()` feeds the Home stack). UI in `Features/Profile/RemindersView.swift`, reached from the bell in Home's header and from Profile
- **Chat** is a half-height popup (`AgentChatSheet`) led by the animated bowl; **exercise demos** for catalogue exercises are hand-drawn frames (`Components/ExerciseDrawing.swift`, chosen by the owner on 14 Nov 2026): three line-art frames per exercise from Workout Guide by Bryl Lim, based on Everkinetic (**CC BY-SA 4.0: the credit link under the drawing must stay, and the adapted drawings in `Resources/ExerciseFrames.json.zlib` stay CC BY-SA 4.0**), cross-faded 1→2→3→2, with the worked muscles filled red under the lines. `scripts/build-exercise-frames.py` builds the JSON from a clone of github.com/bryllim/workout-guide plus the marks in `scripts/exercise-frame-muscles.json` (numbered areas between the drawn lines, cut to a band; `--sheets` and `--check` render them for marking and review). All 302 Workout Guide drawings are used; all but 9 of the 312 catalogue exercises have one; the rest (AI-named ones, shadow boxing, marching …) use the posed line figure (`Components/ExerciseLineFigure.swift`): a white body with a dark outline, far-side limbs clearly darker with a fainter outline (front and back must stay easy to tell apart; the camera is aimed from the body's own facing, front three-quarter when standing, more side-on when lying, and bar pieces near the trunk sort wholly behind or in front of it), the worked muscles (`ExerciseMotion.muscles`) filled red inside the outline, equipment in light grey, drawn in perspective in a SwiftUI `Canvas`; drag turns the view. `FigureScene` (`Components/ExerciseFigure3D.swift`) is only the posing engine: a 16-bone body of fixed proportions (`BodyRig`), equipment nodes and camera framing, never rendered; `FigureScene.frame()` hands joints, feet and `propShapes()` to `LineFigureCanvas`. The old anatomy mesh (`ExerciseBody.bin`) and its credit are gone, so the SceneKit review tests (`ExerciseFigureSnapshotTests`, `ExerciseMotionFilmTests`, `ExerciseReviewTests`, `ClipCloseUpTests`) now render empty frames; only their joint-overlap checks still mean anything; the tab bar is the system `TabView` bar, icons only (names kept for VoiceOver): Home, Meals, + (opens a native quick-actions sheet without changing tab), Shop, Train; UI tests find tabs by name (`app.tabBars.buttons["Home"]`)
- **Exercise motion** has three sources, tried in this order by `ExerciseDemo`: (1) **captured clips** (`Components/ExerciseClips.swift`, `Resources/ExerciseClips.bin`): real human motion from the CMU Graphics Lab Motion Capture Database, baked by `scripts/build-exercise-clips.py` (+ `scripts/mocap_asfamc.py`; takes cached in `~/Library/Caches/nourlo-mocap`) and fitted onto the body by `FigureScene.apply(clip:at:)`; covers 27 clips: walk, run, stairs (with moving steps), squat (also back and goblet squat, arms held on the weight), lunge (dumbbells held at the sides), jump rope, twist, fold, armCircle, and 18 exercises that exist only as clips (lateral raise, reverse fly, jumping jacks, high knees, shadow boxing …). Clips come from CMU, the ARKit-vs-Vicon exercise set (Zenodo 6527283, CC BY 4.0) and 100STYLE (CC BY 4.0); each clip carries its source and `MotionClip.Credit` holds the credit text. **The movement credit link under the demo in `ExerciseGuideSheet` must stay** (CMU allows use in commercial products, not resale of the data; the CC BY sets require attribution). (2) **generated strides** (`Components/ExerciseGait.swift`), the fallback for walk/run/stairs. (3) **two drawn poses with rep tempo** (`Components/ExerciseRepTempo.swift`: slower lowering, working part leads, settle, breathing) for everything else. `smartmarketTests/ExerciseMotionFilmTests` writes film strips of all three to `/tmp/mealio-run/motion`. Licence-safe capture found but not yet used: a cycling set (Zenodo 10668611, CC BY 4.0). No licence-safe capture exists for push-up, plank, burpee or the barbell lifts
- **Ported motion components** live in `Components/Motion/` with the original constants noted in each header: `CartButton` (catalogue and cart quantity, via `QuantityStepper`), `StackPanel` (Train's in-place exercise browser), `BellButton`, `NotificationStack`, `ThinkingText`, `GooMenu`
- **No store names in UI.** Cart rows keep a `store` field only for storage/sync shape; everything belongs to `ShopStore.catalog`, and old retailer carts migrate on load
- **Apple features:** a `NourloWidgets` app extension (Calories and Today's meals widgets, lock-screen accessories, iOS 18 Control Center buttons, the workout Live Activity) reads `NourloSnapshot` from the App Group `group.com.mostafa.mealio` (`Shared/` is compiled into app and extension; its types are `nonisolated`); `WidgetSync` writes it. `HealthService` (off by default) syncs logged food and *tracked* workouts (Start workout sessions, real times) to Apple Health and reads weight, steps and active energy; Health data never leaves the device. Siri/Shortcuts/Spotlight live in `smartmarket/Intents/` and `SpotlightIndexer`; outside entry points open screens through `AppRouter` (one sheet path in `MainTabView`, links expire after 60 s). TipKit tips (`NourloTips`, hidden under `-NourloUITesting YES`, which every UI test passes), Liquid Glass comes from the system tab bar on iOS 26, barcode scanning (VisionKit) with Open Food Facts lookups that send only the barcode. Production and phone-test entitlements are separate (`Mealio.entitlements`, `PhoneTest.entitlements`); `scripts/install-phone-test.sh` signs with Xcode's account (Health + widgets) and falls back to the old profile without them
- **Voice commands** (`Features/Voice/`, opened as `MainSheet.voice` from the pink microphone between My Stock and History on Home (`.openVoice`; the small "i" above it explains it) and from the "+" quick actions; settings in `Features/Profile/VoiceSettingsView.swift`): tap once, speak, it stops when you stop. Four languages (`VoiceLanguage`: English, German, Arabic, Lithuanian; chosen in Profile › Voice). **Speech** (`Services/SpeechCapture.swift`, all on the device, **never a server**, all off the main actor): `SpeechCapture.route(for:)` picks Apple's speech model (`AnalyzerSpeechEngine(.speech)`, iOS 26: English, German), else Apple's dictation model (`.dictation`, iOS 26: Arabic and more), else `RecognizerSpeechEngine` (`SFSpeechRecognizer` with `requiresOnDeviceRecognition`), else the downloaded offline model. **Offline model** (`Services/OfflineSpeechModel.swift`): Parakeet TDT v3, an optional download from Hugging Face into Application Support, run by the vendored `Vendor/FluidAudio` (a trimmed local Swift package, the app's one dependency; see its README); it has no live text, so the engine reports `voice` activity instead. **Its credit line (NVIDIA, CC BY 4.0; FluidAudio, Apache 2.0) in Profile › Voice must stay.** **Meaning**: `VoiceRuleBook.parse(_:language:)` is one engine over a `VoiceLexicon` per language (`VoiceLexicon+*.swift`: sentence patterns, units, numbers, and a dictionary from that language's food and exercise words to the English names the catalogue uses) and gives a `VoiceCommand`; `VoiceCommandRunner.plan` makes it concrete (`VoiceFoodRanker` picks the plain, common food for a spoken name, `VoiceAmounts` turns "2 eggs" into grams) and `perform` runs it with an undo. When the rules leave something unplaced, `VoiceInterpreter` asks Apple Intelligence on the device (`FoundationModels`, guided generation) and then the person's own AI key (`VoiceAIKeyStore`: keychain, only while signed in, https only; Anthropic Messages API or an OpenAI-compatible endpoint); a model only fills in a `VoiceAIReply`, which becomes the same `VoiceCommand`. Food, cart and checklist changes are shown on a review card; a reading from the rules saves after a 4 s countdown that any touch stops, a reading from a model waits for a tap. UI tests pass a phrase with `-NourloVoiceTestPhrase` instead of using the microphone; `OfflineSpeechLiveTests` (opt-in, `TEST_RUNNER_NOURLO_PARAKEET_AUDIO`) downloads the real model. The Arabic and Lithuanian lexicons have not been checked by a native speaker
- **Food catalogue:** offline, `NutritionCatalog.json` (USDA, about 13,600 foods) plus `RegionalDishes.json` (`NutritionFood.Source.regional`: Lithuanian and Middle Eastern dishes). **No regional value is typed in by hand**: `scripts/build-regional-dishes.py` holds a typical recipe per dish (USDA ingredient ids with grams, and the finished weight) and computes the values; `scripts/test_nutrition_catalog.py` rebuilds and compares. To add a dish, add it to `DISHES` and run the script; a food that isn't a recipe (a cheese, a branded product) doesn't belong there. The app labels these "Nourlo recipe estimate". Online, the food logger looks packaged products up on Open Food Facts 1.2 s after typing stops (`LogFoodSheet.scheduleAutoProductSearch`; three letters or more, never a half-typed barcode, spaced by `NutritionCatalogService.searchSpacing` because OFF allows about ten text searches a minute; off under UI tests; the "Look up products as I type" switch turns it off; products are always searched worldwide, the market switch is gone)
- **Recipes without AI ("Cook with what I have")**: about 1,550 recipes from the Wikibooks Cookbook (**CC BY-SA 4.0: `CookbookCredit` with the page link and licence must stay under every recipe, and the adapted recipes stay CC BY-SA**), in `Resources/Recipes.json.zlib` (raw deflate). `scripts/build-wikibooks-recipes.py --download` caches the pages in `~/Library/Caches/nourlo-wikibooks`; a plain run rebuilds: `scripts/recipes/wikiparse.py` reads the wikitext, `scripts/recipes/ingredients.py` maps each ingredient page to one USDA record with kitchen weights (names checked against the catalogue), and a recipe is kept only when every line that matters is understood. No value is typed in by hand. In the app: `Models/CookbookRecipe.swift` (`CookbookLibrary`, `KitchenMatcher` matches stock food names by words, `CookbookSuggester`), `Features/Recipes/CookbookViews.swift` (opened from My Stock; "I cooked this" logs servings as a `.cookbook` food and can take the amounts out of stock). Salt, oil, spices, flour, sugar and stock count as kitchen basics
- Numeric input uses `RulerPicker`, not `Slider` (the two-thumb price `RangeSlider` is the exception)
- Onboarding screens don't scroll: use `OnboardingScaffold`, which pins the action and caps Dynamic Type at accessibility1
