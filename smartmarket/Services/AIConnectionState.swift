import Foundation
import Observation

@MainActor @Observable
final class AIConnectionState {
    static let shared = AIConnectionState()
    private(set) var ownerReady = false
    private(set) var isChecking = false
    private(set) var detail: String?

    var modeLabel: String {
        if OwnerAITestConfiguration.current != nil {
            return ownerReady ? "AI on your Mac" : "Mac AI disconnected"
        }
        return AIAccountService.shared.isAvailable ? "Online AI ready" : "Local guide"
    }

    func checkOwnerConnection() async {
        guard let config = OwnerAITestConfiguration.current, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            var request = URLRequest(url: config.baseURL.appendingPathComponent("api/owner-ai/config"))
            request.timeoutInterval = 10
            request.setValue(config.token, forHTTPHeaderField: "X-Owner-AI-Token")
            let session = config.makeSession()
            defer { if config.certificateDER != nil { session.finishTasksAndInvalidate() } }
            let (data, response) = try await session.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  json?["enabled"] as? Bool == true,
                  json?["mode"] as? String == "owner-test" else { throw AIAccountError.unavailable }
            ownerReady = true
            detail = "Private AI testing on your Mac. Keep the Mac and its AI connection running."
        } catch {
            ownerReady = false
            detail = "Could not reach your Mac. Keep it awake with the AI testing service running, then retry."
        }
    }
}
