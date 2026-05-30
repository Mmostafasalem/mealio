import UserNotifications
import Observation

@MainActor
@Observable
final class NotificationService {

    static let shared = NotificationService()

    var permissionGranted = false

    static let categoryID   = "DEAL_ALERT"
    static let actionBuyID  = "DEAL_BUY"
    static let actionSkipID = "DEAL_SKIP"

    private init() {}

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
            options: [.foreground]
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

    // MARK: - Schedule

    func scheduleDealNotification(for deal: MarketDeal) async {
        guard permissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Deal on \(deal.productName)"
        content.body = "\(deal.store.chain) · \(deal.quantity) — now €\(String(format: "%.2f", deal.discountPrice)) (−\(deal.discountPercent)%)"
        content.sound = .default
        content.categoryIdentifier = NotificationService.categoryID
        content.userInfo = [
            "deal_id":        deal.id,
            "product_name":   deal.productName,
            "store_name":     deal.store.name,
            "store_id":       deal.store.id,
            "food_id":        deal.productId,
            "discount_price": deal.discountPrice,
            "quantity":       deal.quantity
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

    func cancelDealNotification(dealID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["deal-\(dealID)"])
    }
}
