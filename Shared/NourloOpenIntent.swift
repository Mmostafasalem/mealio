import AppIntents
import Foundation

// MARK: - Opening a screen from outside the app
//
// Widgets, the Control Center button, Siri, Shortcuts and Spotlight all open a
// screen the same way: they hand a `NourloLink` to `NourloLinkInbox`, and the
// app's router (`AppRouter`, app target only) takes it when the app is active.
// Compiled into the app and the widget extension; an intent with
// `openAppWhenRun` performs in the app's process.

nonisolated enum NourloLinkInbox {
    static let didPost = Notification.Name("nourloLinkInboxDidPost")
    private static let key = "nourloPendingLink"
    private static let timeKey = "nourloPendingLinkAt"
    /// A link not opened within this many seconds is dropped, so a request
    /// made during onboarding (or one that never reached the screen) doesn't
    /// fire much later.
    static let lifetime: TimeInterval = 60

    /// The App Group defaults, so a link left by an intent running in the widget
    /// extension still reaches the app; plain defaults when the group is missing.
    static var defaults: UserDefaults { NourloAppGroup.defaults ?? .standard }

    /// Leaves a link for the app to open, and tells a running app at once.
    static func post(_ link: NourloLink, defaults: UserDefaults = NourloLinkInbox.defaults, now: Date = Date()) {
        defaults.set(link.rawValue, forKey: key)
        defaults.set(now.timeIntervalSince1970, forKey: timeKey)
        NotificationCenter.default.post(name: didPost, object: nil)
    }

    /// The pending link if it is still fresh, removed so it's opened once.
    /// An expired link is removed and nil is returned.
    static func take(defaults: UserDefaults = NourloLinkInbox.defaults, now: Date = Date()) -> NourloLink? {
        // Links from builds that kept them in the standard defaults, without a time: drop them.
        if defaults !== UserDefaults.standard { UserDefaults.standard.removeObject(forKey: key) }
        guard let raw = defaults.string(forKey: key) else { return nil }
        let postedAt = defaults.object(forKey: timeKey) as? Double
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: timeKey)
        guard let postedAt, isFresh(postedAt: Date(timeIntervalSince1970: postedAt), now: now) else { return nil }
        return NourloLink(rawValue: raw)
    }

    /// True while a link posted at `postedAt` may still be opened. A little
    /// clock skew into the future is tolerated.
    static func isFresh(postedAt: Date, now: Date, lifetime: TimeInterval = NourloLinkInbox.lifetime) -> Bool {
        let age = now.timeIntervalSince(postedAt)
        return age >= -5 && age <= lifetime
    }
}

nonisolated extension NourloLink: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Nourlo screen" }
    static var caseDisplayRepresentations: [NourloLink: DisplayRepresentation] {
        [
            .home: DisplayRepresentation(title: "Today", image: .init(systemName: "house")),
            .logFood: DisplayRepresentation(title: "Log food", image: .init(systemName: "plus.circle")),
            .meals: DisplayRepresentation(title: "Meal plan", image: .init(systemName: "fork.knife")),
            .groceries: DisplayRepresentation(title: "Grocery list", image: .init(systemName: "checklist")),
            .train: DisplayRepresentation(title: "Workouts", image: .init(systemName: "figure.strengthtraining.traditional")),
            .scan: DisplayRepresentation(title: "Scan a barcode", image: .init(systemName: "barcode.viewfinder")),
        ]
    }
}

/// Opens Nourlo on a screen. Used by the Control Center button, widgets and Shortcuts.
struct OpenNourloIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Nourlo" }
    static var description: IntentDescription { IntentDescription("Opens Nourlo on the screen you choose.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Screen", default: .logFood)
    var screen: NourloLink

    init() {}
    init(screen: NourloLink) { self.screen = screen }

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$screen) in Nourlo") }

    func perform() async throws -> some IntentResult {
        NourloLinkInbox.post(screen)
        return .result()
    }
}
