import Foundation
import UIKit
import WidgetKit

/// Keeps the widgets' copy of today (`NourloSnapshot` in the App Group) in step
/// with the app: what's been eaten today, the goals Home shows, today's planned
/// meals and the streak. Reloads widget timelines only when the snapshot really
/// changed. Without the App Group (unsigned or fallback builds) it does nothing.
@MainActor
final class WidgetSync {
    static let shared = WidgetSync()

    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var started = false

    /// How long to wait for a burst of changes to settle before writing.
    static let debounce: Duration = .milliseconds(500)

    private init() {}

    /// Starts listening and writes a first snapshot. Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .foodLogDidChange, .mealPlanDidUpdate, .personalDataDidChange,
            UIApplication.didBecomeActiveNotification, .NSCalendarDayChanged, UIApplication.significantTimeChangeNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WidgetSync.shared.scheduleSync() }
            }
        }
        // Leaving the app: write at once, a pending pause might not get to run.
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                            queue: .main) { _ in
            MainActor.assumeIsolated {
                WidgetSync.shared.pending?.cancel()
                WidgetSync.shared.syncNow()
            }
        })
        observeStreak()
        syncNow()
    }

    /// Writes after a short pause, so several changes in a row cost one write.
    func scheduleSync() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self.syncNow()
        }
    }

    /// Writes the snapshot now; reloads the widgets if it changed.
    func syncNow(now: Date = Date()) {
        let snapshot = Self.liveSnapshot(now: now)
        if NourloSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The streak has no notification of its own: watch the loop store's state.
    private func observeStreak() {
        withObservationTracking {
            _ = DailyLoopStore.shared.state.streak
        } onChange: {
            Task { @MainActor in
                WidgetSync.shared.observeStreak()
                WidgetSync.shared.scheduleSync()
            }
        }
    }

    // MARK: - Building the snapshot

    /// Today's snapshot from the app's live data.
    static func liveSnapshot(now: Date = Date()) -> NourloSnapshot {
        // Before onboarding the profile holds placeholder numbers: no goal yet.
        let goal = AppState.shared.isOnboarded ? AppState.shared.userProfile.dailyCalorieGoal : 0
        let isKeto = Set<DietaryPreference>.load().contains(.keto)
        let weekly = AppState.shared.weeklyMealPlan
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return makeSnapshot(entries: FoodLogStore.shared.allEntries, now: now, calorieGoal: goal, isKeto: isKeto,
                            todayPlan: weekly.flatMap { MealPlan.from(weekly: $0, date: now) },
                            tomorrowPlan: weekly.flatMap { MealPlan.from(weekly: $0, date: tomorrow) },
                            streak: DailyLoopStore.shared.state.streak)
    }

    /// Pure: builds the snapshot from plain inputs. Only entries logged on `now`'s
    /// day count. Macro goals follow the calorie goal the same way Home does.
    static func makeSnapshot(entries: [FoodLogEntry], now: Date, calorieGoal: Int, isKeto: Bool,
                             todayPlan: MealPlan?, tomorrowPlan: MealPlan?, streak: Int,
                             calendar: Calendar = .current) -> NourloSnapshot {
        let today = entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: now) }
        let goal = max(calorieGoal, 0)
        let targets = goal > 0 ? BMRCalculator.macroTargets(calories: goal, isKeto: isKeto) : nil
        func grams(_ value: Double) -> Int { Int(value.rounded()) }
        return NourloSnapshot(
            // The day, not the moment: the snapshot only changes when what it shows does.
            date: calendar.startOfDay(for: now),
            caloriesEaten: today.reduce(0) { $0 + $1.calories },
            calorieGoal: goal,
            proteinG: grams(today.reduce(0) { $0 + $1.proteinG }), proteinGoalG: targets?.proteinG ?? 0,
            carbsG: grams(today.reduce(0) { $0 + $1.carbsG }), carbsGoalG: targets?.carbsG ?? 0,
            fatG: grams(today.reduce(0) { $0 + $1.fatG }), fatGoalG: targets?.fatG ?? 0,
            meals: meals(in: todayPlan),
            streakDays: max(streak, 0),
            nextDayMeals: tomorrowPlan.map { meals(in: $0) })
    }

    /// One row per meal slot that has food planned, in the day's order.
    static func meals(in plan: MealPlan?) -> [NourloSnapshot.Meal] {
        guard let plan else { return [] }
        return plan.allMeals.compactMap { meal in
            guard !meal.entries.isEmpty else { return nil }
            let name = meal.entries.map(\.foodName).joined(separator: ", ")
            return NourloSnapshot.Meal(slot: meal.title, name: name, kcal: meal.entries.reduce(0) { $0 + $1.calories })
        }
    }
}
