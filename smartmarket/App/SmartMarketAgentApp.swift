import SwiftUI
import UserNotifications
import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await NotificationService.shared.checkPermission() }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo

        guard
            let foodID       = info["food_id"]        as? String,
            let productName  = info["product_name"]   as? String,
            let storeName    = info["store_name"]      as? String,
            let storeID      = info["store_id"]        as? String,
            let price        = info["discount_price"]  as? Double,
            let quantity     = info["quantity"]        as? String
        else {
            completionHandler()
            return
        }

        if response.actionIdentifier == NotificationService.actionBuyID {
            let item = GroceryItem(
                id: UUID().uuidString,
                foodId: foodID,
                foodName: productName,
                quantity: quantity,
                estimatedPrice: price,
                storeId: storeID,
                storeName: storeName,
                isBought: false
            )
            GroceryStorage.add(item)
            NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    static let groceryListDidChange = Notification.Name("groceryListDidChange")
    static let mealPlanDidUpdate    = Notification.Name("mealPlanDidUpdate")
}

// MARK: - App

@main
struct SmartMarketAgentApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            if appState.isOnboarded {
                MainTabView()
                    .environment(appState)
                    .task {
                        _ = try? await APIService.shared.checkHealth()
                        appState.agentLoop.start(appState: appState)
                    }
            } else {
                OnboardingFlow()
                    .environment(appState)
            }
        }
    }
}
