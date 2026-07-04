import Foundation
import UserNotifications

@MainActor
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    static let categoryID  = "DEAL_ALERT"
    static let actionBuyID = "BUY_DEAL"
    static let actionSkipID = "SKIP_DEAL"

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var permissionGranted: Bool { authorizationStatus == .authorized }

    // MARK: - Setup

    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .authorized {
            registerActions()
        }
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            authorizationStatus = granted ? .authorized : .denied
            if granted { registerActions() }
            return granted
        } catch {
            return false
        }
    }

    private func registerActions() {
        let buy  = UNNotificationAction(identifier: Self.actionBuyID,
                                        title: "✅ Yes, add to list",
                                        options: [])
        let skip = UNNotificationAction(identifier: Self.actionSkipID,
                                        title: "❌ No thanks",
                                        options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID,
                                              actions: [buy, skip],
                                              intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Schedule a deal push (fires immediately; works from background)

    func scheduleDealNotification(for deal: Deal, storeName: String, storeId: String) {
        let content = UNMutableNotificationContent()
        content.title  = "\(deal.emoji) \(deal.name) nearby"
        content.body   = "\(deal.brand) at \(storeName) — about €\(String(format: "%.2f", deal.discountedPrice)). Add to your grocery list?"
        content.sound  = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            "food_id":       String(deal.id),
            "product_name":  deal.name,
            "store_name":    storeName,
            "store_id":      storeId,
            "discount_price": deal.discountedPrice,
            "quantity":      "\(deal.weeklyQty) \(deal.unit)"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "deal_\(deal.id)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelDealNotification(dealID: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["deal_\(dealID)"])
    }
}
