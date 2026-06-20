# SmartMarket Agent — CoreLocation + Push Notifications Prompt

Paste this into Claude Code to add location-aware store filtering and push notifications to the existing iOS app.

---

## Context

You are extending an existing iOS app called **SmartMarket Agent**. The onboarding flow, main tab views, and all models/services already exist. Do NOT rewrite any existing file unless explicitly told to modify it. Add new files and make targeted edits only.

**Existing relevant files (do not rewrite):**
- `Models/MarketDeal.swift` — `MarketDeal`, `Store` (has `latitude` and `longitude` Double properties)
- `Models/UserProfile.swift` — `UserProfile` with `favoriteFoodIDs: [String]` (saved to UserDefaults)
- `Models/Food.swift` — `Food.catalog` with `id: String`
- `Features/Home/HomeViewModel.swift` — `deals: [MarketDeal]`, `activeDealBanner: MarketDeal?`
- `Features/Onboarding/OnboardingViewModel.swift` — `@Observable`, manages onboarding state
- `Features/Onboarding/FavoriteFoodsView.swift` — last onboarding screen, has a "Finish Setup" button
- `App/OnboardingFlow.swift` — `NavigationStack` with `OnboardingStep` enum
- `Utilities/Constants.swift` — storage keys
- `App/SmartMarketAgentApp.swift` — `@main` entry point

**iOS deployment target: iOS 17.0**
**Language: Swift 5.9, SwiftUI only, no third-party packages**
**Frameworks to add: CoreLocation, UserNotifications (both are Apple system frameworks — no package installation needed)**

---

## Part 1 — CoreLocation: Nearby Store Filtering

### 1a. New file: `Services/LocationService.swift`

Create an `@Observable` class (not an actor — it must be `@MainActor` for SwiftUI binding):

```swift
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    static let shared = LocationService()

    var userLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var locationError: String?

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()   // single one-shot fix — battery friendly
    }

    // CLLocationManagerDelegate
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.userLocation = loc
            self.locationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationError = error.localizedDescription
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    /// Returns true if the store is within `radius` metres of the user's location.
    /// Falls back to true (show all) when location is unavailable.
    func isNearby(_ store: Store, radius: Double = 1000) -> Bool {
        guard let userLocation else { return true }
        let storeLoc = CLLocation(latitude: store.latitude, longitude: store.longitude)
        return userLocation.distance(from: storeLoc) <= radius
    }
}
```

### 1b. New onboarding screen: `Features/Onboarding/LocationPermissionView.swift`

This screen is inserted as the **second step** of onboarding (after BMR input, before goal selection).

```swift
import SwiftUI
import CoreLocation

struct LocationPermissionView: View {

    @Environment(OnboardingViewModel.self) private var vm
    private let locationService = LocationService.shared

    var body: some View {
        VStack(spacing: 0) {

            OnboardingProgressBar(currentStep: 2)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.brandPrimary)

                VStack(spacing: 8) {
                    Text("Find deals near you")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("SmartMarket checks stores within 1 km of you for discounts on your favourite foods.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    FeatureRow(symbol: "map.fill",       text: "Only shows deals at stores you can reach")
                    FeatureRow(symbol: "battery.100",    text: "Uses one-shot location — no background drain")
                    FeatureRow(symbol: "lock.shield",    text: "Location never leaves your device")
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                // Primary: request permission and advance
                Button {
                    locationService.requestPermission()
                    vm.path.append(OnboardingStep.goal)
                } label: {
                    Label("Allow Location", systemImage: "location.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Secondary: skip without permission
                Button {
                    vm.path.append(OnboardingStep.goal)
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationBarHidden(true)
        .background(Color.surfaceGrouped.ignoresSafeArea())
    }
}

private struct FeatureRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        LocationPermissionView()
            .environment(OnboardingViewModel())
    }
}
```

### 1c. Update `OnboardingStep` enum in `App/OnboardingFlow.swift`

Add a `.location` case and insert it between `.bmr` and `.goal`:

Current enum:
```swift
enum OnboardingStep: Hashable {
    case goal, diet, favorites
}
```

Updated enum:
```swift
enum OnboardingStep: Hashable {
    case location, goal, diet, favorites
}
```

In the `navigationDestination` block, add:
```swift
case .location:
    LocationPermissionView()
```

In `BMRInputView.swift`, change the NavigationLink destination from `.goal` to `.location`:
```swift
// Change:
NavigationLink(value: OnboardingStep.goal) { ... }
// To:
NavigationLink(value: OnboardingStep.location) { ... }
```

Also update `OnboardingProgressBar` step counts — the bar now has 5 steps total. Update `OnboardingProgressBar.swift` so the total is 5, and update each onboarding view's `currentStep` argument:
- BMRInputView: step 1
- LocationPermissionView: step 2
- GoalSelectionView: step 3
- DietaryPreferencesView: step 4
- FavoriteFoodsView: step 5

### 1d. Update `HomeViewModel.swift` to filter by distance

