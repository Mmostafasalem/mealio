import Foundation
import MapKit
import CoreLocation
import SwiftUI

@MainActor
@Observable
final class StoreMapViewModel {

    var deals: [MarketDeal] = []
    var selectedStore: Store?
    var storeDeals: [MarketDeal] = []
    var cameraPosition: MapCameraPosition = .automatic
    var isLoadingDeals = false
    var errorMessage: String?

    // MARK: - Computed

    var uniqueStores: [Store] {
        var seen = Set<String>()
        return deals.compactMap { deal in
            guard seen.insert(deal.store.id).inserted else { return nil }
            return deal.store
        }
    }

    // MARK: - Load

    func load() async {
        isLoadingDeals = true
        defer { isLoadingDeals = false }

        do {
            deals = try await APIService.shared.fetchMarketDeals()
        } catch {
            deals = MarketDeal.mocked
            errorMessage = nil
        }

        // Centre camera on the user's current location if available,
        // otherwise default to Vilnius city centre.
        let vilnius = CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797)
        let centre = LocationService.shared.userLocation?.coordinate ?? vilnius
        cameraPosition = MapCameraPosition.region(MKCoordinateRegion(
            center: centre,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }

    // MARK: - Store selection

    func selectStore(_ store: Store) {
        selectedStore = store

        // Favourite food IDs are stored as catalog string IDs (e.g. "visc-file").
        // Deal.productId is the backend integer ID as a string (e.g. "3").
        // Bridge via Food.catalog.backendId so the comparison is apples-to-apples.
        let favCatalogIDs = Set(
            (UserDefaults.standard.array(forKey: Constants.Storage.favoriteFoodIDs) as? [String]) ?? []
        )
        let favProductIDs = Set(
            Food.catalog
                .filter { favCatalogIDs.contains($0.id) }
                .compactMap { $0.backendId }
                .map { String($0) }
        )

        let forStore = deals.filter { $0.store.id == store.id }
        let favs    = forStore.filter { favProductIDs.contains($0.productId) }
                               .sorted { $0.productName < $1.productName }
        let rest    = forStore.filter { !favProductIDs.contains($0.productId) }
                               .sorted { $0.productName < $1.productName }
        storeDeals = favs + rest
    }

    func dismissStore() {
        selectedStore = nil
        storeDeals = []
    }

    // MARK: - Recipes

    func recipesForStore(_ store: Store) -> [StoreRecipe] {
        let discountedIDs = Set(
            deals.filter { $0.store.id == store.id }.map { $0.productId }
        )
        return StoreRecipe.recipesMatching(discountedIDs: discountedIDs)
    }
}

