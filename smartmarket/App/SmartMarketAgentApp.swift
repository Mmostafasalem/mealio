import SwiftUI
import CoreSpotlight
import UserNotifications

@main
struct SmartMarketAgentApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Constants.Storage.appearanceOverride) private var appearanceOverride = ""

    /// nil follows the iPhone setting.
    private var preferredScheme: ColorScheme? {
        switch appearanceOverride {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// One curve for every root swap; a short fade under Reduce Motion.
    static var rootTransition: Animation { UIAccessibility.isReduceMotionEnabled ? .reducedFade : .rootSwap }
    private var rootTransition: Animation? { Self.rootTransition }

    /// How a whole screen leaves and arrives: the old one grows a touch as it fades
    /// (as if we pass through it), the new one settles in from slightly smaller.
    private func rootSwap(leavingScale: CGFloat) -> AnyTransition {
        guard !UIAccessibility.isReduceMotionEnabled else { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                           removal: .opacity.combined(with: .scale(scale: leavingScale)))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // A shared floor, so a cross-fade never shows the window behind it.
                Color.surfaceGrouped.ignoresSafeArea()
                if !appState.hasSeenWelcome {
                    WelcomeView {
                        withAnimation(Self.rootTransition) { appState.hasSeenWelcome = true }
                        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                    }
                    .transition(rootSwap(leavingScale: 1.08))
                    .zIndex(2)
                } else if appState.isOnboarded {
                    MainTabView()
                        .transition(rootSwap(leavingScale: 1.04))
                        .zIndex(1)
                } else {
                    OnboardingFlow()
                        .transition(rootSwap(leavingScale: 1.04))
                        .zIndex(appState.isOnboarded ? 0 : 1.5)
                }
            }
            .animation(rootTransition, value: appState.isOnboarded)
            .animation(rootTransition, value: appState.hasSeenWelcome)
            .preferredColorScheme(preferredScheme)
            .foregroundStyle(Color.labelPrimary)
            .environment(appState)
            .tint(Color.brandPrimary)
            // nourlo:// links (widgets) and Spotlight results open screens through the router.
            .onOpenURL { AppRouter.shared.open($0) }
            .onContinueUserActivity(CSSearchableItemActionType) { AppRouter.shared.handle($0) }
            .safeAreaInset(edge: .bottom) {
                if PrivateSyncService.shared.deletionPending {
                    VStack(spacing: 6) {
                        Text(PrivateSyncService.shared.status).font(.footnote)
                        Button("Retry iCloud Deletion") { Task { await PrivateSyncService.shared.sync() } }
                            .disabled(PrivateSyncService.shared.isSyncing)
                    }
                    .padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            .id(appState.uiIdentity)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await PrivateSyncService.shared.sync() } }
                // The daily loop: apply savers on open, line up tonight's nudge on leaving.
                if phase == .active { DailyLoopStore.shared.refresh() }
                if phase == .background { ReminderStore.shared.scheduleStreakNudges(DailyLoopStore.shared.stateForNudge()) }
            }
            .task(id: appState.isOnboarded) {
                // Let the screen swap finish before the start-up work begins, so it stays smooth.
                try? await Task.sleep(for: .milliseconds(800))
                // Reads Train's exercise drawings on a background queue so they're ready when Train opens.
                ExerciseDrawings.preload()
                SpotlightIndexer.shared.indexIfNeeded()
                ReminderStore.shared.streakState = { DailyLoopStore.shared.state }
                // A new week brings new lines to the workout reminder.
                Task { await ReminderStore.shared.reschedule() }
                DailyLoopStore.shared.startObservingCart()
                DailyLoopStore.shared.onTodayKeptChange = { ReminderStore.shared.scheduleStreakNudges($0) }
                await PrivateSyncService.shared.start()
                await NotificationService.shared.checkPermission()
                appState.agentLoop.start(appState: appState)
            }
        }
    }
}

// MARK: - AppDelegate (notification responses)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MotionSettings.prepare()
        // UI tests only: start with an empty cart, stock and plan (a launch argument
        // can't do this itself, because it would hide everything the app saves later).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-NourloUITesting"), args.contains("-NourloEmptyKitchen") {
            for key in ["shoppingCart_v1", "nourloStock_v1", "cartStockLinks_v1", Constants.Storage.currentMealPlan] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            // The shared stores may already have read the old values: read again.
            ShoppingCartService.shared.reloadFromStorage()
            StockStore.shared.reload()
            AppState.shared.weeklyMealPlan = nil
        }
        // Native navigation titles follow the same adaptive palette as content.
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor(Color.labelPrimary)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: UIColor(Color.labelPrimary)]
        UNUserNotificationCenter.current().delegate = self
        // Apple features. Each is safe to call more than once and degrades
        // gracefully when a capability (Health, App Group) isn't available.
        NourloTips.configure()                  // before any view with a tip appears
        WidgetSync.shared.start()               // keeps widgets and Siri answers current
        WorkoutSession.shared.restore()         // resumes a workout, or logs one finished from the lock screen
        HealthService.shared.start()            // syncs with Apple Health while it's turned on
        NourloIntents.start()                   // the foods Siri knows by name
        return true
    }

    // Called when user acts on a notification (app in foreground OR background)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if info["streakNudge"] != nil {
            await MainActor.run { NotificationCenter.default.post(name: .openHome, object: nil) }
            return
        }
        guard let foodIdStr  = info["food_id"]       as? String,
              let foodId     = Int(foodIdStr),
              let name       = info["product_name"]   as? String,
              let storeName  = info["store_name"]      as? String
        else { return }

        // discount_price is serialised as NSNumber by UNNotification; cast via NSNumber
        let price    = (info["discount_price"] as? NSNumber)?.doubleValue ?? 0.0
        let quantity = info["quantity"] as? String ?? "1"

        if response.actionIdentifier == NotificationService.actionBuyID {
            await MainActor.run {
                guard AppState.shared.isOnboarded else { return }
                // GroceryStorage is the single source of truth for the grocery list UI.
                // Build a GroceryItem and write directly to it, then notify observers.
                let item = GroceryItem(
                    id: UUID().uuidString,
                    foodId: String(foodId),
                    foodName: name,
                    quantity: quantity,
                    estimatedPrice: price,
                    storeId: info["store_id"] as? String ?? storeName.lowercased(),
                    storeName: storeName,
                    isBought: false
                )
                GroceryStorage.add(item)
                NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
            }
        }
        // Skip = do nothing
    }

    // Show notification even when app is foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
