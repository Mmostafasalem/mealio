import XCTest
import UIKit
@testable import smartmarket

/// "Snap a meal": the photo is shrunk to fit the server, and its answer becomes
/// the voice feature's food phrases (names with grams).
@MainActor
final class MealPhotoTests: XCTestCase {

    /// A noisy picture (hard to compress), `width` × `height` pixels.
    private func noisyImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var generator = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for y in stride(from: 0, to: height, by: 4) {
                for x in stride(from: 0, to: width, by: 4) {
                    UIColor(red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator),
                            blue: .random(in: 0...1, using: &generator), alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }
    }

    func testEncodedPhotoIsASmallJPEG() throws {
        let image = noisyImage(width: 3000, height: 2000)
        let base64 = try XCTUnwrap(MealPhotoEncoder.base64JPEG(from: image))
        XCTAssertLessThanOrEqual(base64.count, MealPhotoEncoder.maxBase64Length)
        XCTAssertFalse(base64.hasPrefix("data:"))
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        // JPEG files start with FF D8 FF.
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF])
        let decoded = try XCTUnwrap(UIImage(data: data))
        let pixels = CGSize(width: decoded.size.width * decoded.scale, height: decoded.size.height * decoded.scale)
        XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 768)
        // The shape is kept.
        XCTAssertEqual(pixels.width / pixels.height, 1.5, accuracy: 0.02)
    }

    func testTightLimitShrinksFurther() throws {
        let image = noisyImage(width: 1600, height: 1600)
        let base64 = try XCTUnwrap(MealPhotoEncoder.base64JPEG(from: image, limit: 40_000))
        XCTAssertLessThanOrEqual(base64.count, 40_000)
    }

    func testSmallPhotoIsNotEnlarged() {
        let small = MealPhotoEncoder.resized(noisyImage(width: 300, height: 200), longestSide: 768)
        XCTAssertEqual(small.size, CGSize(width: 300, height: 200))
    }

    func testResponseBecomesGramPhrases() throws {
        let json = """
        {"foods":[{"name":"banana","grams":120},{"name":" grilled chicken breast ","grams":150.4},
                  {"name":"","grams":50},{"name":"rice","grams":5000},{"name":"butter","grams":0}]}
        """
        let response = try JSONDecoder().decode(FoodPhotoResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.phrases, [
            VoiceFoodPhrase(name: "banana", quantity: 120, unit: .gram),
            VoiceFoodPhrase(name: "grilled chicken breast", quantity: 150, unit: .gram),
            VoiceFoodPhrase(name: "rice", quantity: 1500, unit: .gram),
            VoiceFoodPhrase(name: "butter", quantity: 1, unit: .gram),
        ])
    }

    func testEmptyResponseHasNoPhrases() throws {
        let response = try JSONDecoder().decode(FoodPhotoResponse.self, from: Data(#"{"foods":[]}"#.utf8))
        XCTAssertTrue(response.phrases.isEmpty)
    }

    func testAtMostEightFoods() throws {
        let items = (1...12).map { #"{"name":"food \#($0)","grams":10}"# }.joined(separator: ",")
        let response = try JSONDecoder().decode(FoodPhotoResponse.self, from: Data(#"{"foods":[\#(items)]}"#.utf8))
        XCTAssertEqual(response.phrases.count, 8)
    }

    func testPhotoFoodsKeepTheirGramsInThePlan() throws {
        let banana = NutritionFood(id: "usda:1", name: "Bananas, raw", brand: nil, basis: .grams, kcal: 89, protein: 1, carbs: 23, fat: 0.3,
                                   source: .usda, sourceID: "1", sourceDate: nil)
        let phrases = [VoiceFoodPhrase(name: "banana", quantity: 120, unit: .gram)]
        let plan = VoiceCommandRunner.plan(for: .logFood(items: phrases, slot: .lunch), search: { _ in [banana] })
        guard case .food(let matches, let missing, let slot) = plan else { return XCTFail("not a food plan") }
        XCTAssertEqual(slot, .lunch)
        XCTAssertTrue(missing.isEmpty)
        XCTAssertEqual(matches.first?.amount, 120)
        XCTAssertEqual(matches.first?.food.id, "usda:1")
    }

    func testNoFoodsShowsThePlainMessage() {
        let model = VoiceCommandModel(photoMode: true)
        model.start()
        XCTAssertEqual(model.phase, .choosingPhoto)
        model.start(photoFoods: [])
        XCTAssertEqual(model.phase, .failed(VoiceCommandModel.nothingInPhoto))
        XCTAssertEqual(VoiceCommandModel.nothingInPhoto, "I couldn't make out any food in that photo.")
    }

    func testOldUsageWithoutPhotoCostStillDecodes() throws {
        let old = #"{"limit":50,"used":2,"remaining":48,"resetsAt":"2026-11-21T00:00:00Z","mealPlanCost":5,"shortRequestCost":1}"#
        XCTAssertNil(try JSONDecoder().decode(AIAllowance.self, from: Data(old.utf8)).photoCost)
        let new = #"{"limit":50,"used":2,"remaining":48,"resetsAt":"2026-11-21T00:00:00Z","mealPlanCost":5,"shortRequestCost":1,"photoCost":2}"#
        XCTAssertEqual(try JSONDecoder().decode(AIAllowance.self, from: Data(new.utf8)).photoCost, 2)
    }
}
