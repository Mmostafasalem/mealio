import SwiftUI
import UserNotifications

@main
struct SmartMarketAgentApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboarded {
                    MainTabView()
                } else {
                    OnboardingFlow()
                }
            }
            .environment(appState)
            .task {
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
              let storeName  = info["store_name"]      as? String,
              let price      = info["discount_price"]  as? Double
        else { return }

        let quantity = info["quantity"] as? String ?? "1"

        if response.actionIdentifier == NotificationService.actionBuyID {
            // Reconstruct a minimal Deal and add to grocery list
            await MainActor.run {
                let appState = AppState.shared
                // Find the full deal in activeDeals if possible; otherwise synthesise one
                if let full = appState.activeDeals.first(where: { $0.id == foodId }) {
                    appState.addDealToGrocery(full)
                } else {
                    // Minimal synthetic deal so it shows in grocery list
                    let deal = Deal(
                        id: foodId,
                        name: name,
                        brand: storeName,
                        emoji: "🛒",
                        store: storeName,
                        category: "grocery",
                        originalPrice: price,
                        discountedPrice: price,
                        discount: 0,
                        kcalPer100g: 0,
                        proteinPer100g: 0,
                        carbsPer100g: 0,
                        fatPer100g: 0,
                        weeklyQty: 1,
                        unit: quantity,
                        expiresIn: "7d",
                        allergens: []
                    )
                    appState.addDealToGrocery(deal)
                }
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
