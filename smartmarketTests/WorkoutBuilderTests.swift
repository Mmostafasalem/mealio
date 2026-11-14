import XCTest
@testable import smartmarket

@MainActor
final class WorkoutBuilderTests: XCTestCase {

    func testEveryKindAndLevelBuildsAUsableSession() {
        for kind in ExerciseKind.allCases {
            for level in ExerciseLevel.allCases {
                for minutes in [10, 30, 90] {
                    let workout = WorkoutBuilder.build(kind: kind, level: level, minutes: minutes,
                                                       focus: .fullBody, goal: .maintain)
                    XCTAssertEqual(workout.kind, kind)
                    XCTAssertEqual(workout.durationMinutes, minutes)
                    XCTAssertFalse(workout.isFromAI)
                    XCTAssertFalse(workout.title.isEmpty)
                    XCTAssertFalse(workout.safetyNote.isEmpty)
                    XCTAssertGreaterThanOrEqual(workout.exercises.count, 2, "\(kind) \(level) \(minutes)")
                    for exercise in workout.exercises {
                        XCTAssertFalse(exercise.prescription.isEmpty, exercise.name)
                    }
                }
            }
        }
    }

    func testBeginnersOnlyGetBeginnerExercises() {
        let beginner = Set(Exercise.catalog.filter { $0.level == .beginner }.map(\.name))
        for kind in [ExerciseKind.gym, .home] {
            let workout = WorkoutBuilder.build(kind: kind, level: .beginner, minutes: 60, focus: .fullBody, goal: .lose)
            for exercise in workout.exercises {
                XCTAssertTrue(beginner.contains(exercise.name), "\(exercise.name) is not a beginner exercise")
            }
        }
    }

    func testFocusPicksMatchingExercisesPlusCore() {
        let workout = WorkoutBuilder.build(kind: .gym, level: .advanced, minutes: 45, focus: .upper, goal: .gain)
        let byName = Dictionary(uniqueKeysWithValues: Exercise.catalog.map { ($0.name, $0) })
        XCTAssertTrue(workout.exercises.contains { byName[$0.name]?.focus == .upper })
        XCTAssertFalse(workout.exercises.contains { byName[$0.name]?.focus == .lower })
    }

    func testCardioBlocksAddUpToTheRequestedTime() {
        for level in ExerciseLevel.allCases {
            let workout = WorkoutBuilder.build(kind: .cardio, level: level, minutes: 40, focus: .fullBody, goal: .lose)
            let total = workout.exercises.reduce(0) { $0 + $1.minutes }
            XCTAssertLessThanOrEqual(abs(total - 40), 3, "\(level): \(total) min")
        }
    }

    func testCalorieEstimateScalesWithWeightAndTime() {
        let short = WorkoutBuilder.build(kind: .cardio, level: .beginner, minutes: 20, focus: .fullBody, goal: .maintain)
        let long = WorkoutBuilder.build(kind: .cardio, level: .beginner, minutes: 60, focus: .fullBody, goal: .maintain)
        XCTAssertEqual(long.estimatedCalories(weightKg: 70), short.estimatedCalories(weightKg: 70) * 3, accuracy: 2)
        XCTAssertGreaterThan(long.estimatedCalories(weightKg: 90), long.estimatedCalories(weightKg: 60))
    }

    func testServiceReplyDecodesIntoAnAIWorkout() throws {
        let json = #"{"title":"Push day","summary":"s","kind":"gym","level":"intermediate","durationMinutes":45,"warmup":"w","cooldown":"c","exercises":[{"name":"Bench press","sets":3,"reps":"8","minutes":0,"restSeconds":90,"note":"Elbows 45 degrees"}],"safetyNote":"Stop if it hurts."}"#
        let workout = try XCTUnwrap(JSONDecoder().decode(WorkoutResponse.self, from: Data(json.utf8)).workout(source: "ai"))
        XCTAssertTrue(workout.isFromAI)
        XCTAssertEqual(workout.kind, .gym)
        XCTAssertEqual(workout.exercises.first?.prescription, "3 × 8")
    }

    func testCatalogueIdsAreUnique() {
        XCTAssertEqual(Set(Exercise.catalog.map(\.id)).count, Exercise.catalog.count)
        XCTAssertEqual(Set(Exercise.catalog.map(\.name)).count, Exercise.catalog.count)
    }
}

@MainActor
final class ExerciseMotionTests: XCTestCase {
    func testEveryCatalogueExerciseHasADemo() {
        for exercise in Exercise.catalog {
            XCTAssertNotNil(exercise.motion, "\(exercise.id) has no movement demo")
        }
    }

    func testFreeTextNamesMapToSensibleMotions() {
        XCTAssertEqual(ExerciseMotion.matching(name: "Barbell Back Squat"), .squat)
        XCTAssertEqual(ExerciseMotion.matching(name: "Incline dumbbell bench press"), .benchPress)
        XCTAssertEqual(ExerciseMotion.matching(name: "Bent-over row"), .bentRow)
        XCTAssertEqual(ExerciseMotion.matching(name: "Treadmill jog"), .run)
        XCTAssertEqual(ExerciseMotion.matching(name: "Push-up"), .pushUp)
        XCTAssertNil(ExerciseMotion.matching(name: "Turkish get-up"), "Unknown movements show no demo rather than a wrong one")
    }

    func testPosesStayInsideTheFrame() {
        for motion in ExerciseMotion.allCases {
            for pose in [motion.poses.0, motion.poses.1] {
                for point in [pose.head, pose.shoulder, pose.hip, pose.elbowF, pose.handF, pose.elbowB, pose.handB,
                              pose.kneeF, pose.footF, pose.kneeB, pose.footB] {
                    XCTAssertTrue((0.0...1.0).contains(point.x) && (-0.05...0.95).contains(point.y), "\(motion) \(point)")
                }
            }
        }
    }
}
