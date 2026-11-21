import Foundation

// MARK: - The person's week
//
// The person chooses the day their week starts (Profile › Your week; Monday unless
// changed). The weekly budget, "this week" in Train and the weekly reset follow it.
// When a new week starts, the app asks once whether to empty the cart and My Stock
// for a fresh start; nothing is cleared without that yes.

@MainActor
enum WeeklyReset {
    static let startDayKey = "weekStartDay_v1"
    static let askKey = "weeklyResetAsk_v1"
    static let handledKey = "weeklyResetHandledWeek_v1"

    /// 1 Sunday … 7 Saturday (Calendar weekday numbers). Monday unless changed.
    static var startDay: Int {
        get { let v = UserDefaults.standard.integer(forKey: startDayKey); return (1...7).contains(v) ? v : 2 }
        set {
            UserDefaults.standard.set(newValue, forKey: startDayKey)
            startDayChanged()
        }
    }

    /// A different start day isn't a new week: the current week, counted the new way,
    /// counts as answered, so moving Monday to Wednesday doesn't ask mid-week. Call it
    /// whenever the start day is written (Profile writes the key directly).
    static func startDayChanged(now: Date = Date()) {
        if UserDefaults.standard.object(forKey: handledKey) != nil {
            UserDefaults.standard.set(weekStart(of: now), forKey: handledKey)
        }
    }

    /// Whether to ask about a fresh start each week (on unless turned off).
    static var asks: Bool {
        get { UserDefaults.standard.object(forKey: askKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: askKey) }
    }

    /// The calendar whose weeks start on the person's day.
    static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = startDay
        return c
    }

    static func weekStart(of date: Date, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? Self.calendar
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// True when a new week has started since the last answer and there's something to clear.
    /// The very first time, the current week is just noted (nothing is asked on day one).
    static func isDue(now: Date = Date(), hasSomething: Bool, defaults: UserDefaults = .standard,
                      calendar: Calendar? = nil) -> Bool {
        let week = weekStart(of: now, calendar: calendar)
        guard let handled = defaults.object(forKey: handledKey) as? Date else {
            defaults.set(week, forKey: handledKey)
            return false
        }
        // Weeks start seven days apart; a time-zone change moves the start by hours, not days.
        guard week.timeIntervalSince(handled) > 2 * 86_400 else { return false }
        guard asks, hasSomething else {
            defaults.set(week, forKey: handledKey)
            return false
        }
        return true
    }

    enum Choice { case cartAndStock, cartOnly, keep }

    /// Records the answer for this week and clears what was chosen.
    static func answer(_ choice: Choice, now: Date = Date(), cart: ShoppingCartService? = nil, stock: StockStore? = nil,
                       defaults: UserDefaults = .standard) {
        let cart = cart ?? .shared, stock = stock ?? .shared
        switch choice {
        case .cartAndStock:
            cart.clear(keepStock: true)
            stock.clearItems()
            defaults.removeObject(forKey: "cartStockLinks_v1")
        case .cartOnly:
            cart.clear(keepStock: true)
            defaults.removeObject(forKey: "cartStockLinks_v1")
        case .keep:
            break
        }
        defaults.set(weekStart(of: now), forKey: handledKey)
    }

    static let dayNames: [(day: Int, name: String)] = {
        let symbols = Calendar.current.weekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].map { ($0, symbols[$0 - 1]) }
    }()
}
