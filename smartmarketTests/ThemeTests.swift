import SwiftUI
import XCTest
@testable import smartmarket

/// Colour themes (Profile › Appearance): contrast, persistence and the pink default.
@MainActor
final class ThemeTests: XCTestCase {

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "ThemeTests." + name
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: Contrast

    func testLuminanceMatchesWCAGReferencePoints() {
        XCTAssertEqual(ThemeContrast.luminance(0xFFFFFF), 1, accuracy: 1e-9)
        XCTAssertEqual(ThemeContrast.luminance(0x000000), 0, accuracy: 1e-9)
        XCTAssertEqual(ThemeContrast.ratio(0xFFFFFF, 0x000000), 21, accuracy: 1e-6)
        // #777777 on white is the textbook 4.48:1.
        XCTAssertEqual(ThemeContrast.ratio(0x777777, 0xFFFFFF), 4.48, accuracy: 0.01)
    }

    /// Button labels sit on the accent: normal-size text needs 4.5:1 in both modes.
    func testOnAccentTextOnAccentPassesAAInEveryTheme() {
        for theme in AppTheme.allCases {
            let p = theme.palette
            for (accent, ink, mode) in [(p.accent.light, p.onAccent.light, "light"), (p.accent.dark, p.onAccent.dark, "dark")] {
                let ratio = ThemeContrast.ratio(accent, ink)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme.name) \(mode): on-accent \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    /// Ticks, checkmarks and the widget's Log food button draw on-accent ink on the
    /// progress colour too (icons and bold labels: 3:1 is the floor; we hold 4.5:1).
    func testOnAccentOnProgressPassesInEveryTheme() {
        for theme in AppTheme.allCases {
            let p = theme.palette
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.progress.light, p.onAccent.light), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.progress.dark, p.onAccent.dark), 4.5, theme.name)
        }
    }

    /// Ink text on the selection tint and on the canvas stays readable.
    func testInkOnTintsPassesAA() {
        for theme in AppTheme.allCases {
            let p = theme.palette
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.tint.light, 0x111111), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.tint.dark, 0xF4ECE9), 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.canvas.light, 0x111111), 4.5, theme.name)
            // The pale tint carries text on Rhino (toasts, the welcome title).
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.soft.light, 0x1C1C1E), 4.5, theme.name)
        }
    }

    /// Rings and bars are graphics: 3:1 against the track (WCAG 1.4.11).
    func testProgressStandsOutFromItsTrack() {
        for theme in AppTheme.allCases {
            let p = theme.palette
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.progress.light, p.fill.light), 1.9, theme.name)
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(p.progress.dark, p.fill.dark), 3, theme.name)
        }
    }

    /// No macro ring wears the accent's colour.
    func testMacroRingsNeverRepeatTheAccent() {
        for theme in AppTheme.allCases {
            let p = theme.palette
            for ring in [p.ringProtein, p.ringCarbs, p.ringFat] {
                XCTAssertNotEqual(ring.light, p.progress.light, theme.name)
                XCTAssertGreaterThan(hueDistance(ring.light, p.progress.light), 25, "\(theme.name) ring too close to the accent")
            }
        }
    }

    private func hueDistance(_ a: UInt32, _ b: UInt32) -> Double {
        func hue(_ v: UInt32) -> Double {
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
            UIColor(rgb: v).getHue(&h, saturation: &s, brightness: &br, alpha: &al)
            return s < 0.12 ? -1 : Double(h) * 360 // greys have no hue
        }
        let ha = hue(a), hb = hue(b)
        if ha < 0 || hb < 0 { return 360 }
        let d = abs(ha - hb)
        return min(d, 360 - d)
    }

    // MARK: The default and persistence

    func testPinkIsTheDefaultForExistingUsers() {
        let d = freshDefaults()
        XCTAssertEqual(AppThemeStorage.load(from: d), .pink)
        XCTAssertEqual(ThemeStore(defaults: d, sharedDefaults: nil).theme, .pink)
        d.set("not-a-theme", forKey: AppTheme.storageKey)
        XCTAssertEqual(AppThemeStorage.load(from: d), .pink)
        XCTAssertEqual(AppTheme.default, .pink)
    }

    func testPinkKeepsTheOriginalPalette() {
        let p = AppTheme.pink.palette
        XCTAssertEqual(p.accent, ThemeHex(0xDD8C96))
        XCTAssertEqual(p.progress, ThemeHex(0xDD8C96, 0xE89DA6))
        XCTAssertEqual(p.soft, ThemeHex(0xF4DAD4))
        XCTAssertEqual(p.tint, ThemeHex(0xF6E1E3, 0x3A2830))
        XCTAssertEqual(p.onAccent, ThemeHex(0x111111))
        XCTAssertEqual(p.canvas, ThemeHex(0xF8F4F2, 0x000000))
        XCTAssertEqual(p.fill, ThemeHex(0xEFE8E6, 0x2C2C2E))
    }

    func testChoiceRoundTripsAndReachesTheWidgets() {
        let own = freshDefaults(), shared = freshDefaults("shared")
        let store = ThemeStore(defaults: own, sharedDefaults: shared)
        store.theme = .forest
        XCTAssertEqual(own.string(forKey: Constants.Storage.appTheme), "forest")
        XCTAssertEqual(AppThemeStorage.load(from: shared), .forest)
        XCTAssertEqual(ThemeStore(defaults: own, sharedDefaults: shared).theme, .forest)
        for theme in AppTheme.allCases {
            store.theme = theme
            XCTAssertEqual(ThemeStore(defaults: own, sharedDefaults: nil).theme, theme)
        }
    }

    func testStartUpMirrorsAnEarlierChoiceIntoTheAppGroup() {
        let own = freshDefaults(), shared = freshDefaults("shared2")
        AppThemeStorage.save(.teal, to: own)
        _ = ThemeStore(defaults: own, sharedDefaults: shared)
        XCTAssertEqual(AppThemeStorage.load(from: shared), .teal)
    }

    func testColoursFollowTheTheme() {
        let store = ThemeStore(defaults: freshDefaults(), sharedDefaults: nil)
        store.theme = .ocean
        let blue = UIColor(store.colors.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        blue.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(b, r, "Ocean Blue's accent should be blue")
    }

    func testEveryThemeHasANameAndDistinctAccent() {
        XCTAssertEqual(AppTheme.allCases.count, 8)
        XCTAssertEqual(Set(AppTheme.allCases.map(\.name)).count, AppTheme.allCases.count)
        XCTAssertEqual(Set(AppTheme.allCases.map(\.palette.accent.light)).count, AppTheme.allCases.count)
    }
}
