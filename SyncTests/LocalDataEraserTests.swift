import XCTest
@testable import MealioSync

final class LocalDataEraserTests: XCTestCase {
    func testEraseRemovesCartAndUnknownLegacyDataWithoutClearingOtherDomains() throws {
        let domain = "MealioTests." + UUID().uuidString
        let other = "MealioTests.Other." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let otherDefaults = try XCTUnwrap(UserDefaults(suiteName: other))
        defer {
            defaults.removePersistentDomain(forName: domain)
            otherDefaults.removePersistentDomain(forName: other)
        }
        defaults.set(Data([1]), forKey: "shoppingCart_v1")
        defaults.set(80, forKey: "weeklyBudget")
        defaults.set("private", forKey: "legacyKeyNotInAnAllowlist")
        otherDefaults.set("preserved", forKey: "unrelated")
        LocalDataEraser.clear(defaults: defaults, domain: domain)
        XCTAssertNil(defaults.object(forKey: "shoppingCart_v1"))
        XCTAssertNil(defaults.object(forKey: "weeklyBudget"))
        XCTAssertNil(defaults.object(forKey: "legacyKeyNotInAnAllowlist"))
        XCTAssertEqual(otherDefaults.string(forKey: "unrelated"), "preserved")
    }
}
