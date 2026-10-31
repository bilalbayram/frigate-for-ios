import Foundation
import FrigateAPI
import Testing

/// Decodes every captured Frigate version. Adding `fixtures/frigate/<version>/` adds a row here.
struct FrigateFixtureTests {
    @Test func `fixtures exist`() {
        #expect(!Fixtures.frigateVersions.isEmpty)
    }

    @Test(arguments: Fixtures.frigateVersions)
    func `captured versions are supported`(version: String) throws {
        let reported = try #require(String(data: try Fixtures.data(version, "version.txt"), encoding: .utf8))
        let parsed = try #require(FrigateVersion(reported))
        #expect(FrigateSupportPolicy.iwa.support(for: parsed) == .supported)
    }

    @Test(arguments: Fixtures.frigateVersions)
    func `config decodes with camera names intact`(version: String) throws {
        let config = try Fixtures.decode(FrigateConfig.self, version, "config.json")
        #expect(!config.cameras.isEmpty)
        for (key, camera) in config.cameras {
            #expect(key == camera.name, "Dictionary keys must not be snake-case converted")
        }
        let ordered = config.orderedCameras
        #expect(zip(ordered, ordered.dropFirst()).allSatisfy { ($0.order, $0.name) <= ($1.order, $1.name) })
    }

    @Test(arguments: Fixtures.frigateVersions)
    func `review items decode and reference known cameras`(version: String) throws {
        let config = try Fixtures.decode(FrigateConfig.self, version, "config.json")
        let review = try Fixtures.decode([ReviewSegment].self, version, "review.json")
        #expect(!review.isEmpty)
        for item in review {
            #expect(config.cameras[item.camera] != nil)
            #expect(item.end.map { $0 >= item.start } ?? true)
            if case .other(let raw) = item.severity { Issue.record("Unknown severity \(raw)") }
        }
        let summary = try Fixtures.decode(ReviewSummary.self, version, "review_summary.json")
        #expect(summary.days.keys.allSatisfy { $0.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil })
    }

    @Test(arguments: Fixtures.frigateVersions)
    func `tracked objects decode and reference known cameras`(version: String) throws {
        let config = try Fixtures.decode(FrigateConfig.self, version, "config.json")
        let objects = try Fixtures.decode([TrackedObject].self, version, "events.json")
        #expect(!objects.isEmpty)
        #expect(objects.allSatisfy { config.cameras[$0.camera] != nil && !$0.label.isEmpty })
    }

    @Test(arguments: Fixtures.frigateVersions)
    func `cameras without go2rtc streams fall back to snapshots`(version: String) throws {
        let config = try Fixtures.decode(FrigateConfig.self, version, "config.json")
        let runtime = try Fixtures.decode([String: IgnoredJSON].self, version, "go2rtc_streams.json")
        for camera in config.cameras.values {
            let view = camera.liveView(go2rtcStreams: Set(runtime.keys))
            let expectWebRTC =
                camera.liveStreams.values.contains { runtime[$0] != nil }
                || (camera.liveStreams.isEmpty && runtime[camera.name] != nil)
            #expect((view != .snapshots) == expectWebRTC)
        }
    }
}

private struct IgnoredJSON: Decodable {
    init(from decoder: any Decoder) throws {}
}