Add a computed property `nearbyDeals`:
```swift
var nearbyDeals: [MarketDeal] {
    deals.filter { LocationService.shared.isNearby($0.store, radius: 1000) }
}
```

In `HomeView.swift`, replace every reference to `vm.deals` in the deals horizontal scroll section with `vm.nearbyDeals`.

Also in `HomeView.swift`, add `.onAppear { LocationService.shared.startUpdating() }` to the root `ScrollView` so location refreshes when the user opens the Home tab.

---

## Part 2 — Push Notifications with Yes/No Action Buttons

### 2a. New file: `Services/NotificationService.swift`

```swift
import UserNotifications
import Observation

@MainActor
@Observable
final class NotificationService {

    static let shared = NotificationService()

    var permissionGranted = false

    // Notification category and action identifiers — must match what the app registers
    static let categoryID   = "DEAL_ALERT"
    static let actionBuyID  = "DEAL_BUY"
    static let actionSkipID = "DEAL_SKIP"

    private override init() {}

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            permissionGranted = granted
            if granted { registerActionCategories() }
        } catch {
            permissionGranted = false
        }
    }

    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionGranted = settings.authorizationStatus == .authorized
    }

    // MARK: - Action categories

    private func registerActionCategories() {
        let buyAction = UNNotificationAction(
            identifier: NotificationService.actionBuyID,
            title: "Yes, add to list",
            options: [.foreground]          // opens the app
        )
        let skipAction = UNNotificationAction(
            identifier: NotificationService.actionSkipID,
            title: "No thanks",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: NotificationService.categoryID,
            actions: [buyAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Schedule a deal notification

    /// Call this whenever a deal is found for a favourite food.
    /// The notification fires immediately (timeInterval: 1).
    func scheduleDealNotification(for deal: MarketDeal) async {
        guard permissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Deal on \(deal.productName)"
        content.body = "\(deal.store.chain) · \(deal.quantity) — now €\(String(format: "%.2f", deal.discountPrice)) (−\(deal.discountPercent)%)"
        content.sound = .default
        content.categoryIdentifier = NotificationService.categoryID

        // Pass deal ID so the app knows which deal was acted on
        content.userInfo = [
            "deal_id":       deal.id,
            "product_name":  deal.productName,
            "store_name":    deal.store.name,
            "store_id":      deal.store.id,
            "food_id":       deal.productID,
            "discount_price": deal.discountPrice,
            "quantity":      deal.quantity
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "deal-\(deal.id)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to schedule: \(error.localizedDescription)")
        }
    }

    // MARK: - Cancel

    func cancelDealNotification(dealID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["deal-\(dealID)"])
    }
}
```

### 2b. New onboarding screen: `Features/Onboarding/NotificationPermissionView.swift`

This screen is inserted as the **last step before finishing** — after FavoriteFoodsView, or replace the current finish action with a two-step: first notifications, then done.

Actually, insert it between DietaryPreferencesView and FavoriteFoodsView by adding a `.notifications` case to `OnboardingStep`.

```swift
import SwiftUI

struct NotificationPermissionView: View {

    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {

            OnboardingProgressBar(currentStep: 4)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.brandAmber)

                VStack(spacing: 8) {
                    Text("Never miss a deal")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("We'll ping you the moment a discount appears on one of your favourite foods — with a one-tap option to add it to your grocery list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    FeatureRow(symbol: "heart.fill",     text: "Only notifies for your favourite foods")
                    FeatureRow(symbol: "location.fill",  text: "Only from stores within 1 km")
                    FeatureRow(symbol: "cart.badge.plus",text: "Tap yes to add to grocery list instantly")
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await NotificationService.shared.requestPermission()
                        vm.path.append(OnboardingStep.favorites)
                    }
                } label: {
                    Label("Enable notifications", systemImage: "bell.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandAmber)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    vm.path.append(OnboardingStep.favorites)
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationBarHidden(true)
        .background(Color.surfaceGrouped.ignoresSafeArea())
    }
}

private struct FeatureRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.brandAmber)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        NotificationPermissionView()
            .environment(OnboardingViewModel())
    }
}
```

Add `.notifications` to `OnboardingStep` and insert the screen between `.diet` and `.favorites`:
```swift
enum OnboardingStep: Hashable {
    case location, goal, diet, notifications, favorites
}
```

In `DietaryPreferencesView.swift`, change the NavigationLink destination:
```swift
// Change:
NavigationLink(value: OnboardingStep.favorites) { ... }
// To:
NavigationLink(value: OnboardingStep.notifications) { ... }
```

In `OnboardingFlow.swift` add the destination:
```swift
case .notifications:
    NotificationPermissionView()
```

Update step numbers: NotificationPermissionView is step 4, FavoriteFoodsView is step 5. Total steps = 5 — update `OnboardingProgressBar` total to 5.

### 2c. Update `SmartMarketAgentApp.swift` — handle notification responses

