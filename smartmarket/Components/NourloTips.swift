import SwiftUI
import TipKit

/// TipKit setup and the app's few tips. Each tip shows once, at most one a day,
/// and is invalidated as soon as the person does the thing it teaches.
///
/// Placement rule: tips are inline (`TipView`), so they never cover controls.
enum NourloTips {

    /// The launch argument UI tests pass (`-NourloUITesting YES`) to keep tips away.
    static let uiTestingKey = "NourloUITesting"

    /// True when the app was launched by the UI tests. Reads the argument domain
    /// (`-NourloUITesting YES`) as well as plain arguments.
    static func isUITesting(arguments: [String] = ProcessInfo.processInfo.arguments,
                            defaults: UserDefaults = .standard) -> Bool {
        if let index = arguments.firstIndex(of: "-" + uiTestingKey) {
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { return true }
            return ["yes", "true", "1"].contains(arguments[next].lowercased())
        }
        return defaults.bool(forKey: uiTestingKey)
    }

    /// Call once at launch, before any view with a tip appears.
    static func configure() {
        // Must run before `Tips.configure`.
        if isUITesting() { Tips.hideAllTipsForTesting() }
        do {
            try Tips.configure([
                .displayFrequency(.daily),
                .datastoreLocation(.applicationDefault),
            ])
        } catch {
            // Already configured (or the store couldn't open): tips just don't show.
        }
    }

    /// Food was logged (in the app or through Siri / Shortcuts): the "Log food"
    /// tip has done its job. (Intent files can't import TipKit, whose `@Parameter`
    /// clashes with App Intents', so they call this.)
    static func foodLogged() {
        LogFoodTip().invalidate(reason: .actionPerformed)
    }

    /// Whether the logger should offer the scanner at all, given the device and
    /// camera permission. Denied permission still offers it, so the person gets
    /// an honest explanation and a way to Settings; a restricted camera (Screen
    /// Time, MDM) cannot be changed by them, so the button stays hidden.
    static func shouldOfferScan(isSupported: Bool, cameraRestricted: Bool) -> Bool {
        isSupported && !cameraRestricted
    }
}

// MARK: - Tips

/// On Home's "Log food" button.
nonisolated struct LogFoodTip: Tip {
    var id: String { "nourlo.logFood" }
    var title: Text { Text("Log food in two taps") }
    var message: Text? { Text("Tap Log food, then the plus next to any food to add a standard portion.") }
    var image: Image? { Image(systemName: "fork.knife") }
}

/// In the food logger, only on devices that can scan.
nonisolated struct ScanBarcodeTip: Tip {
    var id: String { "nourlo.scanBarcode" }
    var title: Text { Text("Scan a barcode") }
    var message: Text? { Text("Point the camera at a package to fill in its nutrition.") }
    var image: Image? { Image(systemName: "barcode.viewfinder") }
}

/// In Shop, while the weekly budget is still the default.
nonisolated struct WeeklyBudgetTip: Tip {
    /// Set by Shop from the cart: true once the person has changed the budget.
    @Parameter static var hasCustomBudget: Bool = false

    var id: String { "nourlo.weeklyBudget" }
    var title: Text { Text("Set a weekly budget") }
    var message: Text? { Text("Tap Edit to set what you spend on groceries each week. Meal plans stay within it.") }
    var image: Image? { Image(systemName: "eurosign.circle") }
    var rules: [Rule] {
        #Rule(Self.$hasCustomBudget) { $0 == false }
    }
}
