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
        // Show approximate pins instantly, then refine to real branches via MapKit.
        if stores.isEmpty { stores = Self.vilniusStores }
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
    /// MapKit, replacing the approximate hardcoded pins. Falls back to the
    /// hardcoded list if the search yields nothing.
    func loadRealStores() {
        let center = LocationService.shared.userLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797)
        Task {
            var found: [Store] = []
            await withTaskGroup(of: [Store].self) { group in
                for chain in ["Rimi", "Maxima", "Lidl", "Iki", "Norfa"] {
                    group.addTask { await Self.search(chain: chain, near: center) }
                }
                for await result in group { found.append(contentsOf: result) }
            }
            if !found.isEmpty {
                // De-dupe by rounded coordinate so the same branch isn't doubled.
                var seen = Set<String>()
                stores = found.filter { s in
                    let key = String(format: "%.4f,%.4f", s.latitude, s.longitude)
                    return seen.insert(key).inserted
                }
            }
        }
    }

    private static func search(chain: String, near center: CLLocationCoordinate2D) async -> [Store] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = chain
        request.region = MKCoordinateRegion(center: center,
                                            latitudinalMeters: 14_000,
                                            longitudinalMeters: 14_000)
        request.resultTypes = .pointOfInterest
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item -> Store? in
                let name = item.name ?? ""
                // Keep only results that are actually this chain (filters out noise).
                guard name.localizedCaseInsensitiveContains(chain) else { return nil }
                let coord = item.placemark.coordinate
                return Store(
                    id: String(format: "%@_%.4f_%.4f", chain.lowercased(), coord.latitude, coord.longitude),
                    chain: chain,
                    name: name,
                    address: item.placemark.title ?? "",
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
            }
        } catch {
            appLog("[Map] search for \(chain) failed:", error)
            return []
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
                    return loc.distance(from: storeLoc) <= 8_000
                }
            } else {
                filtered = allMarket
            }

            storeDeals = filtered
            // Store pins are managed by loadRealStores(); deals are matched by chain.
        }
    }

    // Hardcoded Vilnius supermarket locations — shown even when backend is offline
    static let vilniusStores: [Store] = [
        Store(id: "rimi",   chain: "Rimi",   name: "Rimi Vilnius Centre",    address: "Gedimino pr. 9",          latitude: 54.6869, longitude: 25.2796),
        Store(id: "rimi2",  chain: "Rimi",   name: "Rimi Panorama",          address: "Saltoniškių g. 9",        latitude: 54.7154, longitude: 25.2630),
        Store(id: "maxima", chain: "Maxima", name: "Maxima XX Savanoriai",    address: "Savanorių pr. 176",       latitude: 54.6634, longitude: 25.2240),
        Store(id: "maxima2",chain: "Maxima", name: "Maxima XXX Ozas",         address: "Ozo g. 18",               latitude: 54.7201, longitude: 25.2690),
        Store(id: "lidl",   chain: "Lidl",   name: "Lidl Vilnius North",      address: "Ukmergės g. 369",         latitude: 54.7321, longitude: 25.2805),
        Store(id: "lidl2",  chain: "Lidl",   name: "Lidl Šeškinė",            address: "Šeškinės g. 25",          latitude: 54.7032, longitude: 25.2205),
        Store(id: "iki",    chain: "Iki",    name: "Iki Senamiestis",         address: "Pylimo g. 21",            latitude: 54.6791, longitude: 25.2712),
        Store(id: "norfa",  chain: "Norfa",  name: "Norfa Pašilaičiai",       address: "Laisvės pr. 75",          latitude: 54.7021, longitude: 25.3221),
    ]

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
