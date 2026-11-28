import XCTest
import UIKit
@testable import smartmarket

/// Tester feedback F2, F3 and D2: the profile photo, editable daily targets with
/// "Use recommended", and prices in the person's currency.
@MainActor
final class ProfileSettingsTests: XCTestCase {

    private var savedCurrency: String?

    override func setUp() {
        super.setUp()
        savedCurrency = CurrencyStore.shared.code
        TargetOverrides.clear()
    }

    override func tearDown() {
        CurrencyStore.shared.code = savedCurrency
        TargetOverrides.clear()
        super.tearDown()
    }

    // MARK: - D2 currency

    func testOfferAtLeastTenCommonCurrenciesWithUniqueCodes() {
        let codes = Money.currencies.map(\.code)
        XCTAssertGreaterThanOrEqual(codes.count, 10)
        XCTAssertEqual(Set(codes).count, codes.count)
        for code in ["EUR", "USD", "CAD", "GBP", "AUD", "CHF", "JPY", "SEK", "PLN", "INR"] {
            XCTAssertNotNil(Money.currency(code: code), code)
        }
        XCTAssertEqual(Money.currency(code: "EUR")?.perEUR, 1)
        XCTAssertTrue(Money.currencies.allSatisfy { $0.perEUR > 0 })
    }

    func testDefaultComesFromThePhonesRegion() {
        XCTAssertEqual(Money.regionalDefault(locale: Locale(identifier: "en_CA")).code, "CAD")
        XCTAssertEqual(Money.regionalDefault(locale: Locale(identifier: "fr_CA")).code, "CAD")
        XCTAssertEqual(Money.regionalDefault(locale: Locale(identifier: "en_US")).code, "USD")
        XCTAssertEqual(Money.regionalDefault(locale: Locale(identifier: "en_GB")).code, "GBP")
        XCTAssertEqual(Money.regionalDefault(locale: Locale(identifier: "lt_LT")).code, "EUR")
        XCTAssertEqual(Money.regionalDefault(locale: Locale(identifier: "de_DE")).code, "EUR")
        // A currency the table doesn't have: euros, the prices' own currency.
        XCTAssertEqual(Money.regionalDefault(locale: Locale(identifier: "sw_KE")).code, "EUR")
    }

    func testChosenCurrencyWinsAndNilFollowsTheRegionAgain() {
        Money.setCurrent("GBP")
        XCTAssertEqual(Money.current.code, "GBP")
        XCTAssertFalse(Money.followsRegion)
        Money.setCurrent("XYZ")   // not in the table
        XCTAssertTrue(Money.followsRegion)
        XCTAssertEqual(Money.current.code, Money.regionalDefault().code)
        Money.setCurrent(nil)
        XCTAssertTrue(Money.followsRegion)
    }

    func testConversionRoundTripsThroughEuros() throws {
        let cad = try XCTUnwrap(Money.currency(code: "CAD"))
        XCTAssertEqual(Money.local(fromEUR: 10, in: cad), 10 * cad.perEUR, accuracy: 0.0001)
        XCTAssertEqual(Money.eur(fromLocal: Money.local(fromEUR: 3.79, in: cad), in: cad), 3.79, accuracy: 0.0001)
        let eur = try XCTUnwrap(Money.currency(code: "EUR"))
        XCTAssertEqual(Money.local(fromEUR: 3.79, in: eur), 3.79)
    }

