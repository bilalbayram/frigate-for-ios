import CryptoKit
import Foundation
import Security
import Synchronization

/// Which server certificates to accept.
public enum ServerTrustPolicy: Sendable, Hashable {
    /// The system's trust store, for public hostnames with real certificates.
    case system
    /// Only a server whose leaf certificate has this public key. Frigate's port 8971 uses a self-signed
    /// certificate, so Iwa pins its key on first connection after the user confirms it.
    case pinnedPublicKey(sha256: Data)
}

public enum ServerTrust {
    /// SHA-256 of the leaf certificate's public key in its external representation (X9.63 for EC keys,
    /// PKCS #1 for RSA). Stable across certificate renewals that keep the key.
    public static func publicKeySHA256(of certificate: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(certificate),
            let bytes = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else { return nil }
        return Data(SHA256.hash(data: bytes))
    }

    static func leafPublicKeySHA256(_ trust: SecTrust) -> Data? {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return nil }
        return publicKeySHA256(of: leaf)
    }

    /// Whether to accept `trust` under `policy`.
    static func evaluate(_ trust: SecTrust, policy: ServerTrustPolicy) -> Bool {
        switch policy {
        case .system:
            return SecTrustEvaluateWithError(trust, nil)
        case .pinnedPublicKey(let expected):
            return leafPublicKeySHA256(trust) == expected
        }
    }
}

/// `HTTPTransport` over `URLSession`, with its own trust policy and no shared cookie storage.
public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let trust: TrustDelegate

    public init(policy: ServerTrustPolicy, timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        trust = TrustDelegate(policy: policy)
        // The session retains its delegate, not this transport, so deinit still runs.
        session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// The leaf public key hash the server presented on the last connection, for trust-on-first-use.
    public var lastObservedPublicKeySHA256: Data? { trust.observedKey.withLock { $0 } }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

private final class TrustDelegate: NSObject, URLSessionDelegate, Sendable {
    let policy: ServerTrustPolicy
    let observedKey = Mutex<Data?>(nil)

    init(policy: ServerTrustPolicy) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else { return (.performDefaultHandling, nil) }
        observedKey.withLock { $0 = ServerTrust.leafPublicKeySHA256(trust) }
        guard ServerTrust.evaluate(trust, policy: policy) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
