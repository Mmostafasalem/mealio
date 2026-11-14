import Foundation

/// An explicit allowlist keeps tokens, locations, device preferences and caches
/// out of iCloud. Existing local persistence remains the source for offline UI.
@MainActor
enum SyncStorageAdapter {
    // App Review 5.1.3(ii): personal health information must not go to iCloud.
    // Excludes profile, BMR, intake, diets/allergies and nutrition meal plans.
    static let scalarKeys = SyncDataPolicy.scalarKeys
    static let listKeys = SyncDataPolicy.listKeys

    static func snapshot() throws -> [String: Data] {
        var result: [String: Data] = [:]
        for key in scalarKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                result[key] = try PropertyListSerialization.data(fromPropertyList: value,
                                                               format: .binary, options: 0)
            }
        }
        for key in listKeys {
            if var data = UserDefaults.standard.data(forKey: key) {
                if key == groceryKey { data = try groceryRows(in: data, planned: false) }
                result.merge(try SyncSnapshotCodec.split(data, prefix: key)) { _, new in new }
            }
        }
        return result
    }

    private static let groceryKey = Constants.Storage.groceryList
    /// Missing-ingredient rows derived from the (unsynced) meal plan.
    private static let plannedPrefix = "planned_"

    /// Returns only the planned (`planned == true`) or only the shareable rows
    /// of an encoded grocery list. Planned rows come from the meal plan, which
    /// is health-derived and device-local, so they never go to iCloud.
    private static func groceryRows(in data: Data, planned: Bool) throws -> Data {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CocoaError(.coderInvalidValue)
        }
        let kept = rows.filter { (($0["id"] as? String)?.hasPrefix(plannedPrefix) ?? false) == planned }
        return try JSONSerialization.data(withJSONObject: kept)
    }

    static func apply(_ values: [String: Data]) throws {
        // Validate all payloads before modifying any local store.
        var scalars: [String: Any] = [:]
        for key in scalarKeys {
            if let data = values[key] {
                scalars[key] = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            }
        }
        var lists: [String: Data] = [:]
        for key in listKeys { lists[key] = try SyncSnapshotCodec.join(values, prefix: key) }
        // Inbound rows replace only the shareable part of the grocery list:
        // drop any planned rows from older builds and keep local planned rows.
        if let inbound = lists[groceryKey] {
            let shared = try JSONSerialization.jsonObject(with: try groceryRows(in: inbound, planned: false)) as? [Any] ?? []
            let localPlanned = UserDefaults.standard.data(forKey: groceryKey)
                .flatMap { try? groceryRows(in: $0, planned: true) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] } ?? []
            lists[groceryKey] = try JSONSerialization.data(withJSONObject: shared + localPlanned, options: [.sortedKeys])
        }
        if let data = lists["shoppingCart_v1"] { _ = try JSONDecoder().decode([CartItem].self, from: data) }
        if let data = lists["groceryList"] { _ = try JSONDecoder().decode([GroceryItem].self, from: data) }
        for key in scalarKeys {
            if let value = scalars[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for (key, data) in lists { UserDefaults.standard.set(data, forKey: key) }
        ShoppingCartService.shared.reloadFromStorage()
        FoodLogStore.shared.reload()
        AppState.shared.reloadStoredData()
        NotificationCenter.default.post(name: .personalDataDidChange, object: nil)
        NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
        NotificationCenter.default.post(name: .mealPlanDidUpdate, object: nil)
    }
}
