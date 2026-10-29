import XCTest
@testable import MealioSync

final class SyncDocumentTests: XCTestCase {
    func testConcurrentAdditionsSurviveMerge() {
        var phone = SyncDocument(generation: "initial")
        var tablet = phone
        phone.capture(["cart/a": Data("apple".utf8)], device: "phone")
        tablet.capture(["cart/b": Data("banana".utf8)], device: "tablet")
        let merged = phone.merging(tablet)
        XCTAssertEqual(merged.values["cart/a"], Data("apple".utf8))
        XCTAssertEqual(merged.values["cart/b"], Data("banana".utf8))
        XCTAssertEqual(merged, tablet.merging(phone))
    }

    func testRemovalTombstoneBeatsOlderValue() {
        var old = SyncDocument(generation: "initial")
        old.capture(["log/a": Data([1])], device: "phone")
        var deleted = old
        deleted.capture([:], device: "phone")
        XCTAssertNil(deleted.merging(old).values["log/a"])
    }

    func testResetDiscardsOfflineEditsFromPreviousGeneration() {
        var offline = SyncDocument(generation: "old")
        offline.capture(["profile": Data([1])], device: "offline")
        let reset = SyncDocument(generation: "new")
        XCTAssertEqual(offline.reconciled(with: reset), reset)
        XCTAssertTrue(offline.reconciled(with: reset).values.isEmpty)
    }

    func testEqualCountersHaveDeterministicWinner() {
        var a = SyncDocument(generation: "same")
        var b = a
        a.capture(["budget": Data([10])], device: "a")
        b.capture(["budget": Data([20])], device: "b")
        XCTAssertEqual(a.merging(b), b.merging(a))
        XCTAssertEqual(a.merging(b).values["budget"], Data([20]))
    }

    func testNoOpCaptureDoesNotOverwriteConcurrentEdit() {
        var a = SyncDocument(generation: "same")
        a.capture(["budget": Data([1])], device: "a")
        let before = a
        a.capture(["budget": Data([1])], device: "a")
        XCTAssertEqual(a, before)
    }

    func testPersistedTombstonesSurviveRestart() throws {
        var doc = SyncDocument(generation: "same")
        doc.capture(["cart/a": Data([1])], device: "a")
        let old = doc
        doc.capture([:], device: "a")
        let restored = try JSONDecoder().decode(SyncDocument.self, from: JSONEncoder().encode(doc))
        XCTAssertNil(restored.merging(old).values["cart/a"])
    }

    func testNewLocalChangesDoNotTombstoneUnseenRemoteRows() {
        var remote = SyncDocument(generation: "same")
        remote.capture(["cart/remote": Data([1])], device: "tablet")
        var merged = SyncDocument(generation: "same").merging(remote)
        merged.captureChanges(["cart/local": Data([2])], since: [:], device: "phone")
        XCTAssertEqual(merged.values["cart/remote"], Data([1]))
        XCTAssertEqual(merged.values["cart/local"], Data([2]))
    }

    func testUnchangedLocalValueDoesNotReplaceFetchedRemoteValue() {
        var local = SyncDocument(generation: "same")
        local.capture(["budget": Data([1])], device: "phone")
        let baseline = local.values
        var remote = local
        remote.capture(["budget": Data([2])], device: "tablet")
        var merged = local.merging(remote)
        merged.captureChanges(baseline, since: baseline, device: "phone")
        XCTAssertEqual(merged.values["budget"], Data([2]))
    }

    func testChangeMadeDuringNetworkSaveRemainsPending() {
        var local = SyncDocument(generation: "same")
        local.capture(["budget": Data([1])], device: "phone")
        let uploaded = local
        local.capture(["budget": Data([2])], device: "phone")
        let afterSave = uploaded.merging(local)
        XCTAssertEqual(afterSave.values["budget"], Data([2]))
        XCTAssertNotEqual(afterSave, uploaded)
    }

    func testCloudPayloadExcludesHealthAndUnknownFields() {
        var document = SyncDocument(generation: "same")
        document.capture([
            "userProfile": Data([1]), "bmrResponse": Data([2]),
            "foodLogEntries/a": Data([3]), "selectedDietaryFilters": Data([4]),
            "currentMealPlan": Data([5]), "API_KEY": Data([6]),
            "shoppingCart_v1/a": Data([7]), "weeklyBudget": Data([8])
        ], device: "phone")
        XCTAssertEqual(document.shoppingDataOnly().values, [
            "shoppingCart_v1/a": Data([7]), "weeklyBudget": Data([8])
        ])
    }
}
