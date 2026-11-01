import Foundation

/// Sends HTTP requests. `URLSessionTransport` in production; tests use a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct FrigateCredentials: Sendable, Hashable, CustomStringConvertible {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// Never prints the password.
    public var description: String { "FrigateCredentials(username: \(username))" }
}

public enum FrigateError: Error, Sendable, Hashable {
    /// No credentials, or the server rejected them.
    case unauthorized
    /// The session is valid but its role may not do this.
    case forbidden
    /// Frigate rate-limits failed logins.
    case rateLimited
    case http(status: Int)
    case decoding(String)
    case transport(String)
}

/// Talks to one Frigate server over one base URL (a route).
///
/// Holds the session: logs in when needed, refreshes the token an hour before it expires, takes renewed
/// tokens from `Set-Cookie`, and retries a request once after a 401. Concurrent callers share one login.
public actor FrigateClient {
    public let baseURL: URL
    private let transport: any HTTPTransport
    private let credentials: FrigateCredentials?
    private let cookieName: String
    private let now: @Sendable () -> Date
    private var token: FrigateToken?
    private var pendingLogin: Task<FrigateToken, any Error>?

    public init(
        baseURL: URL,
        transport: any HTTPTransport,
        credentials: FrigateCredentials? = nil,
        token: FrigateToken? = nil,
        cookieName: String = FrigateToken.defaultCookieName,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.credentials = credentials
        self.token = token
        self.cookieName = cookieName
        self.now = now
    }

    /// The current token, for storing in the Keychain between launches.
    public var currentToken: FrigateToken? { token }

    public func send<Response>(_ request: FrigateRequest<Response>) async throws(FrigateError) -> Response {
        if request.requiresAuth, credentials != nil, token.map({ $0.needsRefresh(at: now()) }) ?? true {
            try await login()
        }
        let (data, response) = try await perform(request)
        if response.statusCode == 401, request.requiresAuth, credentials != nil {
            token = nil
            try await login()
            return try decode(request, try await perform(request))
        }
        return try decode(request, (data, response))
    }

    /// Logs in with the stored credentials. Callers that arrive while a login is running wait for it.
    public func login() async throws(FrigateError) {
        guard let credentials else { throw .unauthorized }
        let task: Task<FrigateToken, any Error>
        if let pendingLogin {
            task = pendingLogin
        } else {
            task = Task { try await self.performLogin(credentials) }
            pendingLogin = task
        }
        defer { if pendingLogin == task { pendingLogin = nil } }
        do {
            token = try await task.value
        } catch let error as FrigateError {
            throw error
        } catch {
            throw .transport(String(describing: error))
        }
    }

    private func performLogin(_ credentials: FrigateCredentials) async throws -> FrigateToken {
        let request = FrigateEndpoint.login(username: credentials.username, password: credentials.password)
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200..<300:
            guard let token = FrigateToken(setCookieHeaders: setCookies(response), cookieName: cookieName) else {
                throw FrigateError.decoding("Login succeeded but returned no \(cookieName) cookie")
            }
            return token
        case 401, 403: throw FrigateError.unauthorized
        case 429: throw FrigateError.rateLimited
        default: throw FrigateError.http(status: response.statusCode)
        }
    }

    private func perform<Response>(_ request: FrigateRequest<Response>) async throws(FrigateError) -> (Data, HTTPURLResponse) {
        let urlRequest = request.urlRequest(baseURL: baseURL, token: token)
        let result: (Data, HTTPURLResponse)
        do {
            result = try await transport.send(urlRequest)
        } catch {
            throw .transport(String(describing: error))
        }
        if request.requiresAuth, let renewed = FrigateToken(setCookieHeaders: setCookies(result.1), cookieName: cookieName) {
            token = renewed
        }
        return result
    }

    private func decode<Response>(_ request: FrigateRequest<Response>, _ result: (Data, HTTPURLResponse)) throws(FrigateError) -> Response {
        let (data, response) = result
        switch response.statusCode {
        case 200..<300:
            do {
                return try request.decode(data)
            } catch {
                throw .decoding(String(describing: error))
            }
        case 401: throw .unauthorized
        case 403: throw .forbidden
        case 429: throw .rateLimited
        default: throw .http(status: response.statusCode)
        }
    }

    private func setCookies(_ response: HTTPURLResponse) -> [String] {
        response.value(forHTTPHeaderField: "Set-Cookie").map { [$0] } ?? []
    }
}
