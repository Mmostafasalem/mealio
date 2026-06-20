import Foundation

/// Stale-while-revalidate cache backed by memory + UserDefaults.
/// Use `getStale` to show cached data immediately while fetching fresh in background.
actor CacheService {
    static let shared = CacheService()
    private init() {}

    private struct Entry: Codable {
        let payload: Data
        let expiresAt: Date
        var isExpired: Bool { Date() > expiresAt }
    }

    private var memory: [String: Entry] = [:]

    // MARK: - Fresh read (memory → disk → nil)

    func get<T: Decodable>(_ type: T.Type, key: String) -> T? {
        if let entry = memory[key] {
            if !entry.isExpired { return decode(type, from: entry.payload) }
            memory.removeValue(forKey: key)
        }
        guard let entry = loadFromDisk(key: key), !entry.isExpired else { return nil }
        memory[key] = entry
        return decode(type, from: entry.payload)
    }

    // MARK: - Stale read (returns expired data so UI has something to show)

    func getStale<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let entry = memory[key] ?? loadFromDisk(key: key)
        return entry.flatMap { decode(type, from: $0.payload) }
    }

    // MARK: - Write

    func set<T: Encodable>(_ value: T, key: String, ttl: TimeInterval) {
        guard let payload = try? JSONEncoder().encode(value) else { return }
        let entry = Entry(payload: payload, expiresAt: Date().addingTimeInterval(ttl))
        memory[key] = entry
        saveToDisk(entry, key: key)
    }

    // MARK: - Invalidate

    func invalidate(key: String) {
        memory.removeValue(forKey: key)
        UserDefaults.standard.removeObject(forKey: diskKey(key))
    }

    // MARK: - Disk helpers

    private func diskKey(_ key: String) -> String { "algocache_\(key)" }

    private func loadFromDisk(key: String) -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: diskKey(key)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private func saveToDisk(_ entry: Entry, key: String) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: diskKey(key))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Keys + TTLs

extension CacheService {
    enum Keys {
        static let deals = "v1_deals"
    }
    enum TTL {
        static let deals: TimeInterval = 30 * 60  // 30 minutes
    }
}
