import XCTest
@testable import smartmarket

@MainActor
final class OnboardingPersistenceTests: XCTestCase {
    func testFinishingOfflineSetupPersistsCalorieTargetsForTheAgent() {
        let domain = Bundle.main.bundleIdentifier ?? "com.mostafa.mealio"
        let saved = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let profile = KeychainHelper.load(key: Constants.Storage.userProfile)
        let bmr = KeychainHelper.load(key: Constants.Storage.bmrResponse)
        defer {
            AppState.shared.agentLoop.stop()
            UserDefaults.standard.setPersistentDomain(saved, forName: domain)
            if let profile { KeychainHelper.save(profile, key: Constants.Storage.userProfile) }
            else { KeychainHelper.delete(key: Constants.Storage.userProfile) }
            if let bmr { KeychainHelper.save(bmr, key: Constants.Storage.bmrResponse) }
            else { KeychainHelper.delete(key: Constants.Storage.bmrResponse) }
            AppState.shared.reloadStoredData()
        }
        AppState.shared.bmrData = nil
        KeychainHelper.delete(key: Constants.Storage.bmrResponse)
        let vm = OnboardingViewModel()
        vm.favoriteFoodIDs = Set(CatalogItem.all.prefix(5).map(\.id))
        vm.finish()
        XCTAssertGreaterThan(AppState.shared.userProfile.dailyCalorieGoal, 1200)
        XCTAssertNotNil(AppState.shared.bmrData, "Offline onboarding must initialize the agent's calorie targets")
        XCTAssertNotNil(KeychainHelper.load(BMRResponse.self, key: Constants.Storage.bmrResponse))
    }
}
