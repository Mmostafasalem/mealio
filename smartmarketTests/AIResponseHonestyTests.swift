import XCTest
@testable import smartmarket

private final class SyntheticAIProtocol: URLProtocol {
    static var resultHeader: String?
    static var received: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.received = request
        var headers = ["Content-Type": "application/json"]
        if let value = Self.resultHeader { headers["X-AI-Result"] = value }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"reply\":\"A real synthetic answer\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class AIResponseHonestyTests: XCTestCase {
    private let request = AgentChatRequest(message: "synthetic", history: [],
        userContext: AgentUserContext(goal: "maintain", targetCalories: 2000, caloriesConsumed: 0, favoriteFoods: []))

    private func withConsent(_ body: (URLSession) async throws -> Void) async rethrows {
        let keys = ["aiSharingConsent_v1", "ownerAISharingConsent_v1"]
        let values = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, values) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        UserDefaults.standard.set(true, forKey: keys[0])
        UserDefaults.standard.set(true, forKey: keys[1])
        SyntheticAIProtocol.received = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyntheticAIProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        try await body(session)
    }

    func testLegacyAndFallbackSuccessBodiesAreNotPresentedAsAI() async throws {
        try await withConsent { session in
            let api = APIService(session: session, authorization: { "Bearer synthetic" }, ownerConfiguration: nil)
            for result in [nil, "fallback", "unknown"] as [String?] {
                SyntheticAIProtocol.resultHeader = result
                do {
                    _ = try await api.agentChat(request)
                    XCTFail("A 200 fallback is not a verified AI response")
                } catch APIError.unverifiedAIResponse { }
            }
        }
    }

    func testVerifiedInferenceIsAccepted() async throws {
        try await withConsent { session in
            let api = APIService(session: session, authorization: { "Bearer synthetic" }, ownerConfiguration: nil)
            for source in ["online", "cached-online", "replayed-online"] {
                SyntheticAIProtocol.resultHeader = source
                let answer = try await api.agentChat(request)
                XCTAssertEqual(answer.reply, "A real synthetic answer")
            }
        }
    }

    func testOwnerTransportUsesSeparateCredentialAndConsent() async throws {
        try await withConsent { session in
            let owner = try XCTUnwrap(OwnerAITestConfiguration.resolve(info: [
                "OWNER_AI_BASE_URL": "https://owner.example.test",
                "OWNER_AI_TOKEN": String(repeating: "t", count: 48)], ownerBuild: true))
            let api = APIService(session: session, authorization: { throw AIAccountError.signInRequired }, ownerConfiguration: owner)
            UserDefaults.standard.set(false, forKey: "ownerAISharingConsent_v1")
            do {
                _ = try await api.agentChat(request)
                XCTFail("Normal cloud consent must not authorize a new destination")
            } catch APIError.aiConsentRequired { }
            XCTAssertNil(SyntheticAIProtocol.received)
            UserDefaults.standard.set(true, forKey: "ownerAISharingConsent_v1")
            SyntheticAIProtocol.resultHeader = "online"
            _ = try await api.agentChat(request)
            let sent = try XCTUnwrap(SyntheticAIProtocol.received)
            XCTAssertEqual(sent.url?.host, "owner.example.test")
            XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Owner-AI-Token"), owner.token)
            XCTAssertNil(sent.value(forHTTPHeaderField: "X-API-Key"))
            XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testOwnerConfigurationCannotActivateOutsideOwnerBuildOrOverCleartext() {
        let valid: [String: Any] = ["OWNER_AI_BASE_URL": "https://owner.example.test", "OWNER_AI_TOKEN": String(repeating: "t", count: 48)]
        XCTAssertNil(OwnerAITestConfiguration.resolve(info: valid, ownerBuild: false))
        for url in ["http://owner.example.test", "https://user:pass@owner.example.test", "https://owner.example.test?token=hidden", "https://owner.example.test/path"] {
            var info = valid; info["OWNER_AI_BASE_URL"] = url
            XCTAssertNil(OwnerAITestConfiguration.resolve(info: info, ownerBuild: true))
        }
    }
}
