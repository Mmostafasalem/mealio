import XCTest
@testable import smartmarket

private final class RejectNetworkProtocol: URLProtocol {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
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
        let api = APIService(session: session)
        let context = AgentUserContext(goal: "maintain", targetCalories: 2000,
                                       caloriesConsumed: 0, favoriteFoods: [])
        do {
            _ = try await api.agentChat(AgentChatRequest(message: "test", history: [], userContext: context))
            XCTFail("The test transport intentionally reports offline")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
            XCTAssertEqual(RejectNetworkProtocol.requests, 1)
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
