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
            if let data = UserDefaults.standard.data(forKey: key) {
                result.merge(try SyncSnapshotCodec.split(data, prefix: key)) { _, new in new }
            }
        }
        return result
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
