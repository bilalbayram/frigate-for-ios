import Foundation

/// A Frigate API call and how to decode its response.
public struct FrigateRequest<Response: Sendable>: Sendable {
    public let method: String
    public let path: String
    public let query: [URLQueryItem]
    public let body: Data?
    /// Whether the call needs a session. Login and version don't.
    public let requiresAuth: Bool
    let decode: @Sendable (Data) throws -> Response

    init(
        method: String = "GET",
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuth: Bool = true,
        decode: @escaping @Sendable (Data) throws -> Response
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.decode = decode
    }

    func urlRequest(baseURL: URL, token: FrigateToken?) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if requiresAuth, let token { request.setValue("Bearer \(token.rawValue)", forHTTPHeaderField: "Authorization") }
        return request
    }
}

extension FrigateRequest where Response: Decodable {
    init(path: String, query: [URLQueryItem] = [], requiresAuth: Bool = true) {
        self.init(path: path, query: query, requiresAuth: requiresAuth) { data in
            try Frigate.decoder().decode(Response.self, from: data)
        }
    }
}

/// The read-only endpoints Iwa uses. Calls that change state get their own, reviewed additions.
public enum FrigateEndpoint {
    /// Plain text such as `0.18.2-cfa08c5`. Public on port 5000; needs a session on 8971.
    public static let version = FrigateRequest<FrigateVersion>(path: "api/version") { data in
        guard let text = String(data: data, encoding: .utf8), let version = FrigateVersion(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unparseable version"))
        }
        return version
    }

    public static let config = FrigateRequest<FrigateConfig>(path: "api/config")
    public static let profile = FrigateRequest<FrigateProfile>(path: "api/profile")
    public static let reviewSummary = FrigateRequest<ReviewSummary>(path: "api/review/summary")
    public static let go2rtcStreams = FrigateRequest<Go2RTCStreams>(path: "api/go2rtc/streams")

    public enum ReviewedFilter: Sendable, Hashable {
        case any
        case unreviewed
        case reviewed
    }

    public static func review(limit: Int = 50, filter: ReviewedFilter = .any) -> FrigateRequest<[ReviewSegment]> {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        switch filter {
        case .any: break
        case .unreviewed: query.append(URLQueryItem(name: "reviewed", value: "0"))
        case .reviewed: query.append(URLQueryItem(name: "reviewed", value: "1"))
        }
        return FrigateRequest(path: "api/review", query: query)
    }

    public static func trackedObjects(limit: Int = 50) -> FrigateRequest<[TrackedObject]> {
        FrigateRequest(path: "api/events", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    static func login(username: String, password: String) -> FrigateRequest<Void> {
        let body = try? JSONSerialization.data(withJSONObject: ["user": username, "password": password])
        return FrigateRequest<Void>(method: "POST", path: "api/login", body: body, requiresAuth: false) { _ in () }
    }
}

/// `GET /api/go2rtc/streams`: the streams go2rtc is serving right now, keyed by name.
public struct Go2RTCStreams: Decodable, Sendable, Hashable {
    public let names: Set<String>

    public init(from decoder: any Decoder) throws {
        names = Set(try decoder.singleValueContainer().decode([String: IgnoredValue].self).keys)
    }
}
