import Foundation

enum SyncSnapshotCodec {
    /// JSON arrays with stable identifiers are split into independent entries.
    /// Concurrent changes to different items therefore don't replace the list.
    static func split(_ data: Data, prefix: String) throws -> [String: Data] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CocoaError(.coderInvalidValue)
        }
        var result: [String: Data] = [:]
        for originalRow in rows {
            var row = originalRow
            let allowedFields: Set<String>?
            switch prefix {
            case "shoppingCart_v1": allowedFields = ["id", "catalogId", "name", "store", "price", "category", "quantity"]
            case "groceryList": allowedFields = ["id", "food_id", "food_name", "quantity", "estimated_price", "store_id", "store_name", "is_bought"]
            default: allowedFields = nil
            }
            if let allowedFields { row = row.filter { allowedFields.contains($0.key) } }
            guard let id = row["id"] as? String, !id.isEmpty else {
                throw CocoaError(.coderInvalidValue)
            }
            let identity: String
            if prefix == "shoppingCart_v1" {
                guard let catalog = row["catalogId"] as? String,
                      let store = row["store"] as? String else { throw CocoaError(.coderInvalidValue) }
                // UUIDs differ when two devices independently add the same line.
                let logicalID = try JSONEncoder().encode([catalog, store])
                identity = logicalID.base64EncodedString()
            } else { identity = id }
            let key = prefix + "/" + identity
            guard result[key] == nil else { throw CocoaError(.coderInvalidValue) }
            result[key] = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        }
        return result
    }

    static func join(_ values: [String: Data], prefix: String) throws -> Data {
        let rows = try values.keys.sorted().filter { $0.hasPrefix(prefix + "/") }.map { key in
            try JSONSerialization.jsonObject(with: values[key] ?? Data())
        }
        return try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    }
}
