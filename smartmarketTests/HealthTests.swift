import XCTest
import HealthKit
@testable import smartmarket

/// Apple Health sync rules, checked without HealthKit access or entitlements.
@MainActor
final class HealthTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    // MARK: Diff

    func testNewEntriesInTheWindowAreAdded() {
        let plan = HealthSync.plan(current: ["a": daysAgo(1), "b": daysAgo(2)],
                                   written: ["a": daysAgo(1)], now: now)
        XCTAssertEqual(plan.add, ["b"])
        XCTAssertTrue(plan.remove.isEmpty)
        XCTAssertEqual(Set(plan.keep.keys), ["a"])
    }

    func testDeletedEntriesAreRemoved() {
        let plan = HealthSync.plan(current: ["a": daysAgo(1)],
                                   written: ["a": daysAgo(1), "gone": daysAgo(3)], now: now)
        XCTAssertEqual(plan.remove, ["gone"])
        XCTAssertTrue(plan.add.isEmpty)
        XCTAssertEqual(Set(plan.keep.keys), ["a"])
    }

    func testNothingChangesWhenAlreadyInSync() {
        let both = ["a": daysAgo(1), "b": daysAgo(0.1)]
        let plan = HealthSync.plan(current: both, written: both, now: now)
        XCTAssertTrue(plan.add.isEmpty)
        XCTAssertTrue(plan.remove.isEmpty)
        XCTAssertEqual(plan.keep, both)
    }

    func testOldEntriesAreNeitherWrittenNorRemoved() {
        // An old entry missing from Health is left alone, and an old written
        // entry that the log pruned stays in Health but is no longer tracked.
        let plan = HealthSync.plan(current: ["old": daysAgo(10)],
                                   written: ["pruned": daysAgo(9)], now: now)
        XCTAssertTrue(plan.add.isEmpty)
        XCTAssertTrue(plan.remove.isEmpty)
        XCTAssertTrue(plan.keep.isEmpty)
    }

    func testFirstSyncWritesTheLastSevenDaysOnly() {
        let plan = HealthSync.plan(current: ["today": daysAgo(0), "week": daysAgo(6.9), "older": daysAgo(7.1)],
                                   written: [:], now: now)
        XCTAssertEqual(plan.add, ["today", "week"])
    }

    // MARK: Food values

    func testFoodEntryMapsToEnergyAndMacros() {
        let entry = FoodLogEntry(id: "entry-1", name: "Oat porridge", slot: .breakfast, servingG: 250,
                                 calories: 320, proteinG: 11.5, carbsG: 54.2, fatG: 6.1, loggedAt: now)
        let values = HealthSync.foodValues(for: entry)
        XCTAssertEqual(values, HealthSync.FoodValues(syncID: "entry-1", name: "Oat porridge", date: now,
                                                     kcal: 320, proteinG: 11.5, carbsG: 54.2, fatG: 6.1))
    }

    func testBadNumbersNeverReachHealth() {
        let entry = FoodLogEntry(id: "x", name: "  ", slot: .snack, servingG: 10,
                                 calories: -5, proteinG: .nan, carbsG: -1, fatG: .infinity, loggedAt: now)
        let values = HealthSync.foodValues(for: entry)
        XCTAssertEqual(values.name, "Food")
        XCTAssertEqual(values.kcal, 0)
        XCTAssertEqual(values.proteinG, 0)
        XCTAssertEqual(values.carbsG, 0)
        XCTAssertEqual(values.fatG, 0)
    }

    // MARK: Workouts

    func testExerciseKindMapsToHealthActivityType() {
        XCTAssertEqual(HealthSync.activityType(for: .gym), .traditionalStrengthTraining)
        XCTAssertEqual(HealthSync.activityType(for: .cardio), .mixedCardio)
        XCTAssertEqual(HealthSync.activityType(for: .home), .functionalStrengthTraining)
        XCTAssertEqual(HealthSync.activityType(for: .mobility), .flexibility)
    }

    private func tracked(minutes planned: Int = 45, calories: Int = 300, trainedMinutes: Double?) -> CompletedWorkout {
        let start = trainedMinutes.map { now.addingTimeInterval(-$0 * 60) }
        return CompletedWorkout(title: "Legs", kind: .gym, minutes: planned, calories: calories, date: now,
                                trackedStart: start, trackedEnd: start == nil ? nil : now)
    }

    func testOnlyTrackedWorkoutsAreWritten() {
        let markedDone = tracked(trainedMinutes: nil)
        let session = tracked(trainedMinutes: 30)
        XCTAssertNil(HealthSync.interval(for: markedDone), "Mark as done: not written to Health")
        XCTAssertFalse(HealthSync.isTracked(markedDone))
        XCTAssertNil(HealthSync.trackedEnergyKcal(for: markedDone))
        XCTAssertEqual(Set(HealthSync.trackedWorkouts([markedDone, session]).keys), [session.id.uuidString])
    }

    func testTrackedWorkoutUsesItsRealTimes() throws {
        let session = tracked(trainedMinutes: 32)
        let interval = try XCTUnwrap(HealthSync.interval(for: session))
        XCTAssertEqual(interval.start, now.addingTimeInterval(-32 * 60))
        XCTAssertEqual(interval.end, now)

        // Finished the moment it started: still a valid (1 s) workout.
        let instant = CompletedWorkout(title: "Stretch", kind: .mobility, minutes: 0, calories: 0, date: now,
                                       trackedStart: now, trackedEnd: now)
        XCTAssertEqual(HealthSync.interval(for: instant)?.duration, 1)
    }

    func testTrackedEnergyScalesWithMinutesTrainedAndIsCapped() {
        XCTAssertEqual(HealthSync.trackedEnergyKcal(for: tracked(trainedMinutes: 45)), 300, "as planned")
        XCTAssertEqual(HealthSync.trackedEnergyKcal(for: tracked(trainedMinutes: 15)), 100, "a third of the time")
        XCTAssertEqual(HealthSync.trackedEnergyKcal(for: tracked(trainedMinutes: 90)), 450, "capped at 1.5×")
        XCTAssertNil(HealthSync.trackedEnergyKcal(for: tracked(calories: 0, trainedMinutes: 30)), "no estimate, nothing written")
        XCTAssertEqual(HealthSync.trackedEnergyKcal(for: tracked(minutes: 0, calories: 50, trainedMinutes: 1)), 50,
                       "a zero-minute plan counts as one minute")
    }

    // MARK: Weight suggestion

    func testSuggestsNewerDifferentWeight() {
        XCTAssertEqual(HealthSync.weightSuggestion(healthKg: 72.43, measuredAt: now, profileKg: 70,
                                                   profileEditedAt: daysAgo(1)), 72.4)
    }

    func testNoSuggestionForTheSameWeight() {
        XCTAssertNil(HealthSync.weightSuggestion(healthKg: 70.04, measuredAt: now, profileKg: 70,
                                                 profileEditedAt: nil))
    }

    func testSuggestsATenthOfAKiloDifference() {
        XCTAssertEqual(HealthSync.weightSuggestion(healthKg: 70.1, measuredAt: now, profileKg: 70,
                                                   profileEditedAt: nil), 70.1)
    }

    func testNoSuggestionWhenProfileWasEditedAfterTheReading() {
        XCTAssertNil(HealthSync.weightSuggestion(healthKg: 75, measuredAt: daysAgo(2), profileKg: 70,
                                                 profileEditedAt: daysAgo(1)))
    }

    func testNoSuggestionWithoutAReadingOrOutOfRange() {
        XCTAssertNil(HealthSync.weightSuggestion(healthKg: nil, measuredAt: nil, profileKg: 70, profileEditedAt: nil))
        XCTAssertNil(HealthSync.weightSuggestion(healthKg: 12, measuredAt: now, profileKg: 70, profileEditedAt: nil))
        XCTAssertNil(HealthSync.weightSuggestion(healthKg: .nan, measuredAt: now, profileKg: 70, profileEditedAt: nil))
    }

    // MARK: Activity card text

    func testActivityCardSpeaksBothNumbers() {
        let text = ActivityCard.accessibilityText(steps: 8_250.4, kcal: 312.6)
        XCTAssertTrue(text.contains("steps"))
        XCTAssertTrue(text.contains("313 active kilocalories"))
        XCTAssertEqual(ActivityCard.number(nil), "–")
    }
}
