import Foundation
import Security

/// Credentials are supplied only to the separately signed personal test copy.
/// This never creates an alternate authentication path in a production build.
struct OwnerAITestConfiguration {
    let baseURL: URL
    let token: String
    var certificateDER: Data? = nil

    var transportDescription: String {
        certificateDER == nil ? "through the temporary ngrok connection" : "over your local network using an encrypted, certificate-pinned connection"
    }

    func makeSession() -> URLSession {
        guard let certificateDER else { return .shared }
        return URLSession(configuration: .ephemeral,
                          delegate: OwnerAITrustDelegate(host: baseURL.host ?? "", certificateDER: certificateDER),
                          delegateQueue: nil)
    }

    static var current: OwnerAITestConfiguration? {
        #if DEBUG && MEALIO_LOCAL_PHONE_TEST
        resolve(info: Bundle.main.infoDictionary ?? [:], ownerBuild: true)
        #else
        nil
        #endif
    }

    static func resolve(info: [String: Any], ownerBuild: Bool) -> OwnerAITestConfiguration? {
        guard ownerBuild,
              let text = info["OWNER_AI_BASE_URL"] as? String,
              let url = URL(string: text), let host = url.host,
              url.scheme == "https", !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let token = info["OWNER_AI_TOKEN"] as? String,
              token.count >= 32,
              token.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        else { return nil }
        var pin: Data?
        if let encoded = info["OWNER_AI_CERT_DER"] as? String {
            guard let data = Data(base64Encoded: encoded),
                  SecCertificateCreateWithData(nil, data as CFData) != nil,
                  Self.isPrivateIPv4(host) else { return nil }
            pin = data
        } else if Self.isPrivateIPv4(host) {
            // A direct local server requires its own exact certificate pin.
            return nil
        }
        return OwnerAITestConfiguration(baseURL: url, token: token, certificateDER: pin)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        let bytes = pieces.compactMap { UInt8($0) }
        guard pieces.count == 4, bytes.count == 4,
              zip(pieces, bytes).allSatisfy({ String($0.0) == String($0.1) }) else { return false }
        return bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 192 && bytes[1] == 168)
    }
}

/// Trust only the exact locally generated server certificate, for its compiled
/// host, and require normal SSL hostname/validity evaluation against that anchor.
/// No system trust settings or production URLSession behavior are changed.
private final class OwnerAITrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    nonisolated let host: String
    nonisolated let certificateDER: Data

    init(host: String, certificateDER: Data) {
        self.host = host
        self.certificateDER = certificateDER
    }

    nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                               completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              SecCertificateCopyData(leaf) as Data == certificateDER,
              let anchor = SecCertificateCreateWithData(nil, certificateDER as CFData),
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [anchor] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
