import XCTest

/// Builds a gym workout on the phone, does it in workout mode set by set, and finishes it.
@MainActor
final class WorkoutModeUITests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testWorkoutModeLogsSetsAndFinishes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-workoutModeDraft_v1", "", "-completedWorkouts_v1", "", "-currentProgram_v1", ""]
        app.launch()
        app.tab("Train").tap()
        let gym = app.buttons["train.kind.gym"]
        XCTAssertTrue(gym.waitForExistence(timeout: 10))
        gym.tap()
        let generate = app.buttons["train.generate"]
        // Train is long (programmes first); scroll until Generate sits clear of the floating tab bar.
        let barTop = app.windows.firstMatch.frame.maxY * 0.82
        for _ in 0..<8 where !generate.isHittable || generate.frame.maxY > barTop { app.swipeUp() }
        generate.tap()
        let start = app.buttons["workout.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        // A workout left running by an earlier test: start this one instead.
        let replace = app.buttons["Start this one instead"]
        if replace.waitForExistence(timeout: 2) { replace.tap() }

        let complete = app.buttons["workoutMode.completeSet"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        shot("workout-mode")
        // A tap while the start prompt is still closing can be lost; tap until the weight box opens.
        let field = app.alerts.textFields.firstMatch
        for _ in 0..<3 where !field.exists {
            app.buttons["workoutMode.weight.1"].tap()
            if field.waitForExistence(timeout: 4) { break }
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("40")
        app.alerts.buttons["Set"].tap()
        complete.tap()
        XCTAssertTrue(app.buttons["workoutMode.skipRest"].waitForExistence(timeout: 5))
        shot("workout-mode-rest")
        app.buttons["workoutMode.skipRest"].tap()

        app.buttons["workoutMode.close"].tap()
        let save = app.buttons["Finish and save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["workoutSummary.done"].waitForExistence(timeout: 10))
        shot("workout-summary")
        app.buttons["workoutSummary.done"].tap()
        XCTAssertTrue(app.buttons["workout.done"].waitForExistence(timeout: 10))

        // Progress lists the workout and the exercise.
        app.buttons["BackButton"].firstMatch.tap()
        let progress = app.buttons["train.progress"]
        for _ in 0..<16 where !progress.isHittable { app.swipeUp() }
        progress.tap()
        XCTAssertTrue(app.staticTexts["Weight lifted per week"].waitForExistence(timeout: 10))
        shot("progress")
        let exercise = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progress.exercise.'")).firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        exercise.tap()
        XCTAssertTrue(app.staticTexts["Every time"].waitForExistence(timeout: 5))
        shot("exercise-progress")
    }

    func testBuildingOwnWorkoutWithANewExercise() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-workoutModeDraft_v1", "", "-savedWorkouts_v1", "", "-customExercises_v1", ""]
        app.launch()
        app.tab("Train").tap()
        let create = app.buttons["train.createWorkout"]
        for _ in 0..<8 where !create.isHittable { app.swipeUp() }
        create.tap()
        let title = app.textFields["builder.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Landmine session")
        app.buttons["builder.addExercise"].tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Bench press\n")
        let bench = app.buttons["picker.exercise.Bench press"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()
        shot("exercise-picker")
        app.buttons["picker.newExercise"].tap()
        let name = app.textFields["newExercise.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Landmine press")
        app.buttons["newExercise.create"].tap()
        let add = app.buttons["picker.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        XCTAssertTrue(app.staticTexts["Landmine press"].waitForExistence(timeout: 5))
        shot("workout-builder")
        app.buttons["builder.save"].tap()
        let mine = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Landmine session'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        mine.tap()
        // The workout opens on its page with Start, or straight into workout mode when it can resume.
        let start = app.buttons["workout.start"]
        let complete = app.buttons["workoutMode.completeSet"]
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline && !start.exists && !complete.exists { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        if start.exists {
            start.tap()
            let replace = app.buttons["Start this one instead"]
            if replace.waitForExistence(timeout: 2) { replace.tap() }
        }
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        shot("custom-workout-mode")
    }
}