    func testFormattingShowsTheCurrency() throws {
        let canada = Locale(identifier: "en_CA")
        let cad = try XCTUnwrap(Money.currency(code: "CAD"))
        let eur = try XCTUnwrap(Money.currency(code: "EUR"))
        let jpy = try XCTUnwrap(Money.currency(code: "JPY"))
        let gbp = try XCTUnwrap(Money.currency(code: "GBP"))
        // 10 EUR in Canadian dollars, shown as a Canadian expects.
        let tenEuros = Money.format(eur: 10, in: cad, locale: canada)
        XCTAssertEqual(tenEuros, (10 * cad.perEUR).formatted(.currency(code: "CAD").locale(canada)))
        XCTAssertTrue(tenEuros.hasPrefix("$"), tenEuros)
        XCTAssertEqual(Money.format(eur: 60, in: eur, locale: Locale(identifier: "en_US")), "€60.00")
        XCTAssertEqual(Money.format(eur: 2, in: gbp, locale: Locale(identifier: "en_GB")), "£1.74")
        // Yen has no cents.
        let yen = Money.format(eur: 2, in: jpy, locale: Locale(identifier: "en_US"))
        XCTAssertFalse(yen.contains("."), yen)
        XCTAssertTrue(yen.contains("352"), yen)
        XCTAssertEqual(Money.formatWhole(eur: 60, in: cad, locale: canada), "$97")
    }

    func testTypedAmountsAreReadInTheCurrencyAndKeptInEuros() throws {
        let cad = try XCTUnwrap(Money.currency(code: "CAD"))
        XCTAssertEqual(Money.parseLocal("4.20", in: cad), 4.2)
        XCTAssertEqual(Money.parseLocal("4,20", in: cad), 4.2)
        XCTAssertEqual(Money.parseLocal("$4.20", in: cad), 4.2)
        XCTAssertEqual(Money.parseLocal(" CAD 100 ", in: cad), 100)
        XCTAssertNil(Money.parseLocal("abc", in: cad))
        // A 100 CAD budget is kept as euros and reads back as 100 CAD.
        guard case .success(let eur) = Money.validateLocal("100", eurRange: 5...2000, in: cad) else {
            return XCTFail("100 CAD is a valid budget")
        }
        XCTAssertEqual(eur, 100 / cad.perEUR, accuracy: 0.0001)
        XCTAssertEqual(Money.inputText(eur: eur, in: cad), "100")
        // The allowed range is checked in the currency too.
        XCTAssertEqual(Money.validateLocal("5", eurRange: 5...2000, in: cad),
                       .failure(.outOfRange(Money.localRange(5...2000, in: cad))))
        XCTAssertEqual(Money.validateLocal("x", eurRange: 5...2000, in: cad), .failure(.unreadable))
    }

    func testAboutPricesSaysEstimatesFixedRateAndDate() {
        Money.setCurrent("CAD")
        let text = Money.aboutPricesText
        XCTAssertTrue(text.contains("average estimated prices, not live store prices"), text)
        XCTAssertTrue(text.contains("fixed rate"), text)
        XCTAssertTrue(text.contains(Money.ratesDateText), text)
        XCTAssertTrue(text.contains("CAD"), text)
        XCTAssertEqual(Money.ratesDateText, "27 November 2026")
    }

    func testShopMessagesUseTheChosenCurrency() {
        Money.setCurrent("CAD")
        let message = FallbackData.cartMessage(itemCount: 2, total: 10, budget: 60)
        XCTAssertTrue(message.contains(Money.format(eur: 60)), message)
        XCTAssertFalse(message.contains("€"), message)
    }

    // MARK: - F3 targets

    func testTypedCalorieGoalReplacesTheRecommendation() {
        var profile = UserProfile(weight: 70, height: 175, age: 30, gender: .male,
                                  activityLevel: .moderatelyActive, weightGoal: .maintain)
        BMRCalculator.populate(profile: &profile)
        let recommended = profile.dailyCalorieGoal
        XCTAssertGreaterThan(recommended, 0)

        TargetOverrides(calories: 1800).save()
        BMRCalculator.populate(profile: &profile)
        XCTAssertEqual(profile.dailyCalorieGoal, 1800)
        let bmr = BMRCalculator.response(for: profile, isKeto: false)
        XCTAssertEqual(bmr.calories(forGoal: "maintain"), 1800, "the planner's target")
        XCTAssertEqual(bmr.macros.protein, BMRCalculator.recommendedMacroTargets(calories: 1800).proteinG)

        TargetOverrides.clear()
        BMRCalculator.populate(profile: &profile)
        XCTAssertEqual(profile.dailyCalorieGoal, recommended, "Use recommended goes back")
    }

