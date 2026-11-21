import Foundation
import Observation
import AuthenticationServices
import Security

struct AIAllowance: Codable {
    let limit: Int
    let used: Int
    let remaining: Int
    let resetsAt: String
    let mealPlanCost: Int
    let shortRequestCost: Int
    /// What reading a meal photo costs; older servers don't send it.
    var photoCost: Int? = nil
    var resetDate: Date? { ISO8601DateFormatter().date(from: resetsAt) }
}

enum AIAccountError: LocalizedError {
    case signInRequired, unavailable, quota(String?), sharedCapacity, message(String)
    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in or continue as a guest in Profile to use online AI. Local features still work."
        case .unavailable: return "Online AI sign-in is currently unavailable. Local features still work."
        case .sharedCapacity: return "Online AI is busy. Your personal allowance is unchanged. Please try again later."
        case .quota(let reset):
            if let reset, let date = ISO8601DateFormatter().date(from: reset) {
                return "Your AI allowance resets \(date.formatted(date: .abbreviated, time: .shortened)). Local features still work."
            }
            return "Your daily AI allowance is used up. Local features still work."
        case .message(let text): return text
        }
    }
}

@MainActor @Observable
final class AIAccountService {
    static let shared = AIAccountService()
    private static let unknownLegacyKey = "aiUnknownLegacyAccount_v2"
    private static let recoveredLegacyKey = "aiRecoveredLegacyAccountID_v2"
    private static let retainedAccountsKey = "aiRetainedAccountIDs_v2"
    private static let guestKey = "aiGuestDeviceSecret_v1"
    private static let sessionKey = "aiAppleSession_v1"
    private static let retainedAccountKey = "aiRetainedAccount_v1"

    private struct StoredSession: Codable {
        let token: String
        let accountID: String
        let expiresAt: String
        let appleUserID: String
    }
    private struct Configuration: Decodable { let enabled: Bool; let guestEnabled: Bool?; let appleEnabled: Bool? }
    private struct Challenge: Decodable { let id: String; let nonce: String; let expiresAt: String }
    private struct Login: Decodable {
        let token: String; let accountID: String; let expiresAt: String; let usage: AIAllowance
    }
    private struct LoginRequest: Encodable {
        let identityToken: String; let authorizationCode: String; let challengeID: String
    }
    private struct Failure: Decodable { let error: String; let code: String? }

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    private var stored: StoredSession? = KeychainHelper.load(StoredSession.self, key: sessionKey)
    private var challenge: Challenge?
    /// When the current challenge stops being usable, by this iPhone's clock.
    private var challengeExpires: Date?
    @ObservationIgnored private var challengeRefresh: Task<Void, Never>?
    @ObservationIgnored private var challengeAutoRefreshes = 0
    @ObservationIgnored private var isAutoRefreshingChallenge = false
    /// The challenge the Apple sign-in sheet was opened with, until the sheet reports back.
    @ObservationIgnored private var signInSheetChallengeID: String?
    /// Stop offering a challenge this long before the server drops it, so a sign-in
    /// started at the last moment isn't refused.
    private static let challengeMargin: TimeInterval = 30
    /// How often an expired challenge is replaced without anyone asking, before the
    /// screen asks for a tap instead.
    private static let maxChallengeAutoRefreshes = 2
    private var generation = UUID()
    var allowance: AIAllowance?
    var isAvailable = false
    var guestAvailable = false
    var appleAvailable = false
    var isGuest: Bool { stored?.appleUserID.isEmpty == true }

