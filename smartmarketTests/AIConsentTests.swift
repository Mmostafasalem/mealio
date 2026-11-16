import XCTest
@testable import smartmarket

private final class RejectNetworkProtocol: URLProtocol {
    static var requests = 0
    static var lastAuthorization: String?
    static var lastRequestKey: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        Self.lastRequestKey = request.value(forHTTPHeaderField: "Idempotency-Key")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@MainActor
final class AIConsentTests: XCTestCase {
    func testChatWithConsentReachesTheConfiguredTransport() async throws {
        let key = "aiSharingConsent_v1"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)
        RejectNetworkProtocol.requests = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RejectNetworkProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = APIService(session: session, authorization: { "Bearer test-session" })
        let context = AgentUserContext(goal: "maintain", targetCalories: 2000,
                                       caloriesConsumed: 0, favoriteFoods: [])
        do {
            _ = try await api.agentChat(AgentChatRequest(message: "test", history: [], userContext: context))
            XCTFail("The test transport intentionally reports offline")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
            XCTAssertEqual(RejectNetworkProtocol.requests, 1)
            XCTAssertEqual(RejectNetworkProtocol.lastAuthorization, "Bearer test-session")
            XCTAssertNotNil(RejectNetworkProtocol.lastRequestKey.flatMap(UUID.init(uuidString:)))
        }
    }

    func testConsentDoesNotBypassSignIn() async throws {
        let key = "aiSharingConsent_v1"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)
        RejectNetworkProtocol.requests = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RejectNetworkProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = APIService(session: session, authorization: { throw AIAccountError.signInRequired })
        let context = AgentUserContext(goal: "maintain", targetCalories: 2000,
                                       caloriesConsumed: 0, favoriteFoods: [])
        do {
            _ = try await api.agentChat(AgentChatRequest(message: "test", history: [], userContext: context))
            XCTFail("Consent must not bypass account authentication")
        } catch AIAccountError.signInRequired {
            XCTAssertEqual(RejectNetworkProtocol.requests, 0)
        }
    }

    func testSignedOutAccountMustBeReauthenticatedBeforeDeleteAllData() async throws {
        let markerKey = "aiRetainedAccount_v1"
        let sessionKey = "aiAppleSession_v1"
        let oldMarker = KeychainHelper.load(key: markerKey)
        let oldSession = KeychainHelper.load(key: sessionKey)
        defer {
            KeychainHelper.delete(key: markerKey)
            KeychainHelper.delete(key: sessionKey)
            if let oldMarker { KeychainHelper.save(oldMarker, key: markerKey) }
            if let oldSession { KeychainHelper.save(oldSession, key: sessionKey) }
        }
        KeychainHelper.delete(key: sessionKey)
        KeychainHelper.save(true, key: markerKey)
        let account = AIAccountService()
        XCTAssertTrue(account.hasAccount)
        XCTAssertFalse(account.isSignedIn)
        do {
            try await account.deleteAccountIfPresent()
            XCTFail("Retained online account must not be silently skipped")
        } catch AIAccountError.signInRequired {
            XCTAssertTrue(account.hasAccount)
        }
    }

    func testChatWithoutConsentRejectsBeforeNetworkRequest() async throws {
        let key = "aiSharingConsent_v1"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(false, forKey: key)
        RejectNetworkProtocol.requests = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RejectNetworkProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = APIService(session: session)
        let context = AgentUserContext(goal: "maintain", targetCalories: 2000,
                                       caloriesConsumed: 0, favoriteFoods: [])
        do {
            _ = try await api.agentChat(AgentChatRequest(message: "test", history: [], userContext: context))
            XCTFail("AI request was allowed without permission")
        } catch APIError.aiConsentRequired {
            XCTAssertEqual(RejectNetworkProtocol.requests, 0)
        }
    }
}
