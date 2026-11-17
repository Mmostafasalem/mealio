import Foundation

// MARK: - Daily loop
//
// Nourlo's daily habit loop, worked out from what the app already records
// (food log, stock use, workouts) plus a small ledger of things that have no
// dated history of their own (budget check-ins, savers, claimed quests).
// Everything here is pure: give it `LoopInputs`, get days, streak, quests and
// Nourlo's mood back. `DailyLoopStore` feeds it and keeps the ledger.

/// A local calendar day.
struct DayKey: Hashable, Comparable, Codable, CustomStringConvertible {
    let year: Int, month: Int, day: Int

    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    /// Start of the day.
    func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func adding(days: Int, calendar: Calendar) -> DayKey {
        // Noon avoids DST edges when stepping whole days.
        let noon = calendar.date(byAdding: .hour, value: 12, to: date(in: calendar)) ?? date(in: calendar)
        return DayKey(calendar.date(byAdding: .day, value: days, to: noon) ?? noon, calendar: calendar)
    }

    /// Days since 2001-01-01 in this calendar; a stable seed per day.
    func number(in calendar: Calendar) -> Int {
        let origin = DayKey(year: 2001, month: 1, day: 1).date(in: calendar)
        return calendar.dateComponents([.day], from: origin, to: date(in: calendar)).day ?? 0
    }

    static func < (a: DayKey, b: DayKey) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

enum QuestID: String, Codable, CaseIterable {
    case logAny, breakfast, threeMeals, protein, onTarget, workout, anyWorkout, fromStock, newFood, budget
}

/// What the ledger stores. Append-only; cleared only with all personal data.
enum LoopEvent: Codable, Equatable {
    case loopStarted(DayKey)
    case questDone(DayKey, QuestID)
    case perfectDay(DayKey)
    case budgetCheckIn(DayKey)
    case saverEarned(DayKey)
    case saverUsed(DayKey)
    case milestone(DayKey, Int)
    /// A past day that counted, remembered in case its source history is trimmed.
    case dayKept(DayKey)
    /// The three quests picked for a day, so they stay put all day.
    case questsChosen(DayKey, [QuestID])
}

struct LoopInputs {
    var foodEntries: [FoodLogEntry]
    /// Ids of food entries that came from using home stock.
    var stockEntryIDs: Set<String>
    var workouts: [CompletedWorkout]
    var calorieGoal: Int
    var proteinGoal: Int
    var cartHasItems: Bool
    var hasStock: Bool
    var ledger: [LoopEvent]
    var now: Date
    var calendar: Calendar

    var today: DayKey { DayKey(now, calendar: calendar) }

    // Per-refresh caches (see `prepared()`); nil means compute on demand.
    var cachedKept: Set<DayKey>?
    var cachedSaved: Set<DayKey>?
    var entriesByDay: [DayKey: [FoodLogEntry]]?
    var workoutsByDay: [DayKey: [CompletedWorkout]]?
    /// The first day each food id was logged.
    var firstSeen: [String: DayKey]?

    /// Buckets every entry by day once, so a refresh doesn't redo it per call.
    /// Call again after changing `ledger`.
    func prepared() -> LoopInputs {
        var i = self
        i.cachedKept = nil; i.cachedSaved = nil
        var byDay: [DayKey: [FoodLogEntry]] = [:]
        var first: [String: DayKey] = [:]
        for e in foodEntries {
            let d = DayKey(e.loggedAt, calendar: calendar)
            byDay[d, default: []].append(e)
            if let id = e.foodId, first[id].map({ d < $0 }) ?? true { first[id] = d }
        }
        var wByDay: [DayKey: [CompletedWorkout]] = [:]
        for w in workouts { wByDay[DayKey(w.date, calendar: calendar), default: []].append(w) }
        i.entriesByDay = byDay; i.workoutsByDay = wByDay; i.firstSeen = first
        i.cachedKept = DailyLoop.keptDays(i)
        i.cachedSaved = DailyLoop.savedDays(i)
        return i
    }
}

/// One dot in the Mon–Sun row. Past days that didn't count are just `.open`.
enum WeekDot: Equatable {
    case kept, saved, open, today(kept: Bool), future
}

enum DailyLoop {

    // MARK: Days

