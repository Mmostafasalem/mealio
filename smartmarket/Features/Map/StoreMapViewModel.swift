import SwiftUI
import MapKit
import CoreLocation

@MainActor
@Observable
final class StoreMapViewModel {

    // MARK: - State
    var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797),
        latitudinalMeters: 8_000,
        longitudinalMeters: 8_000
    ))
    var stores: [Store] = []
    var selectedStore: Store? = nil
    var storeDeals: [MarketDeal] = []
    var showNearbyOnly: Bool = true
    var hasCentredOnUser = false

    // MARK: - Load

    func load(appState: AppState) {
        // Start location updates
        LocationService.shared.startUpdating()
        // Build stores and watch location for camera update
        refreshDeals(appState: appState)
        observeLocation()
    }

    private func observeLocation() {
        // Poll for first location fix to snap camera
        Task {
            for _ in 0..<30 {      // try for up to 15 s
                if let loc = LocationService.shared.userLocation, !hasCentredOnUser {
                    centreOn(loc.coordinate, zoom: 5_000)
                    hasCentredOnUser = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Refresh deals/stores from AppState

    func refreshDeals(appState: AppState) {
        Task {
            let allMarket = (try? await APIService.shared.fetchMarketDeals()) ?? []

            let userLoc = LocationService.shared.userLocation
            let filtered: [MarketDeal]
            if showNearbyOnly, let loc = userLoc {
                filtered = allMarket.filter { deal in
                    let storeLoc = CLLocation(latitude: deal.store.latitude, longitude: deal.store.longitude)
                    return loc.distance(from: storeLoc) <= 8_000  // 8 km
                }
            } else {
                filtered = allMarket
            }

            storeDeals = filtered

            // Deduplicate stores preserving order
            var seen = Set<String>()
            stores = filtered.compactMap { deal -> Store? in
                let id = deal.store.id
                guard !seen.contains(id) else { return nil }
                seen.insert(id)
                return deal.store
            }
        }
    }

    // MARK: - Camera

    func centreOnUser() {
        guard let loc = LocationService.shared.userLocation else {
            // Permission not yet granted or no fix — request
            LocationService.shared.requestPermission()
            return
        }
        centreOn(loc.coordinate, zoom: 5_000)
    }

    private func centreOn(_ coord: CLLocationCoordinate2D, zoom: CLLocationDistance) {
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: zoom,
                longitudinalMeters: zoom
            ))
        }
    }

    // MARK: - Store selection

    func selectStore(_ store: Store) {
        selectedStore = store
        // Animate map to selected store
        centreOn(CLLocationCoordinate2D(latitude: store.latitude, longitude: store.longitude), zoom: 2_000)
    }

    // MARK: - Deal helpers

    func dealCount(for store: Store) -> Int {
        storeDeals.filter { $0.store.id == store.id }.count
    }

    func deals(for store: Store) -> [MarketDeal] {
        storeDeals.filter { $0.store.id == store.id }
    }

    func favouriteDeals(for store: Store, favIDs: Set<String>) -> [MarketDeal] {
        let backendIDs: Set<String> = Set(
            Food.catalog
                .filter { favIDs.contains($0.id) }
                .compactMap { $0.backendId.map { String($0) } }
        )
        return deals(for: store).filter { backendIDs.contains($0.productId) }
    }

    func otherDeals(for store: Store, favIDs: Set<String>) -> [MarketDeal] {
        let favSet = Set(favouriteDeals(for: store, favIDs: favIDs).map(\.id))
        return deals(for: store).filter { !favSet.contains($0.id) }
    }
}
