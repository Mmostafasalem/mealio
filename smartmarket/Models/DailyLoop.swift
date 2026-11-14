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
}

/// One dot in the Mon–Sun row. Past days that didn't count are just `.open`.
enum WeekDot: Equatable {
    case kept, saved, open, today(kept: Bool), future
}

enum DailyLoop {

    // MARK: Days

    static func keptDays(_ i: LoopInputs) -> Set<DayKey> {
        var days = Set(i.foodEntries.map { DayKey($0.loggedAt, calendar: i.calendar) })
        days.formUnion(i.workouts.map { DayKey($0.date, calendar: i.calendar) })
        for case let .budgetCheckIn(d) in i.ledger { days.insert(d) }
        return days
    }

    static func savedDays(_ i: LoopInputs) -> Set<DayKey> {
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
        let weekday = i.calendar.component(.weekday, from: i.now)
        let offset = (weekday - i.calendar.firstWeekday + 7) % 7
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
        if i.ledger.contains(.perfectDay(today)) { return .love }
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
