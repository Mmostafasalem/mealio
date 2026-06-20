import XCTest
@testable import smartmarket

final class PortionTests: XCTestCase {

    func testSpoonsForOils() {
        XCTAssertTrue(Portion.household(grams: 30, category: "oils").contains("tbsp"))
    }

    func testPlateForMeat() {
        XCTAssertTrue(Portion.household(grams: 250, category: "meat").contains("plate"))
    }

    func testEggsAsPieces() {
        XCTAssertTrue(Portion.household(grams: 120, category: "eggs").contains("egg"))
    }

    func testHandfulForNuts() {
        XCTAssertTrue(Portion.household(grams: 30, category: "nuts").contains("handful"))
    }
}
