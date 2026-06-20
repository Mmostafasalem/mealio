# SmartMarket Agent — Map View Prompt

Add a new Map tab to the app. Do not rewrite any existing file unless explicitly told to.

---

## Context

Existing files you will reference (do not rewrite):
- `Models/MarketDeal.swift` — `MarketDeal`, `Store` (has `latitude`, `longitude`, `chain`, `name`, `address`)
- `Models/Food.swift` — `Food.catalog`, `Food.id`, `Food.displayName`
- `Models/MealPlan.swift` — `MealEntry`, `MealPlan`
- `Features/Home/HomeViewModel.swift` — `deals: [MarketDeal]`, `nearbyDeals: [MarketDeal]`
- `Utilities/Constants.swift` — storage keys
- `Utilities/Color+Brand.swift` — brand colors
- `Services/LocationService.swift` — `LocationService.shared.userLocation`
- `App/MainTabView.swift` — TabView with 4 tabs (Home, Meal Plan, Grocery, Profile)

**Add MapKit framework** — it is a system Apple framework, no package needed. Import with `import MapKit`.

iOS 17 minimum. Swift 5.9. SwiftUI only.

---

## New files to create

### 1. `Features/Map/StoreMapViewModel.swift`

`@MainActor @Observable` class:

```
Properties:
- deals: [MarketDeal]          // all loaded deals, sourced from UserDefaults cache or HomeViewModel
- selectedStore: Store?        // currently tapped store pin
- storeDeals: [MarketDeal]     // deals for selectedStore, sorted: favourite deals first
- cameraPosition: MapCameraPosition   // centres on user location or Vilnius fallback
- isLoadingDeals: Bool
- errorMessage: String?

Computed:
- uniqueStores: [Store]        // deduplicated from deals

Methods:
- load() async
    Load deals from HomeViewModel's cached deals (read from UserDefaults key Constants.Storage.groceryList
    or re-use MarketDeal.mocked as fallback).
    Set cameraPosition to user's location if available, else CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797) (Vilnius centre), span delta 0.05.

- selectStore(_ store: Store)
    Set selectedStore = store.
    Filter deals to that store.
    Sort: deals whose productID is in UserDefaults favoriteFoodIDs come first, then rest alphabetically.

- dismissStore()
    Set selectedStore = nil, storeDeals = []

- recipesForStore(_ store: Store) -> [StoreRecipe]
    See StoreRecipe model below.
    Match discounted productIDs at that store against Food.catalog.
    For each food found, generate a simple recipe suggestion using a static lookup (see StoreRecipe).
```

---

### 2. `Models/StoreRecipe.swift`

Simple value type — no API call needed, all generated locally from the food catalog:

```swift
struct StoreRecipe: Identifiable {
    let id: String
    let name: String           // recipe name in Lithuanian/English
    let requiredFoodIDs: [String]   // food IDs needed
    let availableFoodIDs: [String]  // subset that are actually discounted at this store
    let matchCount: Int             // how many ingredients are on discount
    let totalIngredients: Int
    var coverSymbol: String         // SF Symbol representing the dish
}
```

Add a static catalog of at least 12 recipes that map to the food IDs in `Food.catalog`.
Examples: "Vištienos sriuba" needs chicken + carrot + onion; "Avižiniai pusryčiai" needs oats + milk + banana, etc.
Use the actual IDs from Food.catalog.

In `StoreMapViewModel.recipesForStore()`:
- Get discounted productIDs at that store
- For each recipe in StoreRecipe.catalog, count how many of its `requiredFoodIDs` are in the discounted set
- Only include recipes where `matchCount >= 1`
- Sort by `matchCount` descending (most ingredients on discount first)

---

### 3. `Features/Map/StoreMapView.swift`

**Layout:** `ZStack` with a full-screen `Map` and a bottom sheet overlay.

**Map layer:**
```
Map(position: $vm.cameraPosition) {
    // User location dot
    UserAnnotation()

    // Store pins — one per unique store
    ForEach(vm.uniqueStores) { store in
        Annotation(store.chain, coordinate: CLLocationCoordinate2D(latitude: store.latitude, longitude: store.longitude)) {
            StorePinView(
                store: store,
                isSelected: vm.selectedStore?.id == store.id,
                dealCount: vm.deals.filter { $0.store.id == store.id }.count
            ) {
                vm.selectStore(store)
            }
        }
    }
}
.mapStyle(.standard(elevation: .realistic))
.mapControls {
    MapUserLocationButton()
    MapCompassButton()
}
```

**StorePinView** (build inline or in Components):
- Circle with store chain color dot (use `Color(hex: store.chainColor)`)
- Store chain initial letter
- Small badge showing deal count
- Scale up with spring animation when `isSelected`
- Min tap area 44pt

**Bottom sheet:**
Use `.sheet(item: $vm.selectedStore)` with `presentationDetents([.medium, .large])` and `presentationDragIndicator(.visible)`.

Sheet content = `StoreDetailSheet(store: store, vm: vm)`

---

### 4. `Features/Map/StoreDetailSheet.swift`

Scrollable sheet showing all info for the selected store.

**Header:**
- Store chain color circle + chain name + full store name
- Address with `map.fill` SF Symbol
- "X deals available" subtitle

**Section: Your favourites**
Only shown if any deals at this store match the user's favourite food IDs.
Each row: heart.fill icon (brandDanger) + product name + quantity + discount price + "−X%" amber badge.
If empty, hide this section entirely.

**Section: All deals**
Same row layout but without the heart icon. Show remaining non-favourite deals.
Each row: store discount type badge (weekly_special → "Weekly", daily_fresh → "Fresh today", etc.)

**Section: Recipes you can make**
Header: "Recipes from today's discounts"
`ForEach(vm.recipesForStore(store))` → `RecipeCardView`:
- Cover SF Symbol (large, tinted brandPrimary)
- Recipe name
- "\(matchCount) of \(totalIngredients) ingredients on discount today" in caption
- Progress bar: matchCount / totalIngredients in brandPrimary
- List of required foods — discounted ones shown in brandPrimary, missing ones shown in secondary color with strikethrough (they need to be bought at full price)

**Section: Meals in common**
Header: "Matches your current meal plan"
Load today's MealPlan from UserDefaults (decode the same way HomeViewModel does).
For each meal entry in the plan whose food name matches any discounted product name at this store (case-insensitive contains), show:
- Meal type icon (sunrise = breakfast, sun.max = lunch, moon = dinner, sparkles = snacks)
- Meal entry food name + portion
- "On discount here" green badge

If no matches: show "No meal plan matches at this store" in secondary color.

---

## Update `App/MainTabView.swift`

Add a 5th tab between Grocery and Profile:

```swift
NavigationStack {
    StoreMapView()
}
.tabItem {
    Label("Map", systemImage: "map.fill")
}
.tag(3)
```

Shift ProfileView to tag 4. Update GroceryListView's "Browse deals" button to switch to tab 0 (unchanged).

In `StoreMapView`, add `.task { await vm.load() }` and `.onAppear { LocationService.shared.startUpdating() }`.

---

## Build requirements

- No third-party packages. MapKit + CoreLocation only.
- Every new view needs a `#Preview` with `MarketDeal.mocked` data.
- Dark mode: use only brand colors and system colors, never hardcoded hex in views.
- All interactive elements minimum 44pt touch target.
- Annotations must use `Annotation` (iOS 17 API), not the deprecated `MapAnnotation`.
- `Map(position:)` initialiser requires iOS 17 — correct.
- Build with zero errors (Cmd+B).
