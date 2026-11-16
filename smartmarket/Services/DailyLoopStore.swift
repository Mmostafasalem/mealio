import Foundation

/// What the daily loop reads from the rest of the app.
struct LoopSource {
    var foodEntries: [FoodLogEntry]
    var stockEntryIDs: Set<String>
    var workouts: [CompletedWorkout]
    var calorieGoal: Int
    var proteinGoal: Int
    var cartHasItems: Bool
    var cartWithinBudget: Bool
    var hasStock: Bool

    @MainActor static func live() -> LoopSource {
        let cart = ShoppingCartService.shared
        return LoopSource(
            foodEntries: FoodLogStore.shared.allEntries,
            stockEntryIDs: Set(StockStore.shared.logs.map(\.id)),
            workouts: WorkoutStore.shared.completed,
            calorieGoal: AppState.shared.userProfile.dailyCalorieGoal,
            proteinGoal: AppState.shared.bmrData?.macros.protein ?? 0,
            cartHasItems: !cart.cartItems.isEmpty,
            cartWithinBudget: cart.total <= cart.weeklyBudget,
            hasStock: !StockStore.shared.items.isEmpty)
    }
}

struct LoopState: Equatable {
    var streak = 0
    var longest = 0
    var quests: [Quest] = []
    var week: [WeekDot] = []
    var saversHeld = 0
    var todayKept = false
    var perfectToday = false
    /// Nourlo's mood from the loop alone (Home adds celebrate/thinking on top).
    var mood: MascotMood = .happy
}

/// Keeps Nourlo's progress ledger (on this device only — health-derived data
/// never goes to iCloud) and publishes today's quests and streak.
@MainActor
@Observable
final class DailyLoopStore {
    /// The app's store only runs once onboarding is done, so nothing is written
    /// to the ledger before setup or while Delete All Data is erasing it.
    static let shared = DailyLoopStore(isActive: {
        AppState.shared.isOnboarded && UserDefaults.standard.bool(forKey: Constants.Storage.hasCompletedOnboarding)
    })

    private(set) var state = LoopState()
    private(set) var ledger: [LoopEvent] = []
    /// Set when a quest is first seen done; Nourlo celebrates.
    private(set) var lastCompletion: Date?
    /// A streak milestone waiting to be shown.
    private(set) var pendingMilestone: Int?
    /// Called when today becomes kept or stops being kept (nudges reschedule).
    @ObservationIgnored var onTodayKeptChange: ((LoopState) -> Void)?

    static let key = "progressLedger"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentCalendar: () -> Calendar
    @ObservationIgnored private let source: @MainActor () -> LoopSource
    /// False while the user isn't onboarded: refresh and cart check-ins do nothing.
    @ObservationIgnored private let isActive: @MainActor () -> Bool
    private var calendar: Calendar { currentCalendar() }

    /// `calendar` is read on every refresh, so a time-zone change is picked up.
    init(defaults: UserDefaults = .standard, calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
         source: @escaping @MainActor () -> LoopSource = LoopSource.live,
         isActive: @escaping @MainActor () -> Bool = { true }) {
        self.defaults = defaults
        self.currentCalendar = calendar
        self.source = source
        self.isActive = isActive
        ledger = ResilientStorage.loadArray(LoopEvent.self, key: Self.key, defaults: defaults)
    }

    func inputs(now: Date = Date()) -> LoopInputs {
        let s = source()
        return LoopInputs(foodEntries: s.foodEntries, stockEntryIDs: s.stockEntryIDs, workouts: s.workouts,
                          calorieGoal: s.calorieGoal, proteinGoal: s.proteinGoal, cartHasItems: s.cartHasItems,
                          hasStock: s.hasStock, ledger: ledger, now: now, calendar: calendar)
    }

    func refresh(now: Date = Date()) {
        guard isActive() else { return }
        // Another store (or "delete my data") may have changed the stored ledger.
        ledger = ResilientStorage.loadArray(LoopEvent.self, key: Self.key, defaults: defaults)
        var i = inputs(now: now).prepared()
        let today = i.today
        var added: [LoopEvent] = []
        func add(_ e: LoopEvent) { added.append(e); i.ledger.append(e) }

        if !i.ledger.contains(where: { if case .loopStarted = $0 { return true }; return false }) {
            add(.loopStarted(today))
        }
        DailyLoop.keptDayEvents(i).forEach(add)
        DailyLoop.saverEvents(i).forEach(add)
        if DailyLoop.chosenQuests(day: today, i) == nil {
            add(.questsChosen(today, DailyLoop.pickQuests(for: today, i)))
        }
        i = i.prepared() // savers and records change which days count
        let quests = DailyLoop.quests(for: today, i)
        for q in quests where q.isDone && !i.ledger.contains(.questDone(today, q.id)) {
            add(.questDone(today, q.id))
            lastCompletion = now
        }
        if quests.count == 3, quests.allSatisfy(\.isDone), !i.ledger.contains(.perfectDay(today)) {
            add(.perfectDay(today))
        }
        if let m = DailyLoop.milestoneEvent(i) {
            add(m)
            if case let .milestone(_, n) = m { pendingMilestone = n }
        }
        if !added.isEmpty {
            ledger = i.ledger
            persist()
        }

        let wasKept = state.todayKept
        state = LoopState(streak: DailyLoop.streak(i), longest: DailyLoop.longestStreak(i), quests: quests,
                          week: DailyLoop.week(i), saversHeld: DailyLoop.saversHeld(i),
                          todayKept: DailyLoop.isKept(today, i), perfectToday: quests.count == 3 && quests.allSatisfy(\.isDone),
                          mood: DailyLoop.mood(i, justCompleted: false, generating: false))
        if state.todayKept != wasKept { onTodayKeptChange?(state) }
    }

    /// The user changed the cart. Counts for today only if it now has items
    /// and sits within the weekly budget.
    func cartChanged(now: Date = Date()) {
        guard isActive() else { return }
        let s = source()
        let today = DayKey(now, calendar: calendar)
        ledger = ResilientStorage.loadArray(LoopEvent.self, key: Self.key, defaults: defaults)
        if s.cartHasItems, s.cartWithinBudget, !ledger.contains(.budgetCheckIn(today)) {
            ledger.append(.budgetCheckIn(today))
            persist()
        }
        refresh(now: now)
    }

    convenience init(defaults: UserDefaults, calendar: Calendar, source: @escaping @MainActor () -> LoopSource,
                     isActive: @escaping @MainActor () -> Bool = { true }) {
        self.init(defaults: defaults, calendar: { calendar }, source: source, isActive: isActive)
    }

    /// Fresh state for scheduling tonight's nudge.
    func stateForNudge(now: Date = Date()) -> LoopState {
        refresh(now: now)
        return state
    }

    func consumeMilestone() { pendingMilestone = nil }

    /// Drops everything held in memory and re-reads the stored ledger (empty
    /// after Delete All Data). Observers and the nudge hook stay attached.
    func reset() {
        ledger = ResilientStorage.loadArray(LoopEvent.self, key: Self.key, defaults: defaults)
        state = LoopState()
        lastCompletion = nil
        pendingMilestone = nil
    }

    /// Cart edits can happen on any tab; listen once for the app's lifetime.
    @ObservationIgnored private var cartObserver: NSObjectProtocol?
    func startObservingCart() {
        guard cartObserver == nil else { return }
        cartObserver = NotificationCenter.default.addObserver(forName: .cartDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cartChanged() }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: Self.key) }
    }
}
