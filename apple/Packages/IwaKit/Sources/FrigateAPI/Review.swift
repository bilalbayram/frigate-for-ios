import Foundation

/// One item from `GET /api/review`: an alert or detection spanning one or more tracked objects.
public struct ReviewSegment: Decodable, Sendable, Hashable, Identifiable {
    public enum Severity: Hashable, Sendable {
        case alert
        case detection
        /// A severity this version of Iwa doesn't know yet.
        case other(String)
    }

    public let id: String
    public let camera: String
    public let start: Date
    /// `nil` while the segment is still in progress.
    public let end: Date?
    public let severity: Severity
    public let hasBeenReviewed: Bool
    public let thumbPath: String
    public let objects: [String]
    public let zones: [String]
    public let audio: [String]
    public let subLabels: [String]
    /// IDs of the tracked objects (`/api/events`) in this segment.
    public let detectionIDs: [String]

    public var isInProgress: Bool { end == nil }

    private enum CodingKeys: String, CodingKey {
        case id, camera, severity, data
        case start = "start_time"
        case end = "end_time"
        case hasBeenReviewed = "has_been_reviewed"
        case thumbPath = "thumb_path"
    }

    private enum DataKeys: String, CodingKey {
        case objects, zones, audio, detections
        case subLabels = "sub_labels"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        camera = try container.decode(String.self, forKey: .camera)
        start = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .start))
        end = try container.decodeIfPresent(Double.self, forKey: .end).map(Date.init(timeIntervalSince1970:))
        severity = Severity(rawValue: try container.decode(String.self, forKey: .severity))
        hasBeenReviewed = try container.decodeIfPresent(Bool.self, forKey: .hasBeenReviewed) ?? false
        thumbPath = try container.decodeIfPresent(String.self, forKey: .thumbPath) ?? ""
        let data = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        objects = try data.decodeIfPresent([String].self, forKey: .objects) ?? []
        zones = try data.decodeIfPresent([String].self, forKey: .zones) ?? []
        audio = try data.decodeIfPresent([String].self, forKey: .audio) ?? []
        subLabels = try data.decodeIfPresent([SubLabel].self, forKey: .subLabels)?.map(\.name) ?? []
        detectionIDs = try data.decodeIfPresent([String].self, forKey: .detections) ?? []
    }
}

extension ReviewSegment.Severity {
    init(rawValue: String) {
        switch rawValue {
        case "alert": self = .alert
        case "detection": self = .detection
        default: self = .other(rawValue)
        }
    }
}

/// `GET /api/review/summary`: counts for the last 24 hours and per day.
public struct ReviewSummary: Decodable, Sendable, Hashable {
    public struct Counts: Decodable, Sendable, Hashable {
        public let totalAlerts: Int
        public let totalDetections: Int
        public let reviewedAlerts: Int
        public let reviewedDetections: Int

        public var unreviewedAlerts: Int { max(totalAlerts - reviewedAlerts, 0) }
        public var unreviewedDetections: Int { max(totalDetections - reviewedDetections, 0) }

        private enum CodingKeys: String, CodingKey {
            case totalAlerts = "total_alert"
            case totalDetections = "total_detection"
            case reviewedAlerts = "reviewed_alert"
            case reviewedDetections = "reviewed_detection"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalAlerts = try container.decodeIfPresent(Int.self, forKey: .totalAlerts) ?? 0
            totalDetections = try container.decodeIfPresent(Int.self, forKey: .totalDetections) ?? 0
            reviewedAlerts = try container.decodeIfPresent(Int.self, forKey: .reviewedAlerts) ?? 0
            reviewedDetections = try container.decodeIfPresent(Int.self, forKey: .reviewedDetections) ?? 0
        }
    }

    public let last24Hours: Counts
    /// Keyed by day, `yyyy-MM-dd` in the server's time zone.
    public let days: [String: Counts]

    public init(from decoder: any Decoder) throws {
        var all = try decoder.singleValueContainer().decode([String: Counts].self)
        guard let last24Hours = all.removeValue(forKey: "last24Hours") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing last24Hours"))
        }
        self.last24Hours = last24Hours
        days = all
    }
}

/// A sub label: a recognized face, plate, or custom label. Frigate sends either `"name"` or `["name", score]`.
public struct SubLabel: Decodable, Sendable, Hashable {
    public let name: String
    public let score: Double?

    public init(name: String, score: Double? = nil) {
        self.name = name
        self.score = score
    }

    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let name = try? single.decode(String.self) {
            self.init(name: name)
            return
        }
        var pair = try decoder.unkeyedContainer()
        let name = try pair.decode(String.self)
        let score = pair.isAtEnd ? nil : try pair.decodeIfPresent(Double.self)
        self.init(name: name, score: score)
    }
}
