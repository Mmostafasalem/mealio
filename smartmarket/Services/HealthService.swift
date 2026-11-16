import Foundation
import Observation
import HealthKit
import UIKit

// MARK: - Apple Health
//
// Optional and off by default. When the person turns it on, Nourlo writes
// logged food (energy, protein, carbs, fat) and workouts tracked with Start
// workout (real start/finish, estimated active energy) to Apple Health, and
// reads their latest weight plus today's steps and active energy. Workouts only
// marked as done are not written. Health data stays between this iPhone and
// Apple Health; a Health weight the person chooses to use becomes their profile
// weight and is then treated like one they typed.
//
// Writes are diff-based: the ids already written are remembered, so a change
// in the log writes only what is new and removes only what was deleted. Every
// sample carries the entry id in its metadata (and the correlation / workout a
// sync identifier), so a write can't be duplicated even if the bookkeeping is
// lost. Turning Health off stops syncing; data already in Health stays there.

@MainActor
@Observable
final class HealthService {

    static let shared = HealthService()

    /// Where the integration stands, for the settings screen and Profile row.
    enum Access: Equatable {
        /// This device has no Apple Health (some iPads).
        case unavailableDevice
        /// The request failed: this build lacks the HealthKit capability.
        case unavailableBuild
        case off
        /// On, but iOS has no answer for the write types yet.
        case needsPermission
        /// On, but writing was turned off in the Health app.
        case denied
        case ready
    }

    /// `HKHealthStore.isHealthDataAvailable()`.
    let isAvailable: Bool
    private(set) var isEnabled: Bool
    private(set) var isRequesting = false
    /// The authorization request threw: missing entitlement or capability.
    private(set) var authorizationFailed = false
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    /// A short sentence about the last sync, or why it failed.
    private(set) var lastSyncMessage: String?
    private(set) var stepsToday: Double?
    private(set) var activeKcalToday: Double?
    private(set) var latestWeightKg: Double?
    private(set) var latestWeightDate: Date?
    /// When the profile weight was last set in Nourlo (nil: not recorded).
    private(set) var profileWeightEditedAt: Date?
    /// Write permission as iOS reports it; refreshed on start, foreground and requests.
    private(set) var shareStatus: HKAuthorizationStatus = .notDetermined

    @ObservationIgnored private let store: HKHealthStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var healthQueries: [HKQuery] = []
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var needsResync = false
    /// Bumped when Health is turned off or data is deleted, so a sync that
    /// was already running drops its results instead of writing bookkeeping back.
    @ObservationIgnored private var generation = 0

    enum Keys {
        static let enabled = "appleHealthEnabled_v1"
        static let writtenFood = "appleHealthWrittenFood_v1"
        static let writtenWorkouts = "appleHealthWrittenWorkouts_v1"
        static let lastSync = "appleHealthLastSync_v1"
        static let lastSyncMessage = "appleHealthLastSyncMessage_v1"
        static let profileWeightEditedAt = "appleHealthProfileWeightEditedAt_v1"
        static let all = [enabled, writtenFood, writtenWorkouts, lastSync, lastSyncMessage, profileWeightEditedAt]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let available = HKHealthStore.isHealthDataAvailable()
        isAvailable = available
        store = available ? HKHealthStore() : nil
        isEnabled = available && defaults.bool(forKey: Keys.enabled)
        lastSync = defaults.object(forKey: Keys.lastSync) as? Date
        lastSyncMessage = defaults.string(forKey: Keys.lastSyncMessage)
        profileWeightEditedAt = defaults.object(forKey: Keys.profileWeightEditedAt) as? Date
    }

    // MARK: Types

