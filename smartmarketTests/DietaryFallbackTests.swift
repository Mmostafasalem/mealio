import XCTest
@testable import smartmarket

/// The offline/no-consent plan must never suggest a food that conflicts with
/// a selected diet or allergy.
@MainActor
final class DietaryFallbackTests: XCTestCase {
    private var savedDomain: [String: Any] = [:]
    private let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"

    override func setUp() {
        super.setUp()
        savedDomain = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        // No cart or grocery rows: exercise the generic menu or the pantry path.
        UserDefaults.standard.removeObject(forKey: "shoppingCart_v1")
        UserDefaults.standard.removeObject(forKey: Constants.Storage.groceryList)
    }

    override func tearDown() {
        UserDefaults.standard.setPersistentDomain(savedDomain, forName: domain)
        super.tearDown()
    }

    private func texts(_ plan: WeeklyMealPlan) -> [String] {
        [plan.pirmadienis, plan.antradienis, plan.treciadienis, plan.ketvirtadienis,
         plan.pentadienis, plan.sestadienis, plan.sekmadienis]
            .compactMap { $0 }
            .flatMap { [$0.pusryciai, $0.pietus, $0.vakariene, $0.uzkandziai] }
            .compactMap { $0 }
            .flatMap { [$0.pavadinimas] + $0.ingredientai }
    }

    private func assertNoConflicts(_ plan: WeeklyMealPlan, _ prefs: Set<DietaryPreference>,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let all = texts(plan)
        XCTAssertFalse(all.isEmpty, file: file, line: line)
        for text in all {
            for pref in prefs {
                XCTAssertFalse(pref.conflicts(name: text), "\(pref.rawValue) conflicts with \(text)",
                               file: file, line: line)
            }
        }
    }

    func testGenericPlanRespectsEveryPreferenceAloneAndCombined() {
        var cases = DietaryPreference.allCases.map { Set([$0]) }
        cases.append(Set(DietaryPreference.allCases))
        for prefs in cases {
            assertNoConflicts(FallbackData.mealPlan(targetKcal: 2000, pantry: [], preferences: prefs), prefs)
        }
    }

    func testPantryPlanSubstitutesConflictingFoodsAndDefaults() {
        var cases = DietaryPreference.allCases.map { Set([$0]) }
        cases.append([.vegan, .nutAllergy, .glutenFree])
        cases.append(Set(DietaryPreference.allCases))
        for prefs in cases {
            assertNoConflicts(FallbackData.mealPlan(targetKcal: 2000, pantry: FallbackData.deals,
                                                    preferences: prefs), prefs)
        }
    }

    func testReportedConflictsAreGone() {
        let generic = texts(FallbackData.mealPlan(targetKcal: 2000, pantry: [], preferences: [.nutAllergy]))
            .joined(separator: " ").lowercased()
        XCTAssertFalse(generic.contains("almond") || generic.contains("peanut") || generic.contains("nuts"))

        let vegan = texts(FallbackData.mealPlan(targetKcal: 2000, pantry: FallbackData.deals, preferences: [.vegan]))
            .joined(separator: " ").lowercased()
        for word in ["pork", "beef", "chicken", "salmon", "yogurt", "egg", "milk"] {
            XCTAssertFalse(vegan.contains(word), "vegan plan contains \(word)")
        }

        let noPork = texts(FallbackData.mealPlan(targetKcal: 2000, pantry: FallbackData.deals, preferences: [.noPork]))
            .joined(separator: " ").lowercased()
        XCTAssertFalse(noPork.contains("pork"))
        XCTAssertTrue(noPork.contains("chicken"), "Non-conflicting foods are kept")
    }

    func testDealAllergenTagsCountAsConflicts() {
        XCTAssertTrue(DietaryPreference.lactoseFree.conflicts(name: "Protein shake", allergens: ["milk"]))
        XCTAssertTrue(DietaryPreference.glutenFree.conflicts(name: "Rolled grains", category: "grains"))
        XCTAssertFalse(DietaryPreference.glutenFree.conflicts(name: "Basmati rice", category: "grains"))
        XCTAssertTrue(DietaryPreference.halal.conflicts(name: "Beef mince", category: "meat"))
        XCTAssertFalse(DietaryPreference.halal.conflicts(name: "Halal beef mince", category: "meat"))
    }
}
