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
    var isLoadingStores = false
    var storeLookupMessage: String?
    private var storeLookupGeneration = UUID()

    var visibleStores: [Store] {
        guard showNearbyOnly, let location = LocationService.shared.userLocation else { return stores }
        return stores.filter {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 8_000
        }
    }

    // MARK: - Load

    func load(appState: AppState) {
        // Start location updates
        LocationService.shared.startUpdating()
        refreshDeals(appState: appState)
        loadRealStores()
        observeLocation()
    }

    private func observeLocation() {
        // Poll for first location fix to snap camera and refine store search.
        Task {
            for _ in 0..<30 {      // try for up to 15 s
                if let loc = LocationService.shared.userLocation, !hasCentredOnUser {
                    centreOn(loc.coordinate, zoom: 5_000)
                    hasCentredOnUser = true
                    loadRealStores()   // re-search centred on the user's real position
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Real store locations (MapKit local search)

    /// Finds actual supermarket branches near the user (or Vilnius centre) via
    /// MapKit in any supported country. Catalog/demo coordinates are never used as branch locations.
    func loadRealStores() {
        let center = LocationService.shared.userLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797)
        let generation = UUID()
        storeLookupGeneration = generation
        isLoadingStores = true
        storeLookupMessage = nil
        Task {
            let found = await Self.searchMarkets(near: center)
            guard generation == storeLookupGeneration else { return }
            applyStoreSearchResults(found)
        }
    }

    func applyStoreSearchResults(_ found: [Store]) {
        var seen = Set<String>()
        stores = found.filter { store in
            let key = String(format: "%.4f,%.4f", store.latitude, store.longitude)
            return seen.insert(key).inserted
        }
        isLoadingStores = false
        storeLookupMessage = stores.isEmpty
            ? "Store locations are unavailable. Check your connection and retry."
            : nil
    }

    private static func searchMarkets(near center: CLLocationCoordinate2D) async -> [Store] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: 8000)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item -> Store? in
                guard let name = item.name, !name.isEmpty else { return nil }
                let coordinate = item.placemark.coordinate
                let chain = ["Rimi", "Maxima", "Lidl", "Iki", "Norfa", "Carrefour", "Kaufland", "Tesco", "Aldi", "Spinneys"]
                    .first { name.localizedCaseInsensitiveContains($0) } ?? name
                return Store(id: String(format: "%@_%.5f_%.5f", name.lowercased(), coordinate.latitude, coordinate.longitude),
                             chain: chain, name: name, address: item.placemark.title ?? "",
                             latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        } catch {
            appLog("[Map] nearby food market search failed:", error)
            return []
        }
    }

    // MARK: - Refresh deals/stores from AppState

    func refreshDeals(appState: AppState) {
        Task {
            let allMarket = (try? await APIService.shared.fetchMarketDeals()) ?? []

            // Estimates belong to a chain, not a verified branch inventory.
            // Nearby filtering uses actual Maps branches via visibleStores.
            storeDeals = allMarket
            // Store pins are managed by loadRealStores(); deals are matched by chain.
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

    /// - Parameter verticalBias: fraction of the visible latitude span to move the
    ///   camera centre south of `coord`, so the target sits higher on screen.
    private func centreOn(_ coord: CLLocationCoordinate2D, zoom: CLLocationDistance, verticalBias: Double = 0) {
        var region = MKCoordinateRegion(center: coord, latitudinalMeters: zoom, longitudinalMeters: zoom)
        region.center.latitude -= region.span.latitudeDelta * verticalBias
        let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .smoothCard
        withAnimation(animation) {
            cameraPosition = .region(region)
        }
    }

    // MARK: - Store selection

    func selectStore(_ store: Store) {
        selectedStore = store
        // Animate map to selected store, keeping the pin in the upper third above the .medium sheet.
        centreOn(CLLocationCoordinate2D(latitude: store.latitude, longitude: store.longitude),
                 zoom: 2_000, verticalBias: 0.25)
    }

    // MARK: - Deal helpers

    func dealCount(for store: Store) -> Int {
        storeDeals.filter { $0.store.chain.lowercased() == store.chain.lowercased() }.count
    }

    func deals(for store: Store) -> [MarketDeal] {
        storeDeals.filter { $0.store.chain.lowercased() == store.chain.lowercased() }
    }

    func favouriteDeals(for store: Store, favIDs: Set<String>) -> [MarketDeal] {
        let favNames = ProductCatalogService.shared.nameFor(ids: favIDs)
        return deals(for: store).filter { deal in
            let dn = deal.productName.lowercased()
            return favNames.contains { fav in dn.contains(fav) || fav.contains(dn.prefix(8)) }
        }
    }

    func otherDeals(for store: Store, favIDs: Set<String>) -> [MarketDeal] {
        let favSet = Set(favouriteDeals(for: store, favIDs: favIDs).map(\.id))
        return deals(for: store).filter { !favSet.contains($0.id) }
    }
}