    static func keptDays(_ i: LoopInputs) -> Set<DayKey> {
        if let cached = i.cachedKept { return cached }
        var days = Set(i.entriesByDay.map { Array($0.keys) } ?? i.foodEntries.map { DayKey($0.loggedAt, calendar: i.calendar) })
        days.formUnion(i.workoutsByDay.map { Array($0.keys) } ?? i.workouts.map { DayKey($0.date, calendar: i.calendar) })
        for e in i.ledger {
            switch e {
            case let .budgetCheckIn(d), let .dayKept(d): days.insert(d)
            default: break
            }
        }
        return days
    }

    static func savedDays(_ i: LoopInputs) -> Set<DayKey> {
        if let cached = i.cachedSaved { return cached }
        var days = Set<DayKey>()
        for case let .saverUsed(d) in i.ledger { days.insert(d) }
        return days
    }

    static func isKept(_ day: DayKey, _ i: LoopInputs) -> Bool { keptDays(i).contains(day) }

    // MARK: Streak

    /// Consecutive kept-or-saved days ending yesterday, plus today if kept.
    /// Saved days bridge the run but don't add to it.
    static func streak(_ i: LoopInputs) -> Int {
        let kept = keptDays(i), saved = savedDays(i)
        return run(endingAt: kept.contains(i.today) ? i.today : i.today.adding(days: -1, calendar: i.calendar),
                   kept: kept, saved: saved, calendar: i.calendar)
    }

    static func longestStreak(_ i: LoopInputs) -> Int {
        let kept = keptDays(i), saved = savedDays(i)
        let days = kept.union(saved).sorted()
        var best = 0, current = 0
        var previous: DayKey?
        for d in days {
            if let p = previous, p.adding(days: 1, calendar: i.calendar) != d { current = 0 }
            if kept.contains(d) { current += 1 }
            best = max(best, current)
            previous = d
        }
        return best
    }

    private static func run(endingAt end: DayKey, kept: Set<DayKey>, saved: Set<DayKey>, calendar: Calendar) -> Int {
        var count = 0
        var d = end
        while true {
            if kept.contains(d) { count += 1 }
            else if !saved.contains(d) { break }
            d = d.adding(days: -1, calendar: calendar)
        }
        return count
    }

    // MARK: Week row

    static func week(_ i: LoopInputs) -> [WeekDot] {
        let kept = keptDays(i), saved = savedDays(i)
        // Always Monday–Sunday (the card's letters), whatever the locale's first day.
        let weekday = i.calendar.component(.weekday, from: i.now) // 1 = Sunday
        let offset = (weekday + 5) % 7
        let start = i.today.adding(days: -offset, calendar: i.calendar)
        return (0..<7).map { n in
            let d = start.adding(days: n, calendar: i.calendar)
            if d == i.today { return .today(kept: kept.contains(d)) }
            if d > i.today { return .future }
            if kept.contains(d) { return .kept }
            if saved.contains(d) { return .saved }
            return .open
        }
    }

    // MARK: Nourlo's mood

    static func mood(_ i: LoopInputs, justCompleted: Bool, generating: Bool) -> MascotMood {
        if generating { return .thinking }
        if justCompleted { return .celebrate }
        let today = i.today
        if isPerfect(day: today, i) { return .love }
        let kept = keptDays(i), saved = savedDays(i)
        if kept.contains(today) { return .happy }
        let hour = i.calendar.component(.hour, from: i.now)
        if hour >= 18, streak(i) >= 1 { return .worried }
        let yesterday = today.adding(days: -1, calendar: i.calendar)
        if !kept.contains(yesterday), !saved.contains(yesterday),
           run(endingAt: yesterday.adding(days: -1, calendar: i.calendar), kept: kept, saved: saved, calendar: i.calendar) >= 2 {
            return .sleepy
        }
        return .happy
    }
}

// MARK: - Quests

enum QuestDestination: Equatable { case logFood, train, shop, stock }

struct Quest: Identifiable, Equatable {
    let id: QuestID
    let title: String
    let symbol: String
    let current: Double
    let goal: Double
    let unit: String
    let isDone: Bool
    let destination: QuestDestination

    var fraction: Double { goal > 0 ? min(current / goal, 1) : (isDone ? 1 : 0) }
}

extension DailyLoop {
    static let easyQuests: [QuestID] = [.logAny, .breakfast, .anyWorkout]