The app needs a `UNUserNotificationCenterDelegate` to receive the user's Yes/No tap even when the app is in the foreground.

Add a new class **above** `SmartMarketAgentApp`:

```swift
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await NotificationService.shared.checkPermission() }
        return true
    }

    // Called when the user taps an action button on the notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        guard
            let dealID      = info["deal_id"]       as? String,
            let foodID      = info["food_id"]        as? String,
            let productName = info["product_name"]   as? String,
            let storeName   = info["store_name"]     as? String,
            let storeID     = info["store_id"]       as? String,
            let price       = info["discount_price"] as? Double,
            let quantity    = info["quantity"]       as? String
        else {
            completionHandler()
            return
        }

        if response.actionIdentifier == NotificationService.actionBuyID {
            // "Yes, add to list" — create a GroceryItem and save it
            let item = GroceryItem(
                id: UUID().uuidString,
                foodID: foodID,
                foodName: productName,
                quantity: quantity,
                estimatedPrice: price,
                storeID: storeID,
                storeName: storeName,
                isBought: false
            )
            GroceryStorage.add(item)

            // Post a notification so HomeViewModel / GroceryListViewModel can refresh
            NotificationCenter.default.post(
                name: .groceryListDidChange,
                object: nil
            )
        }
        // "No thanks" — do nothing, just dismiss

        completionHandler()
    }

    // Show notification banner even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
```

Add `Notification.Name` extension somewhere (e.g. bottom of `SmartMarketAgentApp.swift`):
```swift
extension Notification.Name {
    static let groceryListDidChange = Notification.Name("groceryListDidChange")
}
```

Wire up the delegate in `SmartMarketAgentApp`:
```swift
@main
struct SmartMarketAgentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // ... rest of existing body unchanged
}
```

### 2d. Update `HomeViewModel.swift` — trigger deal notifications

In the `load()` method, after deals are fetched and the mealPlan is set, add a call to check for favourite deals and fire notifications:

```swift
private func checkAndNotifyFavouriteDeals() async {
    guard UserDefaults.standard.bool(forKey: "dealAlertsEnabled") else { return }
    await NotificationService.shared.checkPermission()
    guard NotificationService.shared.permissionGranted else { return }

    let favouriteIDs = Set(
        UserDefaults.standard.stringArray(forKey: Constants.Storage.favoriteFoodIDs) ?? []
    )
    guard !favouriteIDs.isEmpty else { return }

    let nearby = nearbyDeals
    for deal in nearby where favouriteIDs.contains(deal.productID) {
        await NotificationService.shared.scheduleDealNotification(for: deal)
    }
}
```

Call it at the end of `load()`:
```swift
await checkAndNotifyFavouriteDeals()
```

Also subscribe to the `groceryListDidChange` notification in `HomeViewModel.init()` so the grocery list stays fresh:
```swift
NotificationCenter.default.addObserver(
    forName: .groceryListDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.groceryList = GroceryStorage.load()
}
```

### 2e. Update `GroceryListViewModel.swift` — listen for background adds

In `GroceryListViewModel.init()` or `loadItems()`, also observe `groceryListDidChange`:
```swift
NotificationCenter.default.addObserver(
    forName: .groceryListDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.loadItems()
}
```

---

## Part 3 — Info.plist entries required

Add these two keys to `Info.plist` (or the app's target Info tab in Xcode). Without them the OS will silently deny the permission requests.

| Key | Value |
|---|---|
| `NSLocationWhenInUseUsageDescription` | `SmartMarket uses your location to find discount deals at stores within 1 km of you.` |

Push notifications do **not** need an Info.plist key — the `UNUserNotificationCenter.requestAuthorization` call is sufficient.

---

## Part 4 — `GroceryStorage` helper (verify it exists)

The `AppDelegate` above calls `GroceryStorage.add(item)` and `GroceryStorage.load()`. Verify that `GroceryStorage` in `HomeViewModel.swift` (or wherever it is defined) has:

```swift
enum GroceryStorage {
    static func load() -> [GroceryItem] { ... }       // decode from UserDefaults
    static func save(_ items: [GroceryItem]) { ... }  // encode to UserDefaults
    static func add(_ item: GroceryItem) {             // load, append, save
        var list = load()
        guard !list.contains(where: { $0.id == item.id }) else { return }
        list.append(item)
        save(list)
    }
}
```

If `add()` doesn't exist yet, add it.

---

## Build checklist

After all changes:

1. Cmd+B — zero errors.
2. Run in Simulator — complete onboarding, location screen appears as step 2, notification screen as step 4.
3. On a real device: grant location, grant notifications — both permission dialogs appear.
4. Trigger a test notification in the Home tab by calling `NotificationService.shared.scheduleDealNotification(for: MarketDeal.mocked[0])` from a debug button temporarily added to HomeView. Lock the phone — the banner appears with "Yes, add to list" and "No thanks" buttons.
5. Tap "Yes, add to list" — open app, go to Grocery List tab — the item should be there.
