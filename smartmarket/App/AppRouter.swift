import SwiftUI
import CoreSpotlight

/// Where outside entry points (widgets, the Control Center button, Siri,
/// Shortcuts, Spotlight, `nourlo://` links) ask the app to go. `MainTabView`
/// watches `request` and takes it with `takeRequest()`.
///
/// Every request is time-limited: one that isn't shown within
/// `requestLifetime` (for example because onboarding isn't finished) is
/// dropped instead of popping up later, and nothing is handed out before
/// onboarding is complete.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter(observesInbox: true)

    /// Where a request goes.
    enum Destination: Equatable {
        case link(NourloLink)
        case exercise(String)
    }

    struct Request: Equatable {
        let id: UUID
        let destination: Destination
        let at: Date
    }

    /// The newest request; `MainTabView` takes it once.
    private(set) var request: Request?
    /// Bumps on every barcode-scan request, so an open food logger can react.
    private(set) var scanRequestID = 0
    @ObservationIgnored private var scanRequestedAt: Date?

    /// Requests older than this are dropped.
    static let requestLifetime: TimeInterval = 60
    /// A scan request older than this no longer opens the camera.
    static let scanLifetime: TimeInterval = 30

    /// Spotlight items for exercises used this prefix on their identifier
    /// (builds before schema 2); newer items use the bare exercise id.
    nonisolated static let exerciseActivityPrefix = "exercise:"

    @ObservationIgnored private var inboxObserver: NSObjectProtocol?
    @ObservationIgnored private let isReady: @MainActor () -> Bool
    @ObservationIgnored private let now: () -> Date

    init(observesInbox: Bool = false,
         isReady: (@MainActor () -> Bool)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.isReady = isReady ?? { AppState.shared.isOnboarded }
        self.now = now
        guard observesInbox else { return }
        inboxObserver = NotificationCenter.default.addObserver(forName: NourloLinkInbox.didPost, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.takeInbox() }
        }
    }

    func open(_ link: NourloLink) {
        if link == .scan {
            scanRequestedAt = now()
            scanRequestID &+= 1
        }
        request = Request(id: UUID(), destination: .link(link), at: now())
    }

    func open(_ url: URL) {
        if let link = NourloLink(url: url) { open(link) }
    }

    /// A workout kind Siri or Shortcuts asked for; Train reads it with
    /// `consumeWorkoutKind()` to preselect the builder.
    private(set) var workoutKind: ExerciseKind?

    /// Opens Train, remembering the kind (if any) for the builder.
    func startWorkout(kind: ExerciseKind?) {
        workoutKind = kind
        NourloLinkInbox.post(.train)
    }

    /// The requested workout kind, cleared so it's applied once.
    func consumeWorkoutKind() -> ExerciseKind? {
        defer { workoutKind = nil }
        return workoutKind
    }

    func showExercise(id: String) {
        let id = Self.exerciseID(fromIdentifier: id)
        guard Exercise.catalog.contains(where: { $0.id == id }) else { return }
        request = Request(id: UUID(), destination: .exercise(id), at: now())
    }

    /// The exercise id in a Spotlight identifier, with or without the old prefix.
    nonisolated static func exerciseID(fromIdentifier identifier: String) -> String {
        identifier.hasPrefix(exerciseActivityPrefix) ? String(identifier.dropFirst(exerciseActivityPrefix.count)) : identifier
    }

    /// A Spotlight result (or Handoff activity) for one of our items.
    func handle(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        // Only exercises are indexed; `showExercise` ignores anything else.
        showExercise(id: id)
    }

    /// Opens a link an intent left. Before onboarding is complete the link
    /// stays in the inbox, where it expires after `NourloLinkInbox.lifetime`.
    func takeInbox() {
        guard isReady() else { return }
        if let link = NourloLinkInbox.take(now: now()) { open(link) }
    }

    /// The request to show now, if there is a fresh one and the app is ready.
    /// Clears it, so it's shown once; a stale request is dropped.
    func takeRequest() -> Destination? {
        guard isReady(), let request else { return nil }
        self.request = nil
        guard NourloLinkInbox.isFresh(postedAt: request.at, now: now(), lifetime: Self.requestLifetime) else { return nil }
        return request.destination
    }

    /// The food logger asks whether it should open the scanner. True once per
    /// request, and only within `scanLifetime` of it.
    func consumeScanRequest() -> Bool {
        guard let at = scanRequestedAt else { return false }
        scanRequestedAt = nil
        return NourloLinkInbox.isFresh(postedAt: at, now: now(), lifetime: Self.scanLifetime)
    }
}
