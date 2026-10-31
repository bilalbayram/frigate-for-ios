import Foundation

/// The JWT Frigate issues on login (cookie `frigate_token` by default, configurable as `auth.cookie_name`).
///
/// Sent back as `Authorization: Bearer`, which Frigate accepts on port 8971, so no cookie jar is needed.
/// The payload is read without verifying the signature: the server verifies it, the client only needs
/// to know when it expires.
public struct FrigateToken: Sendable, Hashable, CustomStringConvertible {
    public static let defaultCookieName = "frigate_token"

    public let rawValue: String
    public let expiresAt: Date?

    /// Returns `nil` unless `jwt` has three dot-separated parts.
    public init?(jwt: String) {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        rawValue = jwt
        let payload = Data(base64URLEncoded: String(parts[1]))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        expiresAt = (payload?["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    /// Finds the token in `Set-Cookie` header values.
    public init?(setCookieHeaders headers: [String], cookieName: String = defaultCookieName) {
        let prefix = "\(cookieName)="
        for header in headers {
            for cookie in header.split(separator: ",") {
                let pair = cookie.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
                if pair.hasPrefix(prefix), let token = FrigateToken(jwt: String(pair.dropFirst(prefix.count))) {
                    self = token
                    return
                }
            }
        }
        return nil
    }

    /// Refresh when less than `margin` remains. Tokens without an expiry are refreshed only on 401.
    public func needsRefresh(at now: Date, margin: Duration = .seconds(3_600)) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < Double(margin.components.seconds)
    }

    /// Never prints the token.
    public var description: String {
        "FrigateToken(expires: \(expiresAt.map { "\($0)" } ?? "never"))"
    }
}

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
