import XCTest
@testable import smartmarket

final class StreakSaverTests: XCTestCase {
    private typealias F = LoopFixture

    /// Kept days at the given offsets, loop started `start` days ago.
    private func inputs(kept: [Int], start: Int, ledger extra: [LoopEvent] = []) -> LoopInputs {
        F.inputs(food: kept.map { F.food($0) }, ledger: [.loopStarted(F.day(start))] + extra)
    }

    /// Runs saver events to a fixed point, like the store does on every refresh.
    private func settle(_ i: LoopInputs) -> LoopInputs {
        var i = i
        i.ledger += DailyLoop.saverEvents(i)
        return i
    }

    func testEarnsOneSaverPerSevenKeptDays() {
        let i = settle(inputs(kept: Array(-7 ... -1), start: -7))
        XCTAssertEqual(DailyLoop.saversHeld(i), 1)
        XCTAssertTrue(i.ledger.contains(.saverEarned(F.day(-1))))
    }

    func testHoldsAtMostTwo() {
        let i = settle(inputs(kept: Array(-21 ... -1), start: -21))
        XCTAssertEqual(DailyLoop.saversHeld(i), 2)
    }

    func testSaverFillsMissedDay() {
        // 7 kept days earn a saver; the next day is missed; then kept again.
        let i = settle(inputs(kept: Array(-10 ... -4) + [-2, -1], start: -10))
        XCTAssertTrue(i.ledger.contains(.saverUsed(F.day(-3))))
        XCTAssertEqual(DailyLoop.saversHeld(i), 0)
        XCTAssertEqual(DailyLoop.streak(i), 9)
    }

    func testFiveMissedDaysWithTwoSaversSavesFirstTwo() {
        let i = settle(inputs(kept: Array(-19 ... -6), start: -19))
        XCTAssertTrue(i.ledger.contains(.saverUsed(F.day(-5))))
        XCTAssertTrue(i.ledger.contains(.saverUsed(F.day(-4))))
        XCTAssertFalse(i.ledger.contains(.saverUsed(F.day(-3))))
        XCTAssertEqual(DailyLoop.saversHeld(i), 0)
        XCTAssertEqual(DailyLoop.streak(i), 0)
    }

    func testNoSaversBeforeLoopStarted() {
        let i = settle(inputs(kept: Array(-30 ... -1), start: -2))
        XCTAssertEqual(DailyLoop.saversHeld(i), 0)
        XCTAssertEqual(DailyLoop.streak(i), 30)
    }

    func testSaverEventsAreIdempotent() {
        let i = settle(inputs(kept: Array(-10 ... -4) + [-2, -1], start: -10))
        XCTAssertEqual(DailyLoop.saverEvents(i), [])
    }

    func testMilestoneOnceAtSeven() {
        var i = F.inputs(food: (0...6).map { F.food(-$0) })
        XCTAssertEqual(DailyLoop.milestoneEvent(i), .milestone(F.day(), 7))
        i.ledger.append(.milestone(F.day(), 7))
        XCTAssertNil(DailyLoop.milestoneEvent(i))
    }

    func testNoMilestoneWhenTodayNotKept() {
        XCTAssertNil(DailyLoop.milestoneEvent(F.inputs(food: (1...7).map { F.food(-$0) })))
    }
}
