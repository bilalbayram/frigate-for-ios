/// `GET /api/profile`: who the session belongs to and what it may see.
public struct FrigateProfile: Decodable, Sendable, Hashable {
    public enum Role: Hashable, Sendable {
        case admin
        case viewer
        /// A custom role (Frigate 0.17+), restricted to `allowedCameras`.
        case custom(String)
    }

    public let username: String
    public let role: Role
    /// Cameras this user may see. `nil` when the server doesn't restrict cameras per role.
    public let allowedCameras: Set<String>?

    /// Only admins may change cameras, review state, or settings.
    public var isAdmin: Bool { role == .admin }

    public func canSee(camera: String) -> Bool {
        allowedCameras?.contains(camera) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case username, role
        case allowedCameras = "allowed_cameras"
    }

    public init(username: String, role: Role, allowedCameras: Set<String>?) {
        self.username = username
        self.role = role
        self.allowedCameras = allowedCameras
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        role = Role(rawValue: try container.decodeIfPresent(String.self, forKey: .role) ?? "viewer")
        allowedCameras = try container.decodeIfPresent([String].self, forKey: .allowedCameras).map(Set.init)
    }
}

extension FrigateProfile.Role {
    init(rawValue: String) {
        switch rawValue {
        case "admin": self = .admin
        case "viewer": self = .viewer
        default: self = .custom(rawValue)
        }
    }
}
