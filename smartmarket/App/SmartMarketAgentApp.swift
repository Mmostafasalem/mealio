import SwiftUI
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

    var body: some Scene {
        WindowGroup {
            Group {
                if !appState.hasSeenWelcome {
                    WelcomeView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            appState.hasSeenWelcome = true
                            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                        }
                    }
                } else if appState.isOnboarded {
                    MainTabView()
                } else {
                    OnboardingFlow()
                }
            }
            .animation(.easeInOut(duration: 0.35), value: appState.isOnboarded)
            .animation(.easeInOut(duration: 0.35), value: appState.hasSeenWelcome)
            .preferredColorScheme(preferredScheme)
            .foregroundStyle(Color.labelPrimary)
            .environment(appState)
            .tint(Color.brandPrimary)
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
            }
            .task(id: appState.isOnboarded) {
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
        // Native navigation titles follow the same adaptive palette as content.
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor(Color.labelPrimary)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: UIColor(Color.labelPrimary)]
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called when user acts on a notification (app in foreground OR background)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
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
