import XCTest

/// Starts a programme from the Train tab, opens its next day, and browses exercises by muscle.
@MainActor
final class ProgramUITests: XCTestCase {
    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
        // Also written out for review when a folder is given.
        if let folder = ProcessInfo.processInfo.environment["NOURLO_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
    }

    func testFollowingAProgramme() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-workoutModeDraft_v1", "", "-currentProgram_v1", "",
                               "-trainExercisesByMuscle_v1", "YES"]
        app.launch()
        app.tab("Train").tap()

        let card = app.buttons["program.ppl-3"]
        XCTAssertTrue(card.waitForExistence(timeout: 40))
        shot("train-programmes")
        card.tap()
        let start = app.buttons["program.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        shot("programme-detail")
        start.tap()
        XCTAssertTrue(app.buttons["program.startNext"].waitForExistence(timeout: 30))
        shot("programme-following")
        app.buttons["BackButton"].firstMatch.tap()

        // Back on Train: the current programme and its next day.
        let next = app.buttons["train.program.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        let current = app.buttons["train.program.current"]
        XCTAssertTrue(current.waitForExistence(timeout: 20))
        XCTAssertTrue(current.label.contains("Next: Day 1 · Push"), current.label)
        shot("train-current-programme")
        next.tap()
        XCTAssertTrue(app.buttons["workout.start"].waitForExistence(timeout: 30))
        shot("programme-day-workout")
    }

    func testBrowsingExercisesByMuscle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-aiSharingConsent_v1", "NO",
                               "-NourloUITesting", "YES", "-workoutModeDraft_v1", "", "-trainExercisesByMuscle_v1", "YES"]
        app.launch()
        app.tab("Train").tap()
        XCTAssertTrue(app.buttons["program.ppl-3"].waitForExistence(timeout: 40))
        let chest = app.buttons["stackPanel.row.muscle.chest"]
        for _ in 0..<10 where !chest.isHittable { app.swipeUp() }
        XCTAssertTrue(chest.isHittable)
        shot("exercises-by-muscle")
        chest.tap()
        XCTAssertTrue(app.buttons["stackPanel.row.chest.bench-press"].waitForExistence(timeout: 20))
        shot("exercises-chest")
    }
}
