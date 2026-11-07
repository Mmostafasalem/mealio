import XCTest
@testable import smartmarket

/// Explicitly selected only in the private owner build, with a synthetic prompt.
/// Normal CI has no private configuration and skips this live integration check.
@MainActor
final class OwnerAILiveTests: XCTestCase {
    func testPinnedConnectionAndRealInferenceWhenConfigured() async throws {
        guard let config = OwnerAITestConfiguration.current else {
            throw XCTSkip("Private owner AI connection is not configured in this build")
        }
        AppState.shared.agentLoop.stop()
        let consentKey = "ownerAISharingConsent_v1"
        let previous = UserDefaults.standard.object(forKey: consentKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: consentKey) }
            else { UserDefaults.standard.removeObject(forKey: consentKey) }
        }
        UserDefaults.standard.set(true, forKey: consentKey)
        let api = APIService(ownerConfiguration: config)
        let request = AgentChatRequest(message: "Connection test only: reply with exactly MEALIO_NATIVE_AI_OK.", history: [],
            userContext: AgentUserContext(goal: "maintain", targetCalories: 2000, caloriesConsumed: 0, favoriteFoods: []))
        let answer = try await api.agentChat(request)
        XCTAssertTrue(answer.reply.contains("MEALIO_NATIVE_AI_OK"), "Synthetic instruction must be followed by the actual provider")
    }
}
