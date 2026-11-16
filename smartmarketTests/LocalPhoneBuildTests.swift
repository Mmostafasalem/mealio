import XCTest
@testable import smartmarket

@MainActor
final class LocalPhoneBuildTests: XCTestCase {
    func testAppleServicesMatchBuildConfiguration() async {
        #if MEALIO_LOCAL_PHONE_TEST
        let sync = PrivateSyncService.shared
        await sync.setEnabled(true)
        await sync.sync()
        XCTAssertFalse(sync.isAvailable)
        XCTAssertFalse(sync.isEnabled)
        XCTAssertTrue(sync.status.contains("phone-test build"))
        let account = AIAccountService.shared
        await account.prepare()
        XCTAssertFalse(account.isAvailable)
        XCTAssertFalse(account.canStartSignIn)
        XCTAssertThrowsError(try account.authorization())
        #else
        XCTAssertTrue(BuildCapabilities.supportsAppleServices)
        #endif
    }
}
