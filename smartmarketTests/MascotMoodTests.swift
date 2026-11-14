import XCTest
@testable import smartmarket

/// The bowl's moods drive real face parts and extras. Each test settles a rig in
/// one mood and checks the pose the drawing receives.
@MainActor
final class MascotMoodTests: XCTestCase {
    private func settled(_ mood: MascotMood, reduceMotion: Bool = false) -> MascotPose {
        let rig = MascotRig()
        rig.reduceMotion = reduceMotion
        rig.set(mood: mood)
        rig.setActive(true)
        rig.stop()
        rig.simulate(seconds: 1.5)
        return rig.pose
    }

    func testCheekyWinksAndSmirks() {
        let p = settled(.cheeky)
        XCTAssertGreaterThan(p.wink, 0.9)
        XCTAssertGreaterThan(p.smirk, 0.9)
        XCTAssertLessThan(p.smile, 0.1)
    }

    func testWorriedShowsBrowsAndSweat() {
        let p = settled(.worried)
        XCTAssertGreaterThan(p.worry, 0.9)
        XCTAssertGreaterThan(p.sweat, 0.9)
        XCTAssertGreaterThan(p.wavy, 0.9)
        XCTAssertGreaterThan(p.wide, 0.9)
    }

    func testLoveHasHeartEyes() {
        let p = settled(.love)
        XCTAssertGreaterThan(p.hearts, 0.9)
        XCTAssertGreaterThan(p.floatHearts, 0.9)
    }

    func testSleepyClosesEyesWithZzz() {
        let p = settled(.sleepy)
        XCTAssertGreaterThan(p.asleep, 0.9)
        XCTAssertGreaterThan(p.zzz, 0.9)
        XCTAssertLessThan(p.sleepy, 0.1)
    }

    func testCelebrateConfettiAndThinkingDots() {
        XCTAssertGreaterThan(settled(.celebrate).confetti, 0.9)
        XCTAssertGreaterThan(settled(.thinking).thought, 0.9)
    }

    func testHelpGlancesTowardRaisedArm() {
        XCTAssertGreaterThan(settled(.help).lookX, 0.4)
    }

    func testIdleHasNoExtras() {
        let p = settled(.idle)
        for (name, v) in [("wink", p.wink), ("smirk", p.smirk), ("hearts", p.hearts), ("asleep", p.asleep),
                          ("worry", p.worry), ("confetti", p.confetti), ("zzz", p.zzz), ("thought", p.thought),
                          ("sweat", p.sweat), ("floatHearts", p.floatHearts)] {
            XCTAssertLessThan(v, 0.05, name)
        }
    }

    func testReduceMotionStillShowsFaces() {
        XCTAssertGreaterThan(settled(.cheeky, reduceMotion: true).wink, 0.9)
        XCTAssertGreaterThan(settled(.love, reduceMotion: true).hearts, 0.9)
        XCTAssertGreaterThan(settled(.sleepy, reduceMotion: true).zzz, 0.9)
    }

    func testConfettiFadesWhenMoodChanges() {
        let rig = MascotRig()
        rig.reduceMotion = false
        rig.set(mood: .celebrate)
        rig.setActive(true)
        rig.stop()
        rig.simulate(seconds: 1.5)
        XCTAssertGreaterThan(rig.pose.confetti, 0.9)
        rig.set(mood: .idle)
        rig.stop()
        rig.simulate(seconds: 1.5)
        XCTAssertLessThan(rig.pose.confetti, 0.05)
    }

    /// A hop's landing flashes a face; it must not wipe the mood's extras.
    func testExtrasSurviveHopLanding() {
        for (mood, value) in [(MascotMood.celebrate, \MascotPose.confetti), (.love, \MascotPose.hearts), (.love, \MascotPose.floatHearts)] {
            let rig = MascotRig()
            rig.reduceMotion = false
            rig.setActive(true)
            rig.set(mood: .idle)
            rig.set(mood: mood) // entry hop
            rig.stop()
            var risen = false
            for frame in 0..<180 {
                rig.simulate(seconds: 1.0 / 60)
                let v = rig.pose[keyPath: value]
                if v > 0.9 { risen = true }
                if risen { XCTAssertGreaterThan(v, 0.8, "\(mood) \(value) dropped at frame \(frame)") }
                if risen, v <= 0.8 { break }
            }
            XCTAssertTrue(risen, "\(mood) \(value) never appeared")
            rig.setActive(false)
        }
    }

    /// Calm moods must let the clock rest after their entry life (battery, UI automation).
    func testCalmMoodsRestAfterEntry() {
        for mood in [MascotMood.sleepy, .love, .worried] {
            let rig = MascotRig()
            rig.reduceMotion = false
            rig.setActive(true)
            rig.set(mood: .idle)
            rig.set(mood: mood)
            rig.stop()
            rig.simulate(seconds: 10)
            XCTAssertFalse(rig.isLively, "\(mood)")
            rig.setActive(false)
        }
    }
}
