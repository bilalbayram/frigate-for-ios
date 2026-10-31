/// The parts of `GET /api/config` Iwa uses.
///
/// Decoded with explicit coding keys: `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` would also
/// rewrite dictionary keys, turning a camera named `front_door` into `frontDoor`.
public struct FrigateConfig: Decodable, Sendable, Hashable {
    public let cameras: [String: Camera]
    public let isAuthEnabled: Bool
    public let isSemanticSearchEnabled: Bool
    public let isFaceRecognitionEnabled: Bool
    public let isLicensePlateRecognitionEnabled: Bool
    public let cameraGroups: [String: CameraGroup]
    /// Stream names declared under `go2rtc.streams`. `GET /api/go2rtc/streams` is the runtime truth.
    public let go2rtcStreamNames: Set<String>

    /// Cameras in the order Frigate's UI shows them: `ui.order`, then name.
    public var orderedCameras: [Camera] {
        cameras.values.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    public struct Camera: Decodable, Sendable, Hashable, Identifiable {
        public let name: String
        public let isEnabled: Bool
        public let isDetecting: Bool
        public let isRecording: Bool
        public let isSavingSnapshots: Bool
        public let isAudioDetecting: Bool
        public let isLicensePlateRecognitionEnabled: Bool
        public let isFaceRecognitionEnabled: Bool
        /// Sorted zone names.
        public let zones: [String]
        /// Live stream label → go2rtc stream name, from `live.streams`.
        public let liveStreams: [String: String]
        /// ONVIF is configured. Whether the camera actually supports PTZ comes from `GET /api/<camera>/ptz/info`.
        public let hasONVIF: Bool
        public let order: Int
        public let isOnDashboard: Bool

        public var id: String { name }

        private enum CodingKeys: String, CodingKey {
            case name, enabled, detect, record, snapshots, audio, lpr, zones, live, onvif, ui
            case faceRecognition = "face_recognition"
        }

        private enum UIKeys: String, CodingKey {
            case order, dashboard
        }

        private enum LiveKeys: String, CodingKey {
            case streams
        }

        private enum ONVIFKeys: String, CodingKey {
            case host
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            isDetecting = try container.enabled(.detect)
            isRecording = try container.enabled(.record)
            isSavingSnapshots = try container.enabled(.snapshots)
            isAudioDetecting = try container.enabled(.audio)
            isLicensePlateRecognitionEnabled = try container.enabled(.lpr)
            isFaceRecognitionEnabled = try container.enabled(.faceRecognition)
            zones = try container.decodeIfPresent([String: IgnoredValue].self, forKey: .zones)?.keys.sorted() ?? []

            if container.contains(.live), try !container.decodeNil(forKey: .live) {
                let live = try container.nestedContainer(keyedBy: LiveKeys.self, forKey: .live)
                liveStreams = try live.decodeIfPresent([String: String].self, forKey: .streams) ?? [:]
            } else {
                liveStreams = [:]
            }
            if container.contains(.onvif), try !container.decodeNil(forKey: .onvif) {
                let onvif = try container.nestedContainer(keyedBy: ONVIFKeys.self, forKey: .onvif)
                hasONVIF = !(try onvif.decodeIfPresent(String.self, forKey: .host) ?? "").isEmpty
            } else {
                hasONVIF = false
            }
            if container.contains(.ui), try !container.decodeNil(forKey: .ui) {
                let ui = try container.nestedContainer(keyedBy: UIKeys.self, forKey: .ui)
                order = try ui.decodeIfPresent(Int.self, forKey: .order) ?? 0
                isOnDashboard = try ui.decodeIfPresent(Bool.self, forKey: .dashboard) ?? true
            } else {
                order = 0
                isOnDashboard = true
            }
        }
    }

    public struct CameraGroup: Decodable, Sendable, Hashable {
        public let cameras: [String]
        public let icon: String?
        public let order: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case cameras, auth, lpr, go2rtc
        case semanticSearch = "semantic_search"
        case faceRecognition = "face_recognition"
        case cameraGroups = "camera_groups"
    }

    private enum Go2RTCKeys: String, CodingKey {
        case streams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cameras = try container.decode([String: Camera].self, forKey: .cameras)
        isAuthEnabled = try container.enabled(.auth)
        isSemanticSearchEnabled = try container.enabled(.semanticSearch)
        isFaceRecognitionEnabled = try container.enabled(.faceRecognition)
        isLicensePlateRecognitionEnabled = try container.enabled(.lpr)
        cameraGroups = try container.decodeIfPresent([String: CameraGroup].self, forKey: .cameraGroups) ?? [:]
        if container.contains(.go2rtc), try !container.decodeNil(forKey: .go2rtc) {
            let go2rtc = try container.nestedContainer(keyedBy: Go2RTCKeys.self, forKey: .go2rtc)
            let streams = try go2rtc.decodeIfPresent([String: IgnoredValue].self, forKey: .streams) ?? [:]
            go2rtcStreamNames = Set(streams.keys)
        } else {
            go2rtcStreamNames = []
        }
    }
}

/// Accepts and discards any JSON value, for objects whose keys matter but values don't.
struct IgnoredValue: Decodable, Hashable, Sendable {
    init(from decoder: any Decoder) throws {}
}

private struct EnabledFlag: Decodable {
    let enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case enabled
    }

    init(from decoder: any Decoder) throws {
        enabled = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }
}

extension KeyedDecodingContainer {
    /// Reads `<key>.enabled`, treating a missing section as disabled.
    fileprivate func enabled(_ key: Key) throws -> Bool {
        try decodeIfPresent(EnabledFlag.self, forKey: key)?.enabled ?? false
    }
}