    func testTypedMacrosReplaceOnlyThoseMacros() {
        TargetOverrides(proteinG: 180).save()
        let m = BMRCalculator.macroTargets(calories: 2000)
        let usual = BMRCalculator.recommendedMacroTargets(calories: 2000)
        XCTAssertEqual(m.proteinG, 180)
        XCTAssertEqual(m.carbsG, usual.carbsG)
        XCTAssertEqual(m.fatG, usual.fatG)
        TargetOverrides.clear()
        XCTAssertEqual(BMRCalculator.macroTargets(calories: 2000).proteinG, usual.proteinG)
    }

    func testOverridesAreClampedAndEmptyAfterClear() {
        TargetOverrides(calories: 200, proteinG: 5000, carbsG: nil, fatG: 0).save()
        let loaded = TargetOverrides.load()
        XCTAssertEqual(loaded.calories, TargetOverrides.calorieRange.lowerBound)
        XCTAssertEqual(loaded.proteinG, TargetOverrides.macroRange.upperBound)
        XCTAssertNil(loaded.carbsG)
        XCTAssertNil(loaded.fatG)
        TargetOverrides.clear()
        XCTAssertTrue(TargetOverrides.load().isEmpty)
        XCTAssertEqual(TargetOverrides.kcal(protein: 100, carbs: 200, fat: 50), 1650)
    }

    func testSavingTargetsReachesHomeAndUseRecommendedResets() {
        let vm = ProfileViewModel()
        vm.load(profile: AppState.shared.userProfile, preferences: [], favorites: [])
        let recommended = vm.recommendedCalories
        vm.setTargets(TargetOverrides(calories: 2345, proteinG: 150))
        XCTAssertEqual(AppState.shared.userProfile.dailyCalorieGoal, 2345)
        XCTAssertEqual(AppState.shared.bmrData?.macros.protein, 150)
        XCTAssertEqual(HomeViewModel().goal, 2345, "Home's calorie ring uses the typed goal")
        vm.useRecommendedTargets()
        XCTAssertTrue(TargetOverrides.load().isEmpty)
        XCTAssertEqual(AppState.shared.userProfile.dailyCalorieGoal, recommended)
        XCTAssertEqual(AppState.shared.bmrData?.macros.protein,
                       BMRCalculator.recommendedMacroTargets(calories: recommended).proteinG)
    }

    // MARK: - F2 photo

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testPhotoIsSavedSquareSmallAndLocalThenRemoved() throws {
        let dir = try tempDirectory()
        let store = ProfilePhotoStore(directory: dir)
        XCTAssertFalse(store.hasPhoto)
        XCTAssertTrue(store.save(image(width: 2000, height: 1200)))
        XCTAssertTrue(store.hasPhoto)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        let saved = try XCTUnwrap(UIImage(contentsOfFile: store.fileURL.path))
        XCTAssertEqual(saved.size.width, saved.size.height)
        XCTAssertLessThanOrEqual(saved.size.width, ProfilePhotoStore.maxPixels)
        let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "not in iCloud backups")

        // A new launch finds it again.
        XCTAssertTrue(ProfilePhotoStore(directory: dir).hasPhoto)

        store.remove()
        XCTAssertFalse(store.hasPhoto)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertFalse(ProfilePhotoStore(directory: dir).hasPhoto)
    }

    func testSmallPhotosAreNotScaledUp() {
        let square = ProfilePhotoStore.squared(image(width: 120, height: 300), side: ProfilePhotoStore.maxPixels)
        XCTAssertEqual(square.size.width, 120)
        XCTAssertEqual(square.size.height, 120)
    }

    func testInitialsForTheAvatar() {
        XCTAssertEqual(ProfileAvatar.initials(for: "urte kazlauskaite"), "UK")
        XCTAssertEqual(ProfileAvatar.initials(for: "Urte Kazlauskaite", max: 1), "U")
        XCTAssertEqual(ProfileAvatar.initials(for: "  "), "")
    }
}
