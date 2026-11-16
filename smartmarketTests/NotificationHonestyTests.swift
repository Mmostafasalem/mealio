import XCTest
import UserNotifications
@testable import smartmarket

@MainActor
private final class NotificationCenterSpy: NotificationCenterClient {
    var status: UNAuthorizationStatus = .authorized
    var pending = ["deal_1", "meal_morning", "deal_42", "logging_evening"]
    var delivered = ["deal_2", "meal_lunch"]
    var categories: Set<UNNotificationCategory> = [
        UNNotificationCategory(identifier: "DEAL_ALERT", actions: [
            UNNotificationAction(identifier: "BUY_DEAL", title: "Add", options: [])
        ], intentIdentifiers: []),
        UNNotificationCategory(identifier: "MEAL_REMINDER", actions: [], intentIdentifiers: [])
    ]
    var added: [UNNotificationRequest] = []

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func pendingIdentifiers() async -> [String] { pending }
    func deliveredIdentifiers() async -> [String] { delivered }
    func notificationCategories() async -> Set<UNNotificationCategory> { categories }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }
    func removePending(withIdentifiers ids: [String]) { pending.removeAll { ids.contains($0) } }
    func removeDelivered(withIdentifiers ids: [String]) { delivered.removeAll { ids.contains($0) } }
    func add(_ request: UNNotificationRequest) { added.append(request) }
}

@MainActor
final class NotificationHonestyTests: XCTestCase {
    func testPermissionCheckRemovesOldPendingAndDeliveredDealsButPreservesOtherNotifications() async {
        let center = NotificationCenterSpy()
        let service = NotificationService(center: center)
        await service.checkPermission()
        XCTAssertEqual(center.pending, ["meal_morning", "logging_evening"])
        XCTAssertEqual(center.delivered, ["meal_lunch"])
        XCTAssertEqual(Set(center.categories.map(\.identifier)), ["MEAL_REMINDER"])
        XCTAssertEqual(service.authorizationStatus, .authorized)
        // Repeated foreground/permission checks are safe.
        await service.checkPermission()
        XCTAssertEqual(center.pending, ["meal_morning", "logging_evening"])
    }

    func testCleanupDoesNotDependOnNotificationAuthorization() async {
        for status in [UNAuthorizationStatus.denied, .notDetermined, .provisional] {
            let center = NotificationCenterSpy()
            center.status = status
            let service = NotificationService(center: center)
            await service.checkPermission()
            XCTAssertEqual(center.pending, ["meal_morning", "logging_evening"])
            XCTAssertEqual(center.delivered, ["meal_lunch"])
            XCTAssertFalse(center.categories.contains { $0.identifier == "DEAL_ALERT" })
        }
    }

    func testCatalogDiscountProximityAndExpiryNeverScheduleEvenWithPermission() {
        let center = NotificationCenterSpy()
        let service = NotificationService(center: center)
        service.authorizationStatus = .authorized
        // Coordinates, claimed savings, and an expiry do not verify retailer data.
        let deal = Deal(id: 1, name: "Milk", brand: "Example", emoji: "🥛", store: "Rimi",
                        originalPrice: 4, discountedPrice: 1, discount: 75, category: "dairy",
                        kcalPer100g: 50, proteinPer100g: 3, carbsPer100g: 5, fatPer100g: 2,
                        weeklyQty: 1, unit: "1L", expiresIn: "today", allergens: [],
                        latitude: 54.7, longitude: 25.3)
        XCTAssertFalse(service.scheduleDealNotification(for: deal, storeName: "Rimi", storeId: "rimi"))
        XCTAssertTrue(center.added.isEmpty)
        XCTAssertFalse(center.pending.contains("deal_1"))
    }

    func testAgentStartupDiscardsOldCatalogAlertQueue() {
        let state = AppState.shared
        let saved = state.dealNotifications
        let loop = AgentLoop()
        defer {
            loop.stop()
            state.dealNotifications = saved
        }
        state.dealNotifications = [
            Deal(id: 1, name: "Milk", brand: "Example", emoji: "🥛", store: "Rimi",
                 originalPrice: 4, discountedPrice: 1, discount: 75, category: "dairy",
                 kcalPer100g: 50, proteinPer100g: 3, carbsPer100g: 5, fatPer100g: 2,
                 weeklyQty: 1, unit: "1L", expiresIn: "today", allergens: [],
                 latitude: 54.7, longitude: 25.3)
        ]
        // No suspension between start and stop: the background tick cannot run
        // or make a request during this test of synchronous startup cleanup.
        loop.start(appState: state)
        loop.stop()
        XCTAssertTrue(state.dealNotifications.isEmpty)
    }

    func testLegacyAddActionCannotMatchResponseHandlerAction() {
        // The existing app delegate compares responses with this shared constant.
        // Old delivered BUY_DEAL responses must no longer add unverified groceries.
        XCTAssertNotEqual(NotificationService.actionBuyID, "BUY_DEAL")
        XCTAssertNotEqual(NotificationService.actionBuyID, UNNotificationDefaultActionIdentifier)
        XCTAssertNotEqual(NotificationService.actionBuyID, UNNotificationDismissActionIdentifier)
    }

    func testPermissionRequestDoesNotPromiseUnimplementedRemindersAndStillCleansUp() async {
        let center = NotificationCenterSpy()
        let service = NotificationService(center: center)
        let enabled = await service.requestPermission()
        XCTAssertFalse(enabled)
        XCTAssertTrue(center.added.isEmpty)
        XCTAssertEqual(center.pending, ["meal_morning", "logging_evening"])
        XCTAssertEqual(center.delivered, ["meal_lunch"])
    }

    func testCancelRemovesDeliveredAsWellAsPendingDeal() {
        let center = NotificationCenterSpy()
        center.delivered.append("deal_1")
        let service = NotificationService(center: center)
        service.cancelDealNotification(dealID: 1)
        XCTAssertFalse(center.pending.contains("deal_1"))
        XCTAssertFalse(center.delivered.contains("deal_1"))
        XCTAssertTrue(center.delivered.contains("meal_lunch"))
    }
}