    private static var energyType: HKQuantityType { HKQuantityType(.dietaryEnergyConsumed) }
    private static var foodQuantityTypes: [HKQuantityType] {
        [HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
         HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal)]
    }
    private static var shareTypes: Set<HKSampleType> {
        // Active energy is written only as part of a workout (its estimated burn).
        Set(foodQuantityTypes).union([HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)])
    }
    private static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.bodyMass), HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]
    }

    // MARK: Status

    var access: Access {
        if !isAvailable { return .unavailableDevice }
        if authorizationFailed { return .unavailableBuild }
        if !isEnabled { return .off }
        switch shareStatus {
        case .notDetermined: return .needsPermission
        case .sharingDenied: return .denied
        default: return .ready
        }
    }

    /// One plain sentence for the current access.
    var statusText: String {
        switch access {
        case .unavailableDevice: return "Apple Health isn't available on this device."
        case .unavailableBuild:  return "Apple Health isn't available in this build."
        case .off:               return "Off. Nothing is shared with Apple Health."
        case .needsPermission:   return "Nourlo needs your permission to use Apple Health."
        case .denied:            return "Allow access in the Health app → Sharing → Apps → Nourlo."
        case .ready:             return "On. Food and tracked workouts are saved to Apple Health."
        }
    }

    /// Short form for the Profile row.
    var shortStatus: String {
        switch access {
        case .unavailableDevice, .unavailableBuild: return "Not available"
        case .off: return "Off"
        case .needsPermission, .denied: return "Needs access"
        case .ready: return "On"
        }
    }

    /// The Home activity card shows once access has been asked for. Reads
    /// can be allowed even when writing is not.
    var showsActivity: Bool { access == .ready || access == .denied }

    /// Health's newer weight when it differs from the profile; never applied silently.
    func weightSuggestion(profileKg: Double) -> Double? {
        HealthSync.weightSuggestion(healthKg: latestWeightKg, measuredAt: latestWeightDate,
                                    profileKg: profileKg, profileEditedAt: profileWeightEditedAt)
    }

    /// ProfileViewModel calls this whenever a saved profile weight changes.
    func noteProfileWeightEdited(at date: Date = Date()) {
        profileWeightEditedAt = date
        defaults.set(date, forKey: Keys.profileWeightEditedAt)
    }

    // MARK: Lifecycle

    /// Call once at launch. Listens for log and workout changes and the app
    /// returning to the foreground; does real work only while Health is on.
    func start() {
        guard !started, isAvailable else { return }
        started = true
        let center = NotificationCenter.default
        observerTokens = [
            center.addObserver(forName: .foodLogDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { HealthService.shared.scheduleSync() }
            },
            center.addObserver(forName: .workoutsDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { HealthService.shared.scheduleSync() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { HealthService.shared.foreground() }
            },
        ]
        if isEnabled { activate() }
    }

    private func foreground() {
        guard isEnabled else { return }
        refreshShareStatus()
        Task { await refreshReads() }
        scheduleSync()
    }

    private func activate() {
        refreshShareStatus()
        startObserverQueries()
        Task { await refreshReads() }
        scheduleSync(delay: .zero)
    }

    /// Turning on asks iOS for access (the system sheet appears once); turning
    /// off stops syncing and leaves data already in Health where it is.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard isAvailable, let store, !isRequesting else { return }
            isRequesting = true
            defer { isRequesting = false }
            do {
                try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            } catch {
                // A denial doesn't throw; a missing HealthKit capability does.
                authorizationFailed = true
                isEnabled = false
                defaults.set(false, forKey: Keys.enabled)
                return
            }
            authorizationFailed = false
            isEnabled = true
            defaults.set(true, forKey: Keys.enabled)
            if started { activate() } else { start() }   // start() activates when on
        } else {
            isEnabled = false
            defaults.set(false, forKey: Keys.enabled)
            stopActivity()
        }
    }

    /// Asks again when iOS has no answer yet (the sheet won't show twice).
    func requestAccessAgain() async {
        await setEnabled(true)
    }

    /// Delete All Data: turns Health off and forgets what was written. Data
    /// already in Apple Health stays; the person manages it in the Health app.
    func resetForDataDeletion() {
        isEnabled = false
        stopActivity()
        authorizationFailed = false
        lastSync = nil
        lastSyncMessage = nil
        profileWeightEditedAt = nil
        for key in Keys.all { defaults.removeObject(forKey: key) }
    }

    private func stopActivity() {
        generation += 1
        debounceTask?.cancel()
        debounceTask = nil
        needsResync = false
        if let store { healthQueries.forEach { store.stop($0) } }
        healthQueries = []
        stepsToday = nil
        activeKcalToday = nil
        latestWeightKg = nil
        latestWeightDate = nil
    }

    private func refreshShareStatus() {
        guard let store else { return }
        let statuses = [store.authorizationStatus(for: Self.energyType),
                        store.authorizationStatus(for: HKObjectType.workoutType())]
        // Either kind of write allowed counts as on; the last sync message
        // says when one of them is refused.
        if statuses.contains(.sharingAuthorized) { shareStatus = .sharingAuthorized }
        else if statuses.contains(.sharingDenied) { shareStatus = .sharingDenied }
        else { shareStatus = .notDetermined }
    }

    // MARK: Reads

    /// Today's steps and active energy plus the latest weight. Called on
    /// appear, on foreground and when Health reports new data.
    func refreshReads() async {
        guard isEnabled, let store else { return }
        let gen = generation
        let start = Calendar.current.startOfDay(for: Date())
        let today = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        // Nourlo's own workout estimates are left out, so they never inflate
        // what the watch or iPhone measured.
        let notMine = NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        let measured = NSCompoundPredicate(andPredicateWithSubpredicates: [today, notMine])

        let steps = await Self.sum(store, HKQuantityType(.stepCount), measured, unit: .count())
        let kcal = await Self.sum(store, HKQuantityType(.activeEnergyBurned), measured, unit: .kilocalorie())
        let weight = await Self.latestWeight(store)
        guard gen == generation, isEnabled else { return }
        stepsToday = steps
        activeKcalToday = kcal
        latestWeightKg = weight?.kg
        latestWeightDate = weight?.date
    }

    private static func sum(_ store: HKHealthStore, _ type: HKQuantityType, _ predicate: NSPredicate,
                            unit: HKUnit) async -> Double? {
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate),
                                                     options: .cumulativeSum)
        do {
            return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        } catch {
            return nil
        }
    }

    private static func latestWeight(_ store: HKHealthStore) async -> (kg: Double, date: Date)? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.endDate)
    }

    private func startObserverQueries() {
        guard let store, healthQueries.isEmpty else { return }
        let types: [HKSampleType] = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
                                     HKQuantityType(.bodyMass)]
        healthQueries = types.map { type in
            Self.observerQuery(for: type) {
                Task { @MainActor in await HealthService.shared.refreshReads() }
            }
        }
        healthQueries.forEach { store.execute($0) }
    }

    /// Built outside the main actor: HealthKit calls the handler on its own queue.
    nonisolated private static func observerQuery(for type: HKSampleType,
                                                  onChange: @escaping @Sendable () -> Void) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            if error == nil { onChange() }
            completion()
        }
    }

    // MARK: Writes

    /// Coalesces bursts of changes into one sync about a second later.
    func scheduleSync(delay: Duration = .seconds(1)) {
        guard isEnabled, store != nil, !authorizationFailed else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            // A fresh task, so a later debounce can't cancel a sync mid-write.
            Task { await self?.syncNow() }
        }
    }

    /// Writes what is new and removes what was deleted. One sync at a time;
    /// a change during a sync runs one more pass afterwards.
    func syncNow() async {
        guard isEnabled, let store, !authorizationFailed else { return }
        if isSyncing { needsResync = true; return }
        isSyncing = true
        let gen = generation
        var outcome = SyncOutcome()
        repeat {
            needsResync = false
            await syncFood(store, generation: gen, outcome: &outcome)
            await syncWorkouts(store, generation: gen, outcome: &outcome)
        } while needsResync && gen == generation && isEnabled
        isSyncing = false
        if gen == generation, isEnabled {
            refreshShareStatus()
            let now = Date()
            lastSync = now
            lastSyncMessage = outcome.message
            defaults.set(now, forKey: Keys.lastSync)
            defaults.set(outcome.message, forKey: Keys.lastSyncMessage)
        }
        // Health was turned off and on again while this pass ran: its results were
        // dropped, but the sync asked for after turning back on must still happen.
        if needsResync, isEnabled {
            await syncNow()
        }
    }

    /// A workout was finished from the lock screen, possibly while the app was
    /// suspended: write it now, skipping the debounce, and ask iOS for time to
    /// finish so it doesn't wait for the next launch. Duplicates can't happen:
    /// syncs run one at a time, the diff remembers what was written, and every
    /// workout carries a sync identifier.
    func syncPromptlyInBackground() {
        guard isEnabled, store != nil, !authorizationFailed else { return }
        debounceTask?.cancel()
        debounceTask = nil
        let background = BackgroundTime()
        background.begin()
        Task { @MainActor in
            await self.syncNow()
            // A sync already running picks this change up in its next pass; wait for it.
            var waited = 0
            while self.isSyncing, waited < 250 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            background.end()
        }
    }

    /// One background task, ended once: by the sync finishing or by iOS running out of time.
    private final class BackgroundTime {
        private var id = UIBackgroundTaskIdentifier.invalid

        func begin() {
            id = UIApplication.shared.beginBackgroundTask(withName: "Apple Health workout") { [self] in
                // Out of time: what was written is remembered; the rest syncs next launch.
                MainActor.assumeIsolated { self.end() }
            }
        }

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    private struct SyncOutcome {
        var foods = 0
        var workouts = 0
        var removed = 0
        var denied = false
        var failed = false

        var message: String {
            if denied { return "Couldn't save to Apple Health. Allow access in the Health app → Sharing → Apps → Nourlo." }
            if failed { return "Some items couldn't be saved. Nourlo will try again." }
            var parts: [String] = []
            if foods > 0 { parts.append(foods == 1 ? "1 food" : "\(foods) foods") }
            if workouts > 0 { parts.append(workouts == 1 ? "1 workout" : "\(workouts) workouts") }
            var text = parts.isEmpty ? "Up to date." : "Saved \(parts.joined(separator: " and "))."
            if removed > 0 { text += removed == 1 ? " Removed 1 deleted item." : " Removed \(removed) deleted items." }
            return text
        }

        mutating func note(_ error: Error) {
            if let hk = error as? HKError, hk.code == .errorAuthorizationDenied || hk.code == .errorAuthorizationNotDetermined {
                denied = true
            } else {
                failed = true
            }
        }
    }

    private func syncFood(_ store: HKHealthStore, generation gen: Int, outcome: inout SyncOutcome) async {
        // A food entry is saved with all four values together, so it needs all four.
        guard Self.foodQuantityTypes.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
            outcome.denied = true
            return
        }
        var byID: [String: FoodLogEntry] = [:]
        for entry in FoodLogStore.shared.allEntries { byID[entry.id] = entry }
        let written = loadWritten(Keys.writtenFood)
        let plan = HealthSync.plan(current: byID.mapValues(\.loggedAt), written: written, now: Date())
        var keep = plan.keep

        if !plan.remove.isEmpty {
            do {
                try await Self.deleteFood(store, ids: plan.remove)
                outcome.removed += plan.remove.count
            } catch {
                outcome.note(error)
                for id in plan.remove { keep[id] = written[id] }   // try again next time
            }
        }

        if !plan.add.isEmpty {
            // Already in Health (bookkeeping lost, e.g. after reinstalling): just remember them.
            let existing = await Self.existingIDs(store, ids: plan.add, type: HKCorrelationType(.food))
            for id in existing { keep[id] = byID[id]?.loggedAt }
            let entries = plan.add.subtracting(existing).compactMap { byID[$0] }
            if !entries.isEmpty {
                do {
                    try await store.save(entries.map(Self.correlation(for:)))
                    for entry in entries { keep[entry.id] = entry.loggedAt }
                    outcome.foods += entries.count
                } catch {
                    outcome.note(error)
                }
            }
        }
        guard gen == generation else { return }
        saveWritten(keep, key: Keys.writtenFood)
    }

    private func syncWorkouts(_ store: HKHealthStore, generation gen: Int, outcome: inout SyncOutcome) async {
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            outcome.denied = true
            return
        }
        // Without active energy access the workout is saved without its burn estimate.
        let withEnergy = store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized
        // Only workouts tracked with Start workout; "Mark as done" stays in Nourlo.
        let byID = HealthSync.trackedWorkouts(WorkoutStore.shared.completed)
        let written = loadWritten(Keys.writtenWorkouts)
        let plan = HealthSync.plan(current: byID.mapValues(\.date), written: written, now: Date())
        var keep = plan.keep

        if !plan.remove.isEmpty {
            do {
                try await Self.delete(store, ids: plan.remove,
                                      types: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)])
                outcome.removed += plan.remove.count
            } catch {
                outcome.note(error)
                for id in plan.remove { keep[id] = written[id] }
            }
        }

        if !plan.add.isEmpty {
            let existing = await Self.existingIDs(store, ids: plan.add, type: HKObjectType.workoutType())
            for id in existing { keep[id] = byID[id]?.date }
            for id in plan.add.subtracting(existing) {
                guard let workout = byID[id], gen == generation else { continue }
                do {
                    try await Self.saveWorkout(workout, id: id, withEnergy: withEnergy, store: store)
                    keep[id] = workout.date
                    outcome.workouts += 1
                } catch {
                    outcome.note(error)
                }
            }
        }
        guard gen == generation else { return }
        saveWritten(keep, key: Keys.writtenWorkouts)
    }

    // MARK: HealthKit objects

    private static func correlation(for entry: FoodLogEntry) -> HKCorrelation {
        let values = HealthSync.foodValues(for: entry)
        let tag: [String: Any] = [HealthSync.entryKey: values.syncID, HKMetadataKeyFoodType: values.name]
        func sample(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) -> HKSample {
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: values.date, end: values.date, metadata: tag)
        }
        let objects: Set<HKSample> = [
            sample(.dietaryEnergyConsumed, .kilocalorie(), values.kcal),
            sample(.dietaryProtein, .gram(), values.proteinG),
            sample(.dietaryCarbohydrates, .gram(), values.carbsG),
            sample(.dietaryFatTotal, .gram(), values.fatG),
        ]
        var metadata = tag
        metadata[HKMetadataKeySyncIdentifier] = values.syncID
        metadata[HKMetadataKeySyncVersion] = HealthSync.syncVersion
        return HKCorrelation(type: HKCorrelationType(.food), start: values.date, end: values.date,
                             objects: objects, metadata: metadata)
    }

    private static func saveWorkout(_ workout: CompletedWorkout, id: String, withEnergy: Bool,
                                    store: HKHealthStore) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HealthSync.activityType(for: workout.kind)
        configuration.locationType = .unknown
        guard let interval = HealthSync.interval(for: workout) else { return }   // untracked: never written
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: interval.start)
        if withEnergy, let kcal = HealthSync.trackedEnergyKcal(for: workout) {
            let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                          quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                          start: interval.start, end: interval.end,
                                          metadata: [HealthSync.entryKey: id])
            try await builder.addSamples([energy])
        }
        try await builder.addMetadata([HKMetadataKeySyncIdentifier: id,
                                       HKMetadataKeySyncVersion: HealthSync.syncVersion,
                                       HealthSync.entryKey: id])
        try await builder.endCollection(at: interval.end)
        _ = try await builder.finishWorkout()
    }

    private static func tagged(_ ids: Set<String>) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HealthSync.entryKey, allowedValues: Array(ids)),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
    }

    /// Ids among `ids` that Nourlo already wrote as `type`.
    private static func existingIDs(_ store: HKHealthStore, ids: Set<String>, type: HKSampleType) async -> Set<String> {
        let descriptor = HKSampleQueryDescriptor(predicates: [.sample(type: type, predicate: tagged(ids))],
                                                 sortDescriptors: [])
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return Set(samples.compactMap { $0.metadata?[HealthSync.entryKey] as? String })
    }

    /// Removes logged foods: each food correlation found by query (correlations
    /// can't be bulk-deleted by type) together with its samples, then any tagged
    /// sample left on its own.
    private static func deleteFood(_ store: HKHealthStore, ids: Set<String>) async throws {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: tagged(ids))],
            sortDescriptors: [])
        let correlations: [HKCorrelation]
        do {
            correlations = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData {
            correlations = []
        }
        var objects: [HKObject] = []
        for correlation in correlations {
            objects.append(correlation)
            objects.append(contentsOf: Array(correlation.objects))
        }
        if !objects.isEmpty {
            do {
                try await store.delete(objects)
            } catch let error as HKError where error.code == .errorNoData {
                // Already gone.
            }
        }
        try await delete(store, ids: ids, types: foodQuantityTypes)
    }

    private static func delete(_ store: HKHealthStore, ids: Set<String>, types: [HKObjectType]) async throws {
        let predicate = tagged(ids)
        for type in types {
            // Nourlo can't delete a type whose writing was turned off; skip it rather than fail.
            if type is HKQuantityType, store.authorizationStatus(for: type) != .sharingAuthorized { continue }
            do {
                _ = try await store.deleteObjects(of: type, predicate: predicate)
            } catch let error as HKError where error.code == .errorNoData {
                continue   // nothing of this type to remove
            }
        }
    }

    // MARK: Bookkeeping

    private func loadWritten(_ key: String) -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: Double] else { return [:] }
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveWritten(_ written: [String: Date], key: String) {
        defaults.set(written.mapValues(\.timeIntervalSince1970), forKey: key)
    }
}
