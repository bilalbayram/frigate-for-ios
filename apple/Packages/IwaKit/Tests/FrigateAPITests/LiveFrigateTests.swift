import Foundation
import Testing

@testable import FrigateAPI

/// Opt-in checks against a real Frigate on its authenticated port.
///
/// Run with `IWA_LIVE_FRIGATE=1 swift test --filter LiveFrigateTests`. Reads `FRIGATE_URL` and credentials
/// from the gitignored `.env` at the repository root. Read-only: one login per user, then GET requests on
/// metadata. Assertions only; nothing about the server is printed.
enum LiveFrigate {
    static let environment: [String: String]? = {
        guard ProcessInfo.processInfo.environment["IWA_LIVE_FRIGATE"] == "1" else { return nil }
        let file = Fixtures.root.deletingLastPathComponent().appending(path: ".env")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[1].isEmpty { values[parts[0]] = parts[1] }
        }
        return values["FRIGATE_URL"] == nil ? nil : values
    }()

    static var isEnabled: Bool { environment != nil }

    static func credentials(_ role: String) -> FrigateCredentials? {
        guard let user = environment?["FRIGATE_\(role)_USERNAME"], let password = environment?["FRIGATE_\(role)_PASSWORD"] else {
            return nil
        }
        return FrigateCredentials(username: user, password: password)
    }

    static var baseURL: URL { URL(string: environment!["FRIGATE_URL"]!)! }

    /// Trust on first use, as the app will do: connect with a pin nothing matches, keep the key the server showed.
    static func observedPublicKey() async throws -> Data {
        let probe = URLSessionTransport(policy: .pinnedPublicKey(sha256: Data()))
        let client = FrigateClient(baseURL: baseURL, transport: probe)
        await #expect(throws: FrigateError.self) { try await client.send(FrigateEndpoint.version) }
        return try #require(probe.lastObservedPublicKeySHA256)
    }
}

@Suite(.enabled(if: LiveFrigate.isEnabled), .serialized)
struct LiveFrigateTests {
    @Test func `admin session reads metadata through a pinned connection`() async throws {
        let credentials = try #require(LiveFrigate.credentials("ADMIN"), "FRIGATE_ADMIN_* missing from .env")
        let key = try await LiveFrigate.observedPublicKey()
        #expect(key.count == 32)

        let client = FrigateClient(
            baseURL: LiveFrigate.baseURL, transport: URLSessionTransport(policy: .pinnedPublicKey(sha256: key)), credentials: credentials)
        let profile = try await client.send(FrigateEndpoint.profile)
        #expect(profile.isAdmin)

        let version = try await client.send(FrigateEndpoint.version)
        #expect(FrigateSupportPolicy.iwa.support(for: version) == .supported)

        let config = try await client.send(FrigateEndpoint.config)
        #expect(!config.cameras.isEmpty)
        #expect(config.isAuthEnabled)
        if let allowed = profile.allowedCameras {
            #expect(allowed.isSubset(of: Set(config.cameras.keys)))
        }

        let streams = try await client.send(FrigateEndpoint.go2rtcStreams)
        for camera in config.cameras.values {
            _ = camera.liveView(go2rtcStreams: streams.names)
        }

        let review = try await client.send(FrigateEndpoint.review(limit: 20))
        #expect(review.allSatisfy { config.cameras[$0.camera] != nil })
        _ = try await client.send(FrigateEndpoint.reviewSummary)
        let objects = try await client.send(FrigateEndpoint.trackedObjects(limit: 20))
        #expect(objects.allSatisfy { config.cameras[$0.camera] != nil })
        #expect(await client.currentToken?.expiresAt != nil)
    }

    @Test func `a wrong pin never reaches the server`() async throws {
        let credentials = try #require(LiveFrigate.credentials("ADMIN"))
        let transport = URLSessionTransport(policy: .pinnedPublicKey(sha256: Data(repeating: 7, count: 32)))
        let client = FrigateClient(baseURL: LiveFrigate.baseURL, transport: transport, credentials: credentials)
        await #expect {
            try await client.send(FrigateEndpoint.profile)
        } throws: { error in
            if case .transport = error as? FrigateError { true } else { false }
        }
    }

    @Test(.enabled(if: LiveFrigate.credentials("VIEWER") != nil))
    func `viewer sessions are not admin and see only allowed cameras`() async throws {
        let credentials = try #require(LiveFrigate.credentials("VIEWER"))
        let key = try await LiveFrigate.observedPublicKey()
        let client = FrigateClient(
            baseURL: LiveFrigate.baseURL, transport: URLSessionTransport(policy: .pinnedPublicKey(sha256: key)), credentials: credentials)
        let profile = try await client.send(FrigateEndpoint.profile)
        #expect(!profile.isAdmin)
        let config = try await client.send(FrigateEndpoint.config)
        if let allowed = profile.allowedCameras {
            #expect(allowed.isSubset(of: Set(config.cameras.keys)))
        }
    }
}