    /// Quests that make sense for this user on this day.
    static func available(day: DayKey, _ i: LoopInputs) -> [QuestID] {
        let workoutDay = [0, 2, 4, 5].contains(((day.number(in: i.calendar) % 7) + 7) % 7)
        return QuestID.allCases.filter { id in
            switch id {
            case .protein: return i.proteinGoal > 0 && i.calorieGoal > 0
            case .onTarget: return i.calorieGoal > 0
            case .budget: return i.cartHasItems
            case .fromStock: return i.hasStock
            case .workout, .anyWorkout: return workoutDay
            case .logAny, .breakfast, .threeMeals, .newFood: return true
            }
        }
    }

    /// Today's three quests: slot 0 always an easy one. Stable for the day.
    static func quests(for day: DayKey, _ i: LoopInputs) -> [Quest] {
        if let ids = chosenQuests(day: day, i) { return ids.map { evaluate($0, day: day, i) } }
        return pickQuests(for: day, i).map { evaluate($0, day: day, i) }
    }

    /// The quests already picked for this day, if the ledger has them.
    static func chosenQuests(day: DayKey, _ i: LoopInputs) -> [QuestID]? {
        for case let .questsChosen(d, ids) in i.ledger where d == day { return ids }
        return nil
    }

    static func pickQuests(for day: DayKey, _ i: LoopInputs) -> [QuestID] {
        let seed = day.number(in: i.calendar)
        let ids = available(day: day, i).sorted { stableHash(seed, $0) < stableHash(seed, $1) }
        let easy = ids.filter { easyQuests.contains($0) }
        var picked = Array(easy.prefix(1))
        picked += ids.filter { !easyQuests.contains($0) }.prefix(2)
        if picked.count < 3 { picked += easy.dropFirst().prefix(3 - picked.count) }
        return picked
    }

    static func isPerfect(day: DayKey, _ i: LoopInputs) -> Bool {
        let qs = quests(for: day, i)
        return qs.count == 3 && qs.allSatisfy(\.isDone)
    }

    static func evaluate(_ id: QuestID, day: DayKey, _ i: LoopInputs) -> Quest {
        let entries = i.entriesByDay.map { $0[day] ?? [] } ?? i.foodEntries.filter { DayKey($0.loggedAt, calendar: i.calendar) == day }
        let workouts = i.workoutsByDay.map { $0[day] ?? [] } ?? i.workouts.filter { DayKey($0.date, calendar: i.calendar) == day }
        func make(_ title: String, _ symbol: String, _ current: Double, _ goal: Double, unit: String = "",
                  done: Bool? = nil, _ dest: QuestDestination) -> Quest {
            Quest(id: id, title: title, symbol: symbol, current: current, goal: goal, unit: unit,
                  isDone: done ?? (current >= goal), destination: dest)
        }
        switch id {
        case .logAny:
            return make("Log something you ate", "fork.knife", min(Double(entries.count), 1), 1, .logFood)
        case .breakfast:
            return make("Log breakfast", "sunrise.fill", entries.contains { $0.slot == .breakfast } ? 1 : 0, 1, .logFood)
        case .threeMeals:
            return make("Log 3 meals", "list.bullet.circle.fill", Double(Set(entries.map(\.slot)).count), 3, unit: "meals", .logFood)
        case .protein:
            let goal = (Double(i.proteinGoal) * 0.8).rounded()
            return make("Hit your protein", "bolt.fill", entries.reduce(0) { $0 + $1.proteinG }.rounded(), goal, unit: "g", .logFood)
        case .onTarget:
            let total = Double(entries.reduce(0) { $0 + $1.calories })
            let goal = Double(i.calorieGoal)
            let late = day < i.today || i.calendar.component(.hour, from: i.now) >= 17
            let near = goal > 0 && abs(total - goal) <= goal * 0.1
            return make("Land near your calories", "scope", total, goal, unit: "kcal",
                        done: near && Set(entries.map(\.slot)).count >= 2 && late, .logFood)
        case .workout:
            return make("Move for 20 minutes", "figure.walk", Double(workouts.reduce(0) { $0 + $1.minutes }), 20, unit: "min", .train)
        case .anyWorkout:
            return make("Do any workout", "figure.run", workouts.isEmpty ? 0 : 1, 1, .train)
        case .fromStock:
            return make("Cook from your stock", "cabinet", entries.contains { i.stockEntryIDs.contains($0.id) } ? 1 : 0, 1, .stock)
        case .newFood:
            let fresh: Bool
            if let first = i.firstSeen {
                fresh = entries.contains { e in e.foodId.map { first[$0] == day } ?? false }
            } else {
                let start = day.date(in: i.calendar)
                let seen = Set(i.foodEntries.filter { $0.loggedAt < start }.compactMap(\.foodId))
                fresh = entries.contains { $0.foodId.map { !seen.contains($0) } ?? false }
            }
            return make("Try something new", "sparkles", fresh ? 1 : 0, 1, .logFood)
        case .budget:
            return make("Shop within budget", "cart.fill", i.ledger.contains(.budgetCheckIn(day)) ? 1 : 0, 1, .shop)
        }
    }

