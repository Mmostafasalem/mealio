import Foundation
import Observation

/// The person's own AI key, as a last resort for phrases neither the rule book
/// nor Apple Intelligence could place.
///
/// Off unless they add a key, and usable only while signed in to their Nourlo
/// account. The key lives in the keychain (this device only) and is sent only
/// to the provider they chose, with the text of the phrase and nothing else:
/// no audio, no profile, no food log.
@MainActor
@Observable
final class VoiceAIKeyStore {
    static let shared = VoiceAIKeyStore()

    enum Provider: String, CaseIterable, Identifiable {
        case anthropic, openAI, custom

        var id: String { rawValue }

        var name: String {
            switch self {
            case .anthropic: return "Anthropic (Claude)"
            case .openAI: return "OpenAI"
            case .custom: return "Other (OpenAI-compatible)"
            }
        }

        /// Filled in for the person where there is a sensible one; they can change it.
        var defaultModel: String {
            switch self {
            case .anthropic: return "claude-opus-5-5"
            case .openAI, .custom: return ""
            }
        }

        var defaultBaseURL: String {
            switch self {
            case .anthropic: return "https://api.anthropic.com"
            case .openAI: return "https://api.openai.com/v1"
            case .custom: return ""
            }
        }
    }

    enum KeyError: LocalizedError, Equatable {
        case notSignedIn, notConfigured, badAddress, rejected(Int), declined, unreadable, network

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to your Nourlo account in Profile to use your own AI key."
            case .notConfigured: return "Add a key and a model name first."
            case .badAddress: return "The address must start with https://."
            case .rejected(401), .rejected(403): return "The provider rejected this key. Check that it was copied in full."
            case .rejected(404): return "The provider doesn't know this model name or address."
            case .rejected(429): return "The provider says this key has hit its limit. Try again later."
            case .rejected(let code): return "The provider returned an error (\(code))."
            case .declined: return "The model declined to answer."
            case .unreadable: return "The model's answer couldn't be read."
            case .network: return "Couldn't reach the provider. Check your connection."
            }
        }
    }

    private static let keychainKey = "voiceAIKey_v1"
    private static let providerKey = "voiceAIProvider_v1"
    private static let modelKey = "voiceAIModel_v1"
    private static let baseURLKey = "voiceAIBaseURL_v1"

    private(set) var provider: Provider
    private(set) var model: String
    private(set) var baseURL: String
    private(set) var hasKey: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let isSignedIn: @MainActor () -> Bool

    init(defaults: UserDefaults = .standard, session: URLSession? = nil, isSignedIn: (@MainActor () -> Bool)? = nil) {
        self.defaults = defaults
        self.isSignedIn = isSignedIn ?? { AIAccountService.shared.isSignedIn }
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration)
        }
        let provider = defaults.string(forKey: Self.providerKey).flatMap(Provider.init) ?? .anthropic
        self.provider = provider
        model = defaults.string(forKey: Self.modelKey) ?? provider.defaultModel
        baseURL = defaults.string(forKey: Self.baseURLKey) ?? provider.defaultBaseURL
        hasKey = KeychainHelper.load(key: Self.keychainKey) != nil
    }

    var signedIn: Bool { isSignedIn() }

    /// A key is saved, a model is named and the person is signed in.
    var isUsable: Bool { signedIn && hasKey && !model.isEmpty && Self.endpointBase(baseURL) != nil }

    private var key: String? {
        KeychainHelper.load(key: Self.keychainKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Saves the settings. An empty `key` keeps the one already stored.
    func save(provider: Provider, model: String, baseURL: String, key: String) throws {
        guard signedIn else { throw KeyError.notSignedIn }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.endpointBase(address) != nil else { throw KeyError.badAddress }
        guard !model.isEmpty, !key.isEmpty || hasKey else { throw KeyError.notConfigured }
        if !key.isEmpty, let data = key.data(using: .utf8) {
            KeychainHelper.save(data, key: Self.keychainKey)
            hasKey = KeychainHelper.load(key: Self.keychainKey) != nil
        }
        self.provider = provider
        self.model = model
        self.baseURL = address
        defaults.set(provider.rawValue, forKey: Self.providerKey)
        defaults.set(model, forKey: Self.modelKey)
        defaults.set(address, forKey: Self.baseURLKey)
    }

    /// Forgets the key and the settings.
    func remove() {
        KeychainHelper.delete(key: Self.keychainKey)
        [Self.providerKey, Self.modelKey, Self.baseURLKey].forEach(defaults.removeObject)
        hasKey = false
        provider = .anthropic
        model = provider.defaultModel
        baseURL = provider.defaultBaseURL
    }

    /// Only https addresses are accepted, so a key is never sent in the clear.
    static func endpointBase(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    // MARK: Asking the model

    func interpret(_ text: String) async throws -> VoiceAIReply {
        guard signedIn else { throw KeyError.notSignedIn }
        guard let key, !model.isEmpty, let base = Self.endpointBase(baseURL) else { throw KeyError.notConfigured }
        let request = try Self.request(provider: provider, base: base, model: model, key: key, text: text)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw KeyError.network
        }
        guard let http = response as? HTTPURLResponse else { throw KeyError.network }
        guard (200..<300).contains(http.statusCode) else { throw KeyError.rejected(http.statusCode) }
        return try Self.reply(from: data, provider: provider)
    }

    /// Models that can hand a declined request to another model inside the same call.
    private static let fallbackModels: Set<String> = ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

    static func request(provider: Provider, base: URL, model: String, key: String, text: String) throws -> URLRequest {
        let prompt = "The spoken request:\n\(text)"
        var request: URLRequest
        var body: [String: Any]
        switch provider {
        case .anthropic:
            request = URLRequest(url: base.appendingPathComponent("v1/messages"))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                // Room for the model's own reasoning as well as the short form.
                "max_tokens": 4000,
                "system": VoiceAIReply.instructions,
                "messages": [["role": "user", "content": prompt]],
                // The form is small and well specified: little reasoning needed.
                "output_config": [
                    "effort": "low",
                    "format": ["type": "json_schema", "schema": VoiceAIReply.schema],
                ],
            ]
            if fallbackModels.contains(model) {
                request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }
        case .openAI, .custom:
            request = URLRequest(url: base.appendingPathComponent("chat/completions"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let fields = "intent, foods (name, quantity, unit), meal, items, workout_kind, minutes, screen, exercise"
            body = [
                "model": model,
                "messages": [
                    ["role": "system", "content": VoiceAIReply.instructions + "\n\nReply with one JSON object with exactly these fields: \(fields)."],
                    ["role": "user", "content": prompt],
                ],
                "response_format": ["type": "json_object"],
            ]
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func reply(from data: Data, provider: Provider) throws -> VoiceAIReply {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KeyError.unreadable }
        let text: String?
        switch provider {
        case .anthropic:
            // A refusal or a cut-off answer has no usable form in it.
            let stop = object["stop_reason"] as? String
            if stop == "refusal" { throw KeyError.declined }
            if stop == "max_tokens" { throw KeyError.unreadable }
            let blocks = object["content"] as? [[String: Any]] ?? []
            text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        case .openAI, .custom:
            let choices = object["choices"] as? [[String: Any]] ?? []
            let message = choices.first?["message"] as? [String: Any]
            if message?["refusal"] is String { throw KeyError.declined }
            text = message?["content"] as? String
        }
        guard let text, let reply = VoiceAIReply.parse(text) else { throw KeyError.unreadable }
        return reply
    }
}