    /// Whether the app shows online AI at all (chat, AI recipes, the AI section in Profile):
    /// the backend said it's switched on (remembered from the last answer), the person is
    /// signed in, or it's the owner's private test build. While the hosted service runs
    /// without AI, nobody is offered something that can't work.
    static let offeredKey = "onlineAIOffered_v1"
    var offersOnlineAI: Bool {
        OwnerAITestConfiguration.current != nil || isAvailable || isSignedIn || UserDefaults.standard.bool(forKey: Self.offeredKey)
    }
    var isWorking = false
    var message: String?
    private var retainedAccountIDs: [String] { KeychainHelper.load([String].self, key: Self.retainedAccountsKey) ?? [] }
    var hasAccount: Bool { stored != nil || !retainedAccountIDs.isEmpty || KeychainHelper.load(Bool.self, key: Self.retainedAccountKey) == true }

    private func preserveLegacyAccount() {
        if let stored {
            rememberAccount(stored.accountID, recoveringApple: !stored.appleUserID.isEmpty)
            return
        }
        if retainedAccountIDs.isEmpty,
           KeychainHelper.load(Bool.self, key: Self.retainedAccountKey) == true {
            KeychainHelper.save(true, key: Self.unknownLegacyKey)
        }
    }

    private func rememberAccount(_ id: String, recoveringApple: Bool = false) {
        var ids = retainedAccountIDs
        if !ids.contains(id) { ids.append(id) }
        KeychainHelper.save(ids, key: Self.retainedAccountsKey)
        if recoveringApple, KeychainHelper.load(Bool.self, key: Self.unknownLegacyKey) == true {
            KeychainHelper.save(id, key: Self.recoveredLegacyKey)
        }
        KeychainHelper.save(true, key: Self.retainedAccountKey)
    }
    var isSignedIn: Bool {
        guard let stored, let expires = ISO8601DateFormatter().date(from: stored.expiresAt) else { return false }
        return expires > Date()
    }
    /// A challenge the server still accepts: it lasts five minutes there.
    private var hasLiveChallenge: Bool {
        guard challenge != nil, let challengeExpires else { return false }
        return challengeExpires > Date()
    }
    var canStartSignIn: Bool { isAvailable && appleAvailable && BuildCapabilities.supportsAppleServices && hasLiveChallenge && !isWorking }

