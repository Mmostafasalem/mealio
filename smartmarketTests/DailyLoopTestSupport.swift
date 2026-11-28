import Foundation
@testable import smartmarket

/// Shared fixtures for the daily-loop tests: a fixed calendar and builders.
enum LoopFixture {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        c.firstWeekday = 2
        return c
    }()

    /// Wednesday 2026-11-11 at the given hour/minute, plus `days` offset.
    static func date(_ days: Int = 0, hour: Int = 12, minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: days, to: base)!
    }

    static func day(_ days: Int = 0) -> DayKey { DayKey(date(days), calendar: calendar) }

    static func food(_ days: Int = 0, hour: Int = 12, minute: Int = 0, slot: MealSlot = .lunch,
                     kcal: Int = 500, protein: Double = 20, foodId: String? = "food-x", id: String = UUID().uuidString,
                     name: String = "Food") -> FoodLogEntry {
        FoodLogEntry(id: id, foodId: foodId, name: name, slot: slot, servingG: 100, calories: kcal,
                     proteinG: protein, carbsG: 50, fatG: 10, loggedAt: date(days, hour: hour, minute: minute))
    }

    static func workout(_ days: Int = 0, minutes: Int = 30) -> CompletedWorkout {
        CompletedWorkout(title: "Walk", kind: .cardio, minutes: minutes, calories: 120, date: date(days))
    }

    static func inputs(food: [FoodLogEntry] = [], stockIDs: Set<String> = [], workouts: [CompletedWorkout] = [],
                       calorieGoal: Int = 2000, proteinGoal: Int = 90, cartHasItems: Bool = false, hasStock: Bool = false,
                       ledger: [LoopEvent] = [], now: Date = date(0)) -> LoopInputs {
        LoopInputs(foodEntries: food, stockEntryIDs: stockIDs, workouts: workouts, calorieGoal: calorieGoal,
                   proteinGoal: proteinGoal, cartHasItems: cartHasItems, hasStock: hasStock, ledger: ledger,
                   now: now, calendar: calendar)
    }
}
