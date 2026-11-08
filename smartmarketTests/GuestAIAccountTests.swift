import XCTest
@testable import smartmarket

private final class GuestAccountProtocol: URLProtocol {
    static var paths: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.paths.append(path)
        let usage: [String: Any] = ["limit": 30, "used": 0, "remaining": 30, "resetsAt": "2099-01-01T00:00:00Z", "mealPlanCost": 5, "shortRequestCost": 1]
        let value: [String: Any]
        switch path {
        case "/api/auth/config": value = ["enabled": true, "guestEnabled": true, "appleEnabled": false]
        case "/api/auth/guest": value = ["token": String(repeating: "a", count: 64), "accountID": "guest-current", "expiresAt": "2099-01-01T00:00:00Z", "usage": usage]
        case "/api/ai/usage": value = usage
        default: value = [:]
        }
        let status = request.httpMethod == "DELETE" || path == "/api/auth/logout" ? 204 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: value))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class GuestAIAccountTests: XCTestCase {
    private let keys = ["aiGuestDeviceSecret_v1", "aiAppleSession_v1", "aiRetainedAccount_v1", "aiRetainedAccountIDs_v2", "aiUnknownLegacyAccount_v2", "aiRecoveredLegacyAccountID_v2"]
    private var backup: [String: Data] = [:]
    private var session: URLSession!
    override func setUp() async throws {
        for key in keys {
            backup[key] = KeychainHelper.load(key: key)
            KeychainHelper.delete(key: key)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GuestAccountProtocol.self]
        session = URLSession(configuration: config)
        GuestAccountProtocol.paths = []
    }
    override func tearDown() async throws {
        session.invalidateAndCancel()
        for key in keys {
            if let data = backup[key] { KeychainHelper.save(data, key: key) }
            else { KeychainHelper.delete(key: key) }
        }
        backup = [:]
    }
    func testGuestSessionWorksWithoutAppleAndRecoversAfterSignOut() async throws {
        let account = AIAccountService(session: session)
        await account.prepare()
        XCTAssertTrue(account.guestAvailable)
        XCTAssertFalse(account.canStartSignIn)
        await account.continueAsGuest()
        XCTAssertTrue(account.isGuest)
        XCTAssertTrue(account.isSignedIn)
        XCTAssertTrue(try account.authorization().hasPrefix("Bearer "))
        let secret = try XCTUnwrap(KeychainHelper.load(String.self, key: "aiGuestDeviceSecret_v1"))
        XCTAssertEqual(secret.count, 43)
        await account.signOut()
        XCTAssertFalse(account.isSignedIn)
        XCTAssertTrue(account.hasAccount)
        await account.continueAsGuest()
        XCTAssertEqual(KeychainHelper.load(String.self, key: "aiGuestDeviceSecret_v1"), secret)
        try await account.deleteAccountIfPresent()
        XCTAssertFalse(account.hasAccount)
        XCTAssertNil(KeychainHelper.load(String.self, key: "aiGuestDeviceSecret_v1"))
        XCTAssertFalse(GuestAccountProtocol.paths.contains("/api/auth/apple/challenge"))
    }
    func testDeletingGuestDoesNotForgetPreviouslyUsedAppleAccount() async throws {
        KeychainHelper.save(["apple-previous"], key: "aiRetainedAccountIDs_v2")
        KeychainHelper.save(true, key: "aiRetainedAccount_v1")
        let account = AIAccountService(session: session)
        await account.prepare()
        await account.continueAsGuest()
        do { try await account.deleteAccountIfPresent(); XCTFail("Must require handling the earlier Apple account") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Another AI account")) }
        XCTAssertEqual(KeychainHelper.load([String].self, key: "aiRetainedAccountIDs_v2"), ["apple-previous"])
        XCTAssertTrue(account.hasAccount)
        XCTAssertFalse(account.isSignedIn)
    }
    func testLegacySignedOutMarkerSurvivesGuestDeletion() async throws {
        KeychainHelper.save(true, key: "aiRetainedAccount_v1")
        let account = AIAccountService(session: session)
        await account.prepare()
        await account.continueAsGuest()
        do { try await account.deleteAccountIfPresent(); XCTFail("Must retain unresolved legacy account") }
        catch { XCTAssertTrue(error.localizedDescription.contains("older build")) }
        XCTAssertEqual(KeychainHelper.load(Bool.self, key: "aiUnknownLegacyAccount_v2"), true)
        XCTAssertTrue(account.hasAccount)
    }
    func testExpiredLegacyAppleSessionIsRetainedBeforeGuestReplacesIt() async throws {
        KeychainHelper.save(["token": String(repeating: "x", count: 64), "accountID": "expired-apple",
                             "expiresAt": "2000-01-01T00:00:00Z", "appleUserID": "previous-apple-user"], key: "aiAppleSession_v1")
        KeychainHelper.save(true, key: "aiRetainedAccount_v1")
        let account = AIAccountService(session: session)
        await account.prepare()
        XCTAssertFalse(account.isSignedIn)
        await account.continueAsGuest()
        do { try await account.deleteAccountIfPresent(); XCTFail("Expired Apple account must still be handled") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Another AI account")) }
        XCTAssertEqual(KeychainHelper.load([String].self, key: "aiRetainedAccountIDs_v2"), ["expired-apple"])
        XCTAssertTrue(account.hasAccount)
    }

}