    /// Remembers when `challenge` runs out and replaces it when it does, so the
    /// sign-in button never starts a sign-in the server would refuse.
    private func scheduleChallengeRefresh() {
        challengeRefresh?.cancel()
        challengeRefresh = nil
        guard let challenge else { challengeExpires = nil; return }
        // The server's time is trusted only when it makes sense on this iPhone's
        // clock; a wrong clock must not make every challenge look expired.
        let stated = ISO8601DateFormatter().date(from: challenge.expiresAt)?.timeIntervalSinceNow ?? 0
        let lifetime = stated > Self.challengeMargin && stated <= 600 ? stated : 270
        let usable = max(lifetime - Self.challengeMargin, 5)
        challengeExpires = Date().addingTimeInterval(usable)
        let id = challenge.id
        challengeRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(usable))
            guard !Task.isCancelled, let self, self.challenge?.id == id else { return }
            // A sign-in sheet that is open was started with this challenge: leave it, and
            // let complete(_:) deal with the outcome.
            guard self.signInSheetChallengeID != id else { return }
            await self.replaceExpiredChallenge()
        }
    }

    private func replaceExpiredChallenge() async {
        challenge = nil
        challengeExpires = nil
        guard !isSignedIn else { return }
        guard !isWorking, challengeAutoRefreshes < Self.maxChallengeAutoRefreshes else {
            if !isWorking { message = "Sign-in setup timed out. Tap Retry sign-in setup to continue." }
            return
        }
        challengeAutoRefreshes += 1
        isAutoRefreshingChallenge = true
        await prepare()
        isAutoRefreshingChallenge = false
    }

    func authorization() throws -> String {
        guard isSignedIn, let stored else { throw AIAccountError.signInRequired }
        return "Bearer \(stored.token)"
    }

    func prepare() async {
        if OwnerAITestConfiguration.current != nil {
            await AIConnectionState.shared.checkOwnerConnection()
            isAvailable = false
            challenge = nil
            message = AIConnectionState.shared.detail
            return
        }
        guard !isWorking else { return }
        var expected = generation
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try await request("/api/auth/config")
            guard generation == expected else { return }
            let config = try JSONDecoder().decode(Configuration.self, from: data)
            isAvailable = config.enabled
            UserDefaults.standard.set(config.enabled, forKey: Self.offeredKey)
            guestAvailable = config.enabled && config.guestEnabled == true
            appleAvailable = config.enabled && (config.appleEnabled ?? true) && BuildCapabilities.supportsAppleServices
            guard isAvailable else { message = AIAccountError.unavailable.localizedDescription; return }
            if isSignedIn {
                if let stored, !isGuest {
                    let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: stored.appleUserID)
                    guard generation == expected else { return }
                    if state == .revoked || state == .notFound { clearLocalSession() }
                }
                if isSignedIn {
                    do { try await refreshAllowance(); return }
                    catch AIAccountError.signInRequired where stored == nil {
                        // The server no longer accepts this session, so it was cleared
                        // (see handleRejectedSession). Carry on and offer sign-in again.
                        expected = generation
                    }
                }
            }
            guard appleAvailable else {
                challenge = nil
                scheduleChallengeRefresh()
                message = guestAvailable ? "Continue as a guest to use AI on this device. Apple sign-in is unavailable in this build or service." : AIAccountError.unavailable.localizedDescription
                return
            }
            let raw = try await request("/api/auth/apple/challenge")
            guard generation == expected else { return }
            challenge = try JSONDecoder().decode(Challenge.self, from: raw)
            if !isAutoRefreshingChallenge { challengeAutoRefreshes = 0 }
            scheduleChallengeRefresh()
            message = nil
        } catch {
            guard generation == expected else { return }
            message = error.localizedDescription
        }
    }

    func continueAsGuest() async {
        guard guestAvailable, !isWorking else { return }
        preserveLegacyAccount()
        let expected = generation
        isWorking = true
        defer { isWorking = false }
        do {
            let secret: String
            if let saved = KeychainHelper.load(String.self, key: Self.guestKey) { secret = saved }
            else {
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                    throw AIAccountError.message("Could not create a secure guest session. Please retry.")
                }
                secret = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                KeychainHelper.save(secret, key: Self.guestKey)
                guard KeychainHelper.load(String.self, key: Self.guestKey) == secret else {
                    throw AIAccountError.message("Unlock your iPhone to securely save guest access, then retry.")
                }
            }
            let body = try JSONEncoder().encode(["deviceSecret": secret])
            let data = try await request("/api/auth/guest", method: "POST", body: body)
            guard generation == expected else { return }
            let signed = try JSONDecoder().decode(Login.self, from: data)
            let session = StoredSession(token: signed.token, accountID: signed.accountID,
                                        expiresAt: signed.expiresAt, appleUserID: "")
            rememberAccount(signed.accountID)
            KeychainHelper.save(session, key: Self.sessionKey)
            guard KeychainHelper.load(StoredSession.self, key: Self.sessionKey)?.token == signed.token else {
                _ = try? await request("/api/auth/logout", method: "POST", bearer: signed.token)
                throw AIAccountError.message("Could not securely save guest access. Unlock your iPhone and retry.")
            }
            stored = session; allowance = signed.usage; challenge = nil; message = nil
        } catch { if generation == expected { message = error.localizedDescription } }
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        // No name or email is requested. Apple user identity is used only for the allowance.
        request.requestedScopes = []
        request.nonce = challenge?.nonce
        signInSheetChallengeID = challenge?.id
        challengeAutoRefreshes = 0
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        signInSheetChallengeID = nil
        guard !isWorking else { return }
        preserveLegacyAccount()
        let expected = generation
        isWorking = true
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identity = credential.identityToken, let code = credential.authorizationCode,
                  let identityText = String(data: identity, encoding: .utf8),
                  let codeText = String(data: code, encoding: .utf8), let challenge else {
                throw AIAccountError.message("Sign-in could not finish. Please try again.")
            }
            let body = try JSONEncoder().encode(LoginRequest(identityToken: identityText,
                authorizationCode: codeText, challengeID: challenge.id))
            let data = try await request("/api/auth/apple", method: "POST", body: body)
            guard generation == expected else { isWorking = false; return }
            let signed = try JSONDecoder().decode(Login.self, from: data)
            let session = StoredSession(token: signed.token, accountID: signed.accountID,
                                        expiresAt: signed.expiresAt, appleUserID: credential.user)
            rememberAccount(signed.accountID, recoveringApple: true)
            KeychainHelper.save(session, key: Self.sessionKey)
            guard KeychainHelper.load(StoredSession.self, key: Self.sessionKey)?.token == session.token else {
                _ = try? await request("/api/auth/logout", method: "POST", bearer: signed.token)
                throw AIAccountError.message("Could not securely save sign-in. Unlock your iPhone and retry.")
            }
            stored = session; allowance = signed.usage; self.challenge = nil; message = nil
        } catch {
            if generation == expected { message = error.localizedDescription; challenge = nil }
        }
        isWorking = false
        if !isSignedIn {
            let failure = message
            await prepare()
            if let failure { message = failure }
        }
    }

    func refreshAllowance() async throws {
        let expected = stored?.token
        let data = try await request("/api/ai/usage", authenticated: true)
        guard stored?.token == expected else { return }
        allowance = try JSONDecoder().decode(AIAllowance.self, from: data)
    }

    func acceptHeaders(_ response: HTTPURLResponse) {
        guard let stored, response.value(forHTTPHeaderField: "X-AI-Account") == stored.accountID,
              let limit = response.value(forHTTPHeaderField: "X-AI-Limit").flatMap(Int.init),
              let left = response.value(forHTTPHeaderField: "X-AI-Remaining").flatMap(Int.init),
              let reset = response.value(forHTTPHeaderField: "X-AI-Reset") else { return }
        allowance = AIAllowance(limit: limit, used: max(0, limit-left), remaining: max(0, left),
                                resetsAt: reset, mealPlanCost: 5, shortRequestCost: 1,
                                photoCost: allowance?.photoCost)
        if response.value(forHTTPHeaderField: "X-AI-Result") == "fallback" {
            // The service keeps 1 credit when the AI answered but the answer was unusable.
            message = response.value(forHTTPHeaderField: "X-AI-Fallback") == "unusable-output"
                ? "Online AI couldn't write a usable answer. 1 credit was used."
                : "Online AI was unavailable. No credits were used."
        }
    }

    func signOut() async {
        // The session is cleared just below either way, so a refusal needs no extra handling.
        if isSignedIn { _ = try? await request("/api/auth/logout", method: "POST", authenticated: true, recoverRejectedSession: false) }
        clearLocalSession()
        await prepare()
    }

    func deleteAccountIfPresent() async throws {
        guard !isWorking else { throw AIAccountError.message("Account setup is running. Wait for it to finish, then retry deletion.") }
        guard hasAccount else { return }
        guard isSignedIn, let accountID = stored?.accountID else { throw AIAccountError.signInRequired }
        _ = try await request("/api/auth/account", method: "DELETE", authenticated: true)
        if KeychainHelper.load(String.self, key: Self.recoveredLegacyKey) == accountID {
            KeychainHelper.delete(key: Self.unknownLegacyKey)
            KeychainHelper.delete(key: Self.recoveredLegacyKey)
        }
        let remaining = retainedAccountIDs.filter { $0 != accountID }
        KeychainHelper.save(remaining, key: Self.retainedAccountsKey)
        guard KeychainHelper.load([String].self, key: Self.retainedAccountsKey) == remaining else {
            throw AIAccountError.message("Could not securely update deletion progress. Unlock your iPhone and retry.")
        }
        clearLocalSession(retainAccount: false)
        guard remaining.isEmpty, KeychainHelper.load(Bool.self, key: Self.unknownLegacyKey) != true else {
            KeychainHelper.save(true, key: Self.retainedAccountKey)
            message = "This AI account was deleted. Another AI account was used on this device. If it was from an older build, use the original Apple account. Sign in to that account and retry Delete All Data to finish removing it. Your local data is kept until all accounts are handled."
            throw AIAccountError.message(message!)
        }
        KeychainHelper.delete(key: Self.retainedAccountKey)
        KeychainHelper.delete(key: Self.retainedAccountsKey)
        KeychainHelper.delete(key: Self.guestKey)
    }

    func clearLocalSession(retainAccount: Bool = true) {
        if retainAccount, let stored { rememberAccount(stored.accountID) }
        generation = UUID()
        stored = nil; allowance = nil; challenge = nil; message = nil
        challengeExpires = nil; challengeAutoRefreshes = 0
        challengeRefresh?.cancel(); challengeRefresh = nil
        KeychainHelper.delete(key: Self.sessionKey)
    }

    /// For "erase this iPhone's data anyway", when the server account could not be deleted.
    /// An Apple account is still remembered, so a later Delete All Data asks the person to
    /// sign in and finish deleting it. A guest account is forgotten together with its device
    /// secret: without the secret nobody can sign in to it again, so remembering it would
    /// block every later deletion. The server removes an unused guest account on its own.
    func clearLocalSessionForLocalErase() {
        if let stored {
            if stored.appleUserID.isEmpty {
                let remaining = retainedAccountIDs.filter { $0 != stored.accountID }
                if remaining.isEmpty {
                    KeychainHelper.delete(key: Self.retainedAccountsKey)
                    if KeychainHelper.load(Bool.self, key: Self.unknownLegacyKey) != true {
                        KeychainHelper.delete(key: Self.retainedAccountKey)
                    }
                } else {
                    KeychainHelper.save(remaining, key: Self.retainedAccountsKey)
                }
                KeychainHelper.delete(key: Self.guestKey)
            } else {
                rememberAccount(stored.accountID)
            }
        }
        clearLocalSession(retainAccount: false)
    }

    /// The server answered 401 to a call made with this session: it expired there, was
    /// signed out, or the account is gone. Forget it on this iPhone and get sign-in ready
    /// again, so the app stops presenting a session nothing accepts. `authorization` is the
    /// header value the refused call was sent with; a session replaced since then is kept.
    func handleRejectedSession(authorization: String) async {
        guard let stored, authorization == "Bearer \(stored.token)" else { return }
        clearLocalSession()
        // While prepare() is already running it notices the cleared session itself.
        if !isWorking { await prepare() }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         authenticated: Bool = false, bearer: String? = nil,
                         recoverRejectedSession: Bool = true) async throws -> Data {
        guard let url = URL(string: Constants.API.baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !Constants.API.appKey.isEmpty { request.setValue(Constants.API.appKey, forHTTPHeaderField: "X-API-Key") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let sessionHeader: String? = try authenticated ? authorization() : nil
        if let sessionHeader { request.setValue(sessionHeader, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 || http.statusCode == 503 { throw AIAccountError.unavailable }
            if http.statusCode == 401 {
                // Only the account service's own refusal counts, not a 401 from anything in between.
                if recoverRejectedSession, let sessionHeader,
                   http.value(forHTTPHeaderField: "X-AI-Error") == "ai_sign_in_required" {
                    await handleRejectedSession(authorization: sessionHeader)
                }
                throw authenticated || bearer != nil ? AIAccountError.signInRequired : AIAccountError.unavailable
            }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw AIAccountError.message(failure?.error ?? "Could not complete sign-in. Please try again.")
        }
        return data
    }
}