    /// FNV-1a; `Hasher` is randomly seeded per launch, so it can't pick quests.
    static func stableHash(_ seed: Int, _ id: QuestID) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in "\(seed)-\(id.rawValue)".utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}

// MARK: - Savers and milestones

extension DailyLoop {
    static let milestones = [3, 7, 30, 100, 365]
    static let maxSavers = 2

    private static func loopStart(_ i: LoopInputs) -> DayKey? {
        i.ledger.compactMap { if case let .loopStarted(d) = $0 { return d } else { return nil } }.min()
    }

    /// Saver events to append so the ledger is up to date through yesterday.
    /// Earned every 7 consecutive kept days since the loop started (max 2
    /// held); used automatically, oldest first, on missed days that would
    /// otherwise end a streak. Returns [] once applied.
    static func saverEvents(_ i: LoopInputs) -> [LoopEvent] {
        guard let start = loopStart(i) else { return [] }
        let kept = keptDays(i)
        var ledger = Set(i.ledger.compactMap { SaverMark($0) })
        var out: [LoopEvent] = []
        var run = 0, held = 0
        var previousSaved = false
        var d = start
        let today = i.today
        while d < today {
            if ledger.contains(.used(d)) {
                held -= 1; previousSaved = true
            } else if kept.contains(d) {
                run += 1; previousSaved = false
                if run % 7 == 0 {
                    if ledger.contains(.earned(d)) { held += 1 }
                    else if held < maxSavers { out.append(.saverEarned(d)); ledger.insert(.earned(d)); held += 1 }
                }
            } else if (run > 0 || previousSaved) && held > 0 {
                out.append(.saverUsed(d)); ledger.insert(.used(d)); held -= 1; previousSaved = true
            } else {
                run = 0; previousSaved = false
            }
            d = d.adding(days: 1, calendar: i.calendar)
        }
        return out
    }

    /// Past days (since the loop started) that counted but aren't recorded yet.
    static func keptDayEvents(_ i: LoopInputs) -> [LoopEvent] {
        guard let start = loopStart(i) else { return [] }
        var recorded = Set<DayKey>()
        for case let .dayKept(d) in i.ledger { recorded.insert(d) }
        return keptDays(i).filter { $0 >= start && $0 < i.today && !recorded.contains($0) }.sorted().map { .dayKept($0) }
    }

    static func saversHeld(_ i: LoopInputs) -> Int {
        let earned = i.ledger.filter { if case .saverEarned = $0 { return true } else { return false } }.count
        let used = i.ledger.filter { if case .saverUsed = $0 { return true } else { return false } }.count
        return max(0, earned - used)
    }

    /// A milestone to celebrate today, once.
    static func milestoneEvent(_ i: LoopInputs) -> LoopEvent? {
        guard isKept(i.today, i) else { return nil }
        let n = streak(i)
        guard milestones.contains(n) else { return nil }
        let event = LoopEvent.milestone(i.today, n)
        return i.ledger.contains(event) ? nil : event
    }

    private enum SaverMark: Hashable {
        case earned(DayKey), used(DayKey)
        init?(_ e: LoopEvent) {
            switch e {
            case let .saverEarned(d): self = .earned(d)
            case let .saverUsed(d): self = .used(d)
            default: return nil
            }
        }
    }
}
