import Foundation

/// A logical clock avoids relying on device wall clocks. Tombstones are retained
/// until an explicit reset changes the generation; removing them resurrects data.
struct SyncDocument: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var value: Data?
        var clock: Int64
        var device: String

        func precedes(_ other: Entry) -> Bool {
            clock == other.clock ? device < other.device : clock < other.clock
        }
    }

    var generation: String
    private(set) var entries: [String: Entry] = [:]

    var values: [String: Data] { entries.compactMapValues(\.value) }

    mutating func capture(_ snapshot: [String: Data], device: String) {
        captureChanges(snapshot, since: values, device: device)
    }

    mutating func captureChanges(_ snapshot: [String: Data], since baseline: [String: Data], device: String) {
        let clock = (entries.values.map(\.clock).max() ?? 0) + 1
        for key in Set(baseline.keys).union(snapshot.keys) {
            guard baseline[key] != snapshot[key] else { continue }
            entries[key] = Entry(value: snapshot[key], clock: clock, device: device)
        }
    }

    func merging(_ other: SyncDocument) -> SyncDocument {
        precondition(generation == other.generation)
        var result = self
        for (key, entry) in other.entries {
            if let current = result.entries[key], !current.precedes(entry) { continue }
            result.entries[key] = entry
        }
        return result
    }

    /// A remote generation change is an erasure boundary, never a normal merge.
    func reconciled(with remote: SyncDocument) -> SyncDocument {
        generation == remote.generation ? merging(remote) : remote
    }

    func shoppingDataOnly() -> SyncDocument {
        var result = self
        result.entries = entries.filter { SyncDataPolicy.allows($0.key) }
        return result
    }
}
