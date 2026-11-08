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
    private var generation = UUID()
    var allowance: AIAllowance?
    var isAvailable = false
    var guestAvailable = false
    var appleAvailable = false
    var isGuest: Bool { stored?.appleUserID.isEmpty == true }
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
    var canStartSignIn: Bool { isAvailable && appleAvailable && BuildCapabilities.supportsAppleServices && challenge != nil && !isWorking }

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
        let expected = generation
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try await request("/api/auth/config")
            guard generation == expected else { return }
            let config = try JSONDecoder().decode(Configuration.self, from: data)
            isAvailable = config.enabled
            guestAvailable = config.enabled && config.guestEnabled == true
            appleAvailable = config.enabled && (config.appleEnabled ?? true) && BuildCapabilities.supportsAppleServices
            guard isAvailable else { message = AIAccountError.unavailable.localizedDescription; return }
            if isSignedIn {
                if let stored, !isGuest {
                    let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: stored.appleUserID)
                    guard generation == expected else { return }
                    if state == .revoked || state == .notFound { clearLocalSession() }
                }
                if isSignedIn { try await refreshAllowance(); return }
            }
            guard appleAvailable else {
                challenge = nil
                message = guestAvailable ? "Continue as a guest to use AI on this device. Apple sign-in is unavailable in this build or service." : AIAccountError.unavailable.localizedDescription
                return
            }
            let raw = try await request("/api/auth/apple/challenge")
            guard generation == expected else { return }
            challenge = try JSONDecoder().decode(Challenge.self, from: raw)
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
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
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
                                resetsAt: reset, mealPlanCost: 5, shortRequestCost: 1)
        if response.value(forHTTPHeaderField: "X-AI-Result") == "fallback" {
            message = "Online AI was unavailable. No credits were used."
        }
    }

    func signOut() async {
        if isSignedIn { _ = try? await request("/api/auth/logout", method: "POST", authenticated: true) }
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
        KeychainHelper.delete(key: Self.sessionKey)
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         authenticated: Bool = false, bearer: String? = nil) async throws -> Data {
        guard let url = URL(string: Constants.API.baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !Constants.API.appKey.isEmpty { request.setValue(Constants.API.appKey, forHTTPHeaderField: "X-API-Key") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if authenticated { request.setValue(try authorization(), forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 || http.statusCode == 503 { throw AIAccountError.unavailable }
            if http.statusCode == 401 { throw authenticated || bearer != nil ? AIAccountError.signInRequired : AIAccountError.unavailable }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw AIAccountError.message(failure?.error ?? "Could not complete sign-in. Please try again.")
        }
        return data
    }
}
