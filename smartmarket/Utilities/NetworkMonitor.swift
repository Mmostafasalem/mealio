import Foundation
import Network
import Observation

/// View-layer reachability signal used to show a subtle "Offline" badge so
/// cached/fallback content isn't mistaken for live data. This is presentation
/// only — it does NOT drive any networking or business logic (those live in
/// `Services/` and are unchanged); it merely reflects the current path status.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mealio.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }
}
