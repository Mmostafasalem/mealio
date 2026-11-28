import Foundation
import UserNotifications

/// The one evening nudge: "your streak is about to end". Only when a streak
/// is at risk, at most one a day, only with Reminders on (see ReminderStore).
enum StreakNudge {
    static let prefix = "streak_"
    static let hour = 20

    struct Item: Equatable {
        let id: String
        let fire: Date
        let body: String
    }

    /// Nudges for the next three evenings, starting today if today doesn't
    /// count yet and 20:00 hasn't passed. `streak` already counts today when
    /// today is kept. A held saver covers a missed today, so tomorrow's note
    /// still speaks of keeping the streak.
    static func plan(now: Date, todayKept: Bool, streak: Int, calendar: Calendar, saversHeld: Int = 0) -> [Item] {
        guard streak >= 1 else { return [] }
        let today = DayKey(now, calendar: calendar)
        var out: [Item] = []
        for offset in 0..<3 {
            let day = today.adding(days: offset, calendar: calendar)
            guard let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.date(in: calendar)),
                  fire > now else { continue }
            let body: String
            switch offset {
            case 0:
                guard !todayKept else { continue }
                body = "Nourlo's getting sleepy… one quest keeps your \(streak)-day streak."
            case 1:
                body = todayKept || saversHeld > 0 ? "Nourlo's getting sleepy… one quest keeps your \(streak)-day streak."
                                                   : "Nourlo misses you. Log one thing to start a new streak."
            default:
                body = "Nourlo saved you a spot. One quest is all it takes."
            }
            out.append(Item(id: prefix + day.description, fire: fire, body: body))
        }
        return out
    }

    /// Every id a plan from around `now` could have used (removing unknown ids is harmless).
    static func candidateIDs(now: Date, calendar: Calendar) -> [String] {
        let today = DayKey(now, calendar: calendar)
        return (-1...3).map { prefix + today.adding(days: $0, calendar: calendar).description }
    }

    static func request(_ item: Item, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Nourlo"
        content.body = item.body
        content.sound = .default
        content.userInfo = ["streakNudge": true]
        let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fire)
        return UNNotificationRequest(identifier: item.id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
    }
}
