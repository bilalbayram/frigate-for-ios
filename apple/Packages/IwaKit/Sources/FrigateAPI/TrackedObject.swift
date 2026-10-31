import Foundation

/// One tracked object from `GET /api/events` (called "tracked objects" in Frigate's UI since 0.14).
public struct TrackedObject: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let camera: String
    public let label: String
    public let subLabel: SubLabel?
    public let zones: [String]
    public let start: Date
    /// `nil` while the object is still tracked.
    public let end: Date?
    public let hasClip: Bool
    public let hasSnapshot: Bool
    /// Best score seen, from the top level or `data.top_score` depending on version.
    public let topScore: Double?
    public let isFalsePositive: Bool

    private enum CodingKeys: String, CodingKey {
        case id, camera, label, zones, data
        case subLabel = "sub_label"
        case start = "start_time"
        case end = "end_time"
        case hasClip = "has_clip"
        case hasSnapshot = "has_snapshot"
        case topScore = "top_score"
        case falsePositive = "false_positive"
    }

    private enum DataKeys: String, CodingKey {
        case topScore = "top_score"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        camera = try container.decode(String.self, forKey: .camera)
        label = try container.decode(String.self, forKey: .label)
        subLabel = try container.decodeIfPresent(SubLabel.self, forKey: .subLabel)
        zones = try container.decodeIfPresent([String].self, forKey: .zones) ?? []
        start = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .start))
        end = try container.decodeIfPresent(Double.self, forKey: .end).map(Date.init(timeIntervalSince1970:))
        hasClip = try container.decodeIfPresent(Bool.self, forKey: .hasClip) ?? false
        hasSnapshot = try container.decodeIfPresent(Bool.self, forKey: .hasSnapshot) ?? false
        isFalsePositive = try container.decodeIfPresent(Bool.self, forKey: .falsePositive) ?? false
        var score = try container.decodeIfPresent(Double.self, forKey: .topScore)
        if score == nil, container.contains(.data), try !container.decodeNil(forKey: .data) {
            score = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data).decodeIfPresent(Double.self, forKey: .topScore)
        }
        topScore = score
    }
}
