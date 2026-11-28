import XCTest

/// Screenshots of the floating quick actions menu (opt-in: TEST_RUNNER_NOURLO_SHOTS=1).
final class QuickActionsMenuShotTests: XCTestCase {
    func testMenuScreens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOURLO_SHOTS"] == "1", "screenshots only")
        for (theme, style) in [("pink", "light"), ("pink", "dark"), ("ocean", "light")] {
            let app = XCUIApplication()
            app.launchArguments = ["-hasSeenWelcome", "YES", "-hasCompletedOnboarding", "YES", "-NourloUITesting", "YES",
                                   "-aiSharingConsent_v1", "NO", "-onlineAIOffered_v1", "YES", "-appTheme_v1", theme,
                                   "-appearanceOverride_v1", style]
            app.launch()
            let button = app.buttons["navigation.quickActions"]
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            button.tap()
            XCTAssertTrue(app.buttons["quickActions.done"].waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "menu-\(theme)-\(style)"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["quickActions.done"].tap()
            app.terminate()
        }
    }
}
