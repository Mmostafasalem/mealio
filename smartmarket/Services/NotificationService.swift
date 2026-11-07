import Foundation
import UserNotifications

/// The notification boundary is injectable so cleanup and suppression can be
/// checked without permissions, timers, or delivering notifications to a device.
@MainActor
protocol NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func notificationCategories() async -> Set<UNNotificationCategory>
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func removePending(withIdentifiers identifiers: [String])
    func removeDelivered(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest)
}

@MainActor
private struct SystemNotificationCenterClient: NotificationCenterClient {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }
    func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map { $0.request.identifier }
    }
    func notificationCategories() async -> Set<UNNotificationCategory> {
        await center.notificationCategories()
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }
    func removePending(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func removeDelivered(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func add(_ request: UNNotificationRequest) { center.add(request) }
}

@MainActor
final class NotificationService {
    static let shared = NotificationService(center: SystemNotificationCenterClient())
    private let center: any NotificationCenterClient

    init(center: any NotificationCenterClient) { self.center = center }

    static let categoryID = "DEAL_ALERT"
    // Retire the old BUY_DEAL identifier too: the existing app delegate compares
    // against this constant. A queued response from an old notification must not
    // turn an unverified price/availability claim into a grocery-list mutation.
    // This replacement is never registered or attached to a notification.
    static let actionBuyID = "DISABLED_UNVERIFIED_DEAL_ACTION"
    static let actionSkipID = "SKIP_DEAL"

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var permissionGranted: Bool { authorizationStatus == .authorized }

    /// Called by app startup and Home's existing permission check. Always clean
    /// up old alerts, even when notification permission is denied or undetermined.
    func checkPermission() async {
        await removeLegacyDealNotifications()
        authorizationStatus = await center.authorizationStatus()
    }

    /// No user-controlled meal/logging scheduler exists yet, so there is no
    /// implemented feature for which to request notification permission.
    func requestPermission() async -> Bool {
        await checkPermission()
        return false
    }

    private func removeLegacyDealNotifications() async {
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix("deal_") }
        let delivered = await center.deliveredIdentifiers().filter { $0.hasPrefix("deal_") }
        center.removePending(withIdentifiers: pending)
        center.removeDelivered(withIdentifiers: delivered)
        let categories = await center.notificationCategories()
        center.setNotificationCategories(Set(categories.filter { $0.identifier != Self.categoryID }))
    }

    /// Compatibility boundary for legacy callers (including Home). Never infer a
    /// verified offer, nearby availability or expiry from curated catalog data.
    @discardableResult
    func scheduleDealNotification(for deal: Deal, storeName: String, storeId: String) -> Bool {
        cancelDealNotification(dealID: deal.id)
        return false
    }

    func cancelDealNotification(dealID: Int) {
        let identifiers = ["deal_\(dealID)"]
        center.removePending(withIdentifiers: identifiers)
        center.removeDelivered(withIdentifiers: identifiers)
    }
}
