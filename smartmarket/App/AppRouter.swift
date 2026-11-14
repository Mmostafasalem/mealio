import SwiftUI
import CoreSpotlight

/// Where outside entry points (widgets, the Control Center button, Siri,
/// Shortcuts, Spotlight, `nourlo://` links) ask the app to go. `MainTabView`
/// watches `pending` and `exerciseID` and shows the screen.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// A screen to open; `MainTabView` clears it once handled.
    var pending: NourloLink?
    /// An exercise whose guide to show (from Spotlight or Siri).
    var exerciseID: String?
    /// Set when the barcode scanner should open with the food logger.
    private(set) var scanRequested = false

    /// Spotlight items for exercises use this prefix on their identifier.
    static let exerciseActivityPrefix = "exercise:"

    @ObservationIgnored private var inboxObserver: NSObjectProtocol?

    private init() {
        inboxObserver = NotificationCenter.default.addObserver(forName: NourloLinkInbox.didPost, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppRouter.shared.takeInbox() }
        }
    }

    func open(_ link: NourloLink) {
        if link == .scan { scanRequested = true }
        pending = link
    }

    func open(_ url: URL) {
        if let link = NourloLink(url: url) { open(link) }
    }

    func showExercise(id: String) {
        guard Exercise.catalog.contains(where: { $0.id == id }) else { return }
        exerciseID = id
    }

    /// A Spotlight result (or Handoff activity) for one of our items.
    func handle(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        if id.hasPrefix(Self.exerciseActivityPrefix) {
            showExercise(id: String(id.dropFirst(Self.exerciseActivityPrefix.count)))
        }
    }

    /// Opens a link an intent left while the app wasn't running.
    func takeInbox() {
        if let link = NourloLinkInbox.take() { open(link) }
    }

    /// The food logger asks once whether it should start with the scanner.
    func consumeScanRequest() -> Bool {
        defer { scanRequested = false }
        return scanRequested
    }
}
