import XCTest
@testable import MealioSync

final class SyncSnapshotCodecTests: XCTestCase {
    func testConcurrentRowsMergeWithoutReplacingList() throws {
        let phone = try SyncSnapshotCodec.split(Data(#"[{"id":"a","name":"Apple"}]"#.utf8), prefix: "cart")
        let tablet = try SyncSnapshotCodec.split(Data(#"[{"id":"b","name":"Banana"}]"#.utf8), prefix: "cart")
        let joined = try SyncSnapshotCodec.join(phone.merging(tablet) { first, _ in first }, prefix: "cart")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: joined) as? [[String: String]])
        XCTAssertEqual(rows.map { $0["name"] }, ["Apple", "Banana"])
    }

    func testMissingIdentifiersDoNotSilentlyDropRows() {
        XCTAssertThrowsError(try SyncSnapshotCodec.split(Data(#"[{"name":"Apple"}]"#.utf8), prefix: "cart"))
    }

    func testDuplicateIdentifiersAreRejected() {
        XCTAssertThrowsError(try SyncSnapshotCodec.split(Data(#"[{"id":"a"},{"id":"a"}]"#.utf8), prefix: "cart"))
    }

    func testSameCartLineOnTwoDevicesHasOneLogicalIdentity() throws {
        let phone = try SyncSnapshotCodec.split(Data(#"[{"id":"uuid-1","catalogId":"apple","store":"Rimi","quantity":1}]"#.utf8), prefix: "shoppingCart_v1")
        let tablet = try SyncSnapshotCodec.split(Data(#"[{"id":"uuid-2","catalogId":"apple","store":"Rimi","quantity":2}]"#.utf8), prefix: "shoppingCart_v1")
        XCTAssertEqual(Set(phone.keys), Set(tablet.keys))
        XCTAssertEqual(phone.merging(tablet) { _, new in new }.count, 1)
    }

    func testShoppingRowsCannotCarryUnknownHealthFields() throws {
        let snapshot = try SyncSnapshotCodec.split(Data(#"[{"id":"a","food_name":"Apple","bodyWeight":70,"allergy":"nuts"}]"#.utf8), prefix: "groceryList")
        let joined = try SyncSnapshotCodec.join(snapshot, prefix: "groceryList")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: joined) as? [[String: Any]])
        XCTAssertEqual(rows.first?["food_name"] as? String, "Apple")
        XCTAssertNil(rows.first?["bodyWeight"])
        XCTAssertNil(rows.first?["allergy"])
    }
}
