import XCTest
@testable import smartmarket

@MainActor
final class StoreLocationIntegrityTests: XCTestCase {
    func testInitialLoadDoesNotPresentUnverifiedCatalogPinsAsBranches() {
        let vm = StoreMapViewModel()
        vm.load(appState: AppState.shared)
        // The MainActor has not yielded to the Maps lookup yet. Catalog/demo
        // coordinates must not be presented as real branch locations.
        XCTAssertTrue(vm.stores.isEmpty)
    }

    func testEmptyLookupOffersRetryWithoutInventingBranches() {
        let vm = StoreMapViewModel()
        vm.applyStoreSearchResults([])
        XCTAssertTrue(vm.stores.isEmpty)
        XCTAssertNotNil(vm.storeLookupMessage)
        XCTAssertFalse(vm.isLoadingStores)
    }

    func testLookupPreservesReturnedBranchAndDeduplicatesIt() {
        let vm = StoreMapViewModel()
        let branch = Store(id: "fixture", chain: "Rimi", name: "Fixture branch",
                           address: "Fixture address", latitude: 54.7, longitude: 25.3)
        vm.applyStoreSearchResults([branch, branch])
        XCTAssertEqual(vm.stores, [branch])
        XCTAssertNil(vm.storeLookupMessage)
        XCTAssertFalse(vm.isLoadingStores)
    }
}
