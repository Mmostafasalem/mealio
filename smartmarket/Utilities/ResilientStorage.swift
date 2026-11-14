import Foundation

/// Decoding helpers for persisted UserDefaults blobs that must not lose data.
///
/// Arrays are decoded element by element, so one malformed element drops only
/// itself. Whenever anything can't be read, the raw bytes are copied to
/// `"<key>.corrupt"` before the caller's next save can overwrite them.
enum ResilientStorage {

    static func backupKey(for key: String) -> String { key + ".corrupt" }

    /// Decodes a JSON array stored under `key`, skipping unreadable elements.
    static func loadArray<T: Decodable>(_ type: T.Type, key: String,
                                        defaults: UserDefaults = .standard) -> [T] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return decodeArray(type, from: data, key: key, defaults: defaults)
    }

    static func decodeArray<T: Decodable>(_ type: T.Type, from data: Data, key: String,
                                          defaults: UserDefaults = .standard) -> [T] {
        guard let lossy = try? JSONDecoder().decode([Lossy<T>].self, from: data) else {
            backUp(data, key: key, defaults: defaults)
            return []
        }
        let values = lossy.compactMap(\.value)
        if values.count != lossy.count { backUp(data, key: key, defaults: defaults) }
        return values
    }

    /// Decodes a single value, backing up the raw bytes if it can't be read.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, key: String,
                                     defaults: UserDefaults = .standard) -> T? {
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            backUp(data, key: key, defaults: defaults)
            return nil
        }
    }

    static func backUp(_ data: Data, key: String, defaults: UserDefaults = .standard) {
        appLog("[Storage] could not fully decode \(key); raw data kept in \(backupKey(for: key))")
        defaults.set(data, forKey: backupKey(for: key))
    }

    /// Decodes one array element; a failure yields nil instead of failing the array.
    struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}
