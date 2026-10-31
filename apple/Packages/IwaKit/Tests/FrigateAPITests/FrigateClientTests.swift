import Foundation
import Synchronization
import Testing

@testable import FrigateAPI

/// Plays back scripted responses and records every request.
private final class FakeTransport: HTTPTransport {
    struct Reply {
        var status: Int
        var body = Data()
        var setCookie: String?
    }

    private let state = Mutex<(requests: [URLRequest], handler: @Sendable (URLRequest) -> Reply)>(([], { _ in Reply(status: 500) }))

    init(_ handler: @escaping @Sendable (URLRequest) -> Reply) {
        state.withLock { $0.handler = handler }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var logins: Int { requests.count { $0.url?.path == "/api/login" } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = state.withLock { state in
            state.requests.append(request)
            return state.handler(request)
        }
        var headers = ["Content-Type": "application/json"]
        if let cookie = reply.setCookie { headers["Set-Cookie"] = cookie }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (reply.body, response)
    }
}

private let start = Date(timeIntervalSince1970: 1_893_456_000)

private func jwt(expiresIn seconds: Double, marker: String = "a") -> String {
    func encode(_ json: String) -> String {
        Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    let payload = #"{"sub":"tester","role":"admin","exp":\#(Int(start.timeIntervalSince1970 + seconds))}"#
    return "\(encode(#"{"alg":"HS256","typ":"JWT"}"#)).\(encode(payload)).sig-\(marker)"
}

private func cookie(_ token: String) -> String {
    "frigate_token=\(token); expires=Thu, 03 Jan 2030 00:00:00 GMT; HttpOnly; Max-Age=86400; Path=/; SameSite=lax"
}

private let profileJSON = Data(#"{"username": "tester", "role": "viewer", "allowed_cameras": ["porch"]}"#.utf8)
private let credentials = FrigateCredentials(username: "tester", password: "correct horse")
private let base = URL(string: "https://nvr.invalid:8971")!

private func bearer(_ request: URLRequest) -> String? {
    request.value(forHTTPHeaderField: "Authorization")
}

struct FrigateTokenTests {
    @Test func `reads the expiry from the payload`() throws {
        let token = try #require(FrigateToken(jwt: jwt(expiresIn: 86_400)))
        #expect(token.expiresAt == start.addingTimeInterval(86_400))
        #expect(token.needsRefresh(at: start) == false)
        #expect(token.needsRefresh(at: start.addingTimeInterval(86_400 - 3_599)))
    }

    @Test(arguments: ["", "abc", "a.b", "a..c", ".b.c"])
    func `rejects strings that are not JWTs`(raw: String) {
        #expect(FrigateToken(jwt: raw) == nil)
    }

    @Test func `finds the token in Set-Cookie despite commas in Expires`() throws {
        let raw = jwt(expiresIn: 60)
        let token = try #require(FrigateToken(setCookieHeaders: ["other=1; Path=/, " + cookie(raw)]))
        #expect(token.rawValue == raw)
        #expect(FrigateToken(setCookieHeaders: [cookie(raw)], cookieName: "custom_token") == nil)
    }

    @Test func `never prints secrets`() throws {
        let raw = jwt(expiresIn: 60)
        #expect(!String(describing: try #require(FrigateToken(jwt: raw))).contains(raw))
        #expect(!String(describing: credentials).contains(credentials.password))
    }
}

struct FrigateClientTests {
    @Test func `sends no Authorization without credentials, as on port 5000`() async throws {
        let transport = FakeTransport { _ in .init(status: 200, body: profileJSON) }
        let client = FrigateClient(baseURL: base, transport: transport)
        _ = try await client.send(FrigateEndpoint.profile)
        #expect(transport.logins == 0)
        #expect(transport.requests.allSatisfy { bearer($0) == nil })
    }

    @Test func `logs in first, then sends the token as a bearer`() async throws {
        let token = jwt(expiresIn: 86_400)
        let transport = FakeTransport { request in
            request.url?.path == "/api/login" ? .init(status: 200, setCookie: cookie(token)) : .init(status: 200, body: profileJSON)
        }
        let client = FrigateClient(baseURL: base, transport: transport, credentials: credentials, now: { start })
        let profile = try await client.send(FrigateEndpoint.profile)

        #expect(profile.role == .viewer)
        let login = try #require(transport.requests.first)
        #expect(login.httpMethod == "POST")
        let body = try #require(login.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["user": "tester", "password": "correct horse"])
        #expect(bearer(login) == nil)
        #expect(bearer(transport.requests[1]) == "Bearer \(token)")
    }

    @Test func `refreshes a token that expires within the hour`() async throws {
        let fresh = jwt(expiresIn: 86_400, marker: "fresh")
        let transport = FakeTransport { request in
            request.url?.path == "/api/login" ? .init(status: 200, setCookie: cookie(fresh)) : .init(status: 200, body: profileJSON)
        }
        let stale = FrigateToken(jwt: jwt(expiresIn: 600, marker: "stale"))
        let client = FrigateClient(baseURL: base, transport: transport, credentials: credentials, token: stale, now: { start })
        _ = try await client.send(FrigateEndpoint.profile)
        #expect(transport.logins == 1)
        #expect(bearer(transport.requests.last!) == "Bearer \(fresh)")
    }

    @Test func `re-logs in once after a 401, then gives up`() async throws {
        let recovered = FakeTransport { request in
            if request.url?.path == "/api/login" { return .init(status: 200, setCookie: cookie(jwt(expiresIn: 86_400, marker: "new"))) }
            return bearer(request)?.hasSuffix("sig-new") == true ? .init(status: 200, body: profileJSON) : .init(status: 401)
        }
        let valid = FrigateToken(jwt: jwt(expiresIn: 86_400, marker: "revoked"))
        let client = FrigateClient(baseURL: base, transport: recovered, credentials: credentials, token: valid, now: { start })
        _ = try await client.send(FrigateEndpoint.profile)
        #expect(recovered.logins == 1)

        let rejected = FakeTransport { request in
            request.url?.path == "/api/login" ? .init(status: 200, setCookie: cookie(jwt(expiresIn: 86_400))) : .init(status: 401)
        }
        let stuck = FrigateClient(baseURL: base, transport: rejected, credentials: credentials, now: { start })
        await #expect(throws: FrigateError.unauthorized) { try await stuck.send(FrigateEndpoint.profile) }
        #expect(rejected.logins == 2, "One login up front, one retry")
        #expect(rejected.requests.count == 4)
    }

    @Test func `takes renewed tokens from Set-Cookie on any response`() async throws {
        let renewed = jwt(expiresIn: 86_400, marker: "renewed")
        let transport = FakeTransport { _ in .init(status: 200, body: profileJSON, setCookie: cookie(renewed)) }
        let client = FrigateClient(
            baseURL: base, transport: transport, credentials: credentials, token: FrigateToken(jwt: jwt(expiresIn: 86_400)), now: { start })
        _ = try await client.send(FrigateEndpoint.profile)
        _ = try await client.send(FrigateEndpoint.profile)
        #expect(bearer(transport.requests[1]) == "Bearer \(renewed)")
        #expect(await client.currentToken?.rawValue == renewed)
    }

    @Test func `concurrent requests share one login`() async throws {
        let transport = FakeTransport { request in
            request.url?.path == "/api/login"
                ? .init(status: 200, setCookie: cookie(jwt(expiresIn: 86_400))) : .init(status: 200, body: profileJSON)
        }
        let client = FrigateClient(baseURL: base, transport: transport, credentials: credentials, now: { start })
        try await withThrowingTaskGroup(of: FrigateProfile.self) { group in
            for _ in 0..<8 { group.addTask { try await client.send(FrigateEndpoint.profile) } }
            for try await _ in group {}
        }
        #expect(transport.logins == 1)
        #expect(transport.requests.count == 9)
    }

    @Test(arguments: [
        (401, FrigateError.unauthorized),
        (403, .unauthorized),
        (429, .rateLimited),
        (500, .http(status: 500)),
    ])
    func `maps login failures`(status: Int, expected: FrigateError) async {
        let transport = FakeTransport { _ in .init(status: status) }
        let client = FrigateClient(baseURL: base, transport: transport, credentials: credentials, now: { start })
        await #expect(throws: expected) { try await client.send(FrigateEndpoint.profile) }
    }

    @Test func `a login without a token cookie is an error, not a silent anonymous session`() async {
        let transport = FakeTransport { _ in .init(status: 200) }
        let client = FrigateClient(baseURL: base, transport: transport, credentials: credentials, now: { start })
        await #expect(throws: FrigateError.self) { try await client.send(FrigateEndpoint.profile) }
        #expect(transport.requests.count == 1)
    }

    @Test(arguments: [
        (403, FrigateError.forbidden),
        (404, .http(status: 404)),
        (429, .rateLimited),
    ])
    func `maps response failures`(status: Int, expected: FrigateError) async {
        let transport = FakeTransport { _ in .init(status: status) }
        let client = FrigateClient(baseURL: base, transport: transport)
        await #expect(throws: expected) { try await client.send(FrigateEndpoint.profile) }
    }

    @Test func `bad JSON is a decoding error`() async {
        let transport = FakeTransport { _ in .init(status: 200, body: Data("<html>".utf8)) }
        let client = FrigateClient(baseURL: base, transport: transport)
        await #expect {
            try await client.send(FrigateEndpoint.profile)
        } throws: { error in
            if case .decoding = error as? FrigateError { true } else { false }
        }
    }

    @Test func `keeps a reverse-proxy path prefix and encodes query parameters`() {
        let request = FrigateEndpoint.review(limit: 20, filter: .unreviewed).urlRequest(
            baseURL: URL(string: "https://example.invalid/frigate/")!, token: nil)
        #expect(request.url?.absoluteString == "https://example.invalid/frigate/api/review?limit=20&reviewed=0")
    }
}

struct FrigateProfileTests {
    @Test func `restricted roles only see allowed cameras`() throws {
        let viewer = try Frigate.decoder().decode(FrigateProfile.self, from: profileJSON)
        #expect(!viewer.isAdmin)
        #expect(viewer.canSee(camera: "porch") && !viewer.canSee(camera: "garage"))

        let custom = try Frigate.decoder().decode(FrigateProfile.self, from: Data(#"{"username": "x", "role": "kids"}"#.utf8))
        #expect(custom.role == .custom("kids"))
        #expect(custom.allowedCameras == nil && custom.canSee(camera: "garage"), "No list means no restriction")
    }
}
