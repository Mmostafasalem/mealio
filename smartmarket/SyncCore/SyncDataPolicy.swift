import Foundation

/// CloudKit is limited to general shopping data. Health data is never eligible.
enum SyncDataPolicy {
    static let scalarKeys = ["lang", "weeklyBudget", "priceOverrides_v1"]
    static let listKeys = ["shoppingCart_v1", "groceryList"]

    static func allows(_ key: String) -> Bool {
        scalarKeys.contains(key) || listKeys.contains { prefix in
            key.hasPrefix(prefix + "/") && key.count > prefix.count + 1
        }
    }
}
