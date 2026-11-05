import Foundation
import CloudKit
import Observation

@MainActor
@Observable
final class PrivateSyncService {
    static let shared = PrivateSyncService()
    private(set) var status = "Stored on this iPhone"
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    var isEnabled: Bool { journal.enabled }
    var deletionPending: Bool { journal.pendingReset }

    private struct Journal: Codable {
        var document = SyncDocument(generation: "initial")
        var baseline: [String: Data] = [:]
        var device = UUID().uuidString
        var account: String?
        var enabled = false
        var pendingReset = false
        var localErasurePending: Bool?
    }

    @ObservationIgnored private var journal: Journal
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var started = false
    @ObservationIgnored private lazy var container = CKContainer(identifier: "iCloud.com.mostafa.mealio")
    private let zoneID = CKRecordZone.ID(zoneName: "MealioPrivate")

    private static var journalURL: URL {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("PrivateSync", isDirectory: true)
        return directory.appendingPathComponent("journal.json")
    }

    private init() {
        journal = (try? Data(contentsOf: Self.journalURL))
            .flatMap { try? JSONDecoder().decode(Journal.self, from: $0) } ?? Journal()
    }

    func start() async {
        guard !started else { return }
        started = true
        // If the process stopped between recording erasure intent and clearing
        // local stores, erase first. Never upload those old rows as new edits.
        if journal.localErasurePending == true {
            await ProfileViewModel().resetOnboarding()
            guard journal.localErasurePending != true else {
                started = false
                status = "Could not finish interrupted deletion. Please retry."
                return
            }
        }
        for name in [UserDefaults.didChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.localDataChanged() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.session = UUID()
                await self?.sync()
            }
        })
        Task { await sync() }
    }

    func setEnabled(_ enabled: Bool) async {
        session = UUID()
        let previous = journal.enabled
        journal.enabled = enabled
        do { try persist() }
        catch {
            journal.enabled = previous
            status = "Could not save sync settings. Your data remains on this iPhone."
            return
        }
        if enabled { await sync() }
        else { status = journal.pendingReset ? "iCloud deletion waiting for connection" : "Sync off. Existing iCloud data is retained." }
    }

    func localDataChanged() {
        guard !applying, journal.enabled else { return }
        do {
            guard try SyncStorageAdapter.snapshot() != journal.baseline else { return }
            try captureLocalChanges()
            scheduled?.cancel()
            scheduled = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await self?.sync()
            }
        } catch { status = "Could not prepare sync. Your data remains on this iPhone." }
    }

    /// Persist the erasure intent before touching local stores. A failed/offline
    /// request is retried on launch/foreground, even if normal sync is disabled.
    func beginDeletion() throws {
        let previous = journal
        session = UUID()
        scheduled?.cancel()
        applying = true
        journal.document = SyncDocument(generation: UUID().uuidString)
        journal.baseline = [:]
        journal.pendingReset = journal.account != nil || journal.enabled
        journal.localErasurePending = true
        do { try persist() }
        catch { journal = previous; applying = false; throw error }
    }

    func finishDeletion() {
        applying = false
        journal.localErasurePending = false
        do { journal.baseline = try SyncStorageAdapter.snapshot(); try persist() }
        catch { status = "Deletion needs another attempt."; return }
        status = journal.pendingReset ? "Deleted here. iCloud deletion pending." : "Stored on this iPhone"
        Task { await sync() }
    }

    private func captureLocalChanges() throws {
        let snapshot = try SyncStorageAdapter.snapshot()
        journal.document.captureChanges(snapshot, since: journal.baseline, device: journal.device)
        journal.baseline = snapshot
        try persist()
    }

    func sync() async {
        guard (journal.enabled || journal.pendingReset), !isSyncing, !applying else { return }
        isSyncing = true
        defer { isSyncing = false }
        let currentSession = session
        do {
            guard try await container.accountStatus() == .available else {
                status = journal.pendingReset ? "iCloud deletion pending. Sign in to iCloud." : "iCloud unavailable. Data stays on this iPhone."
                return
            }
            let account = try await container.userRecordID().recordName
            guard currentSession == session else { return }
            if let bound = journal.account, bound != account {
                status = "Apple Account changed. Return to the original account to sync or delete its data."
                return
            }
            journal.account = account
            try persist()
            let db = container.privateCloudDatabase
            _ = try await db.save(CKRecordZone(zoneID: zoneID))
            let id = CKRecord.ID(recordName: "personal-data-v1", zoneID: zoneID)
            for attempt in 0..<4 {
                guard currentSession == session else { return }
                let record: CKRecord
                do { record = try await db.record(for: id) }
                catch let error as CKError where error.code == .unknownItem {
                    record = CKRecord(recordType: "MealioPersonalData", recordID: id)
                }
                guard currentSession == session else { return }
                if journal.enabled { try captureLocalChanges() }
                var merged = journal.document
                if let payload = record.encryptedValues["payload"] as? Data {
                    let remote = try JSONDecoder().decode(SyncDocument.self, from: payload).shoppingDataOnly()
                    if !journal.pendingReset {
                        // A fresh installation imports local data only into an
                        // initial cloud generation. An existing reset wins.
                        merged = merged.reconciled(with: remote)
                    }
                }
                merged = merged.shoppingDataOnly()
                let uploaded = merged
                let payload = try JSONEncoder().encode(uploaded)
                guard payload.count < 750_000 else {
                    status = "Sync storage limit reached. Your data remains on this iPhone."
                    return
                }
                record.encryptedValues["payload"] = payload as CKRecordValue
                do {
                    let result = try await db.modifyRecords(saving: [record], deleting: [],
                                                           savePolicy: .ifServerRecordUnchanged, atomically: true)
                    if let saved = result.saveResults[id] { _ = try saved.get() }
                    else { throw CocoaError(.fileWriteUnknown) }
                } catch let error as CKError where (error.code == .serverRecordChanged || error.code == .batchRequestFailed || error.code == .partialFailure) && attempt < 3 {
                    continue
                }
                guard currentSession == session else { return }
                // Fold in edits made while the network save was in flight.
                let afterNetwork = try SyncStorageAdapter.snapshot()
                if merged.generation == journal.document.generation {
                    merged = merged.merging(journal.document)
                    merged.captureChanges(afterNetwork, since: journal.baseline, device: journal.device)
                }
                applying = true
                defer { applying = false }
                if journal.enabled && merged.values != afterNetwork {
                    try SyncStorageAdapter.apply(merged.values)
                }
                journal.document = merged
                journal.baseline = try SyncStorageAdapter.snapshot()
                // Existing stores may materialize defaults (for example a 60€
                // budget) while reloading. Track those too, so an empty cloud
                // document doesn't repeatedly reset the UI on every foreground.
                if journal.enabled {
                    journal.document.captureChanges(journal.baseline, since: merged.values, device: journal.device)
                }
                let needsAnotherPass = journal.document != uploaded
                journal.pendingReset = false
                try persist()
                lastSync = Date()
                status = journal.enabled ? "Synced with your private iCloud" : "iCloud data deleted"
                if needsAnotherPass {
                    scheduled = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        await self?.sync()
                    }
                }
                return
            }
            status = "Sync busy. Try again shortly."
        } catch {
            status = journal.pendingReset ? "Deleted here. iCloud deletion waiting for connection." : "Sync unavailable. Changes are kept on this iPhone. Try again."
        }
    }

    private func persist() throws {
        let url = Self.journalURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: url, options: [.atomic, .completeFileProtection])
        var excluded = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }
}
