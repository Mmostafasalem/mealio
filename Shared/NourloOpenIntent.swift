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

    /// Leaves a link for the app to open, and tells a running app at once.
    static func post(_ link: NourloLink, defaults: UserDefaults = .standard) {
        defaults.set(link.rawValue, forKey: key)
        NotificationCenter.default.post(name: didPost, object: nil)
    }

    /// The pending link, removed so it's opened once.
    static func take(defaults: UserDefaults = .standard) -> NourloLink? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return NourloLink(rawValue: raw)
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
nonisolated struct OpenNourloIntent: AppIntent {
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
