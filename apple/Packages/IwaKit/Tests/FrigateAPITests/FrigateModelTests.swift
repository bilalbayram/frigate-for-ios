import Foundation
import FrigateAPI
import Testing

/// Shapes the captured server didn't produce, written inline.
struct FrigateModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try Frigate.decoder().decode(type, from: Data(json.utf8))
    }

    private func camera(_ json: String) throws -> FrigateConfig.Camera {
        try decode(FrigateConfig.Camera.self, json)
    }

    @Test(arguments: [
        (#""Alice""#, SubLabel(name: "Alice")),
        (#"["AB12CDE", 0.93]"#, SubLabel(name: "AB12CDE", score: 0.93)),
        (#"["Bob"]"#, SubLabel(name: "Bob")),
    ])
    func `sub labels decode as a string or a name-score pair`(json: String, expected: SubLabel) throws {
        #expect(try decode(SubLabel.self, json) == expected)
    }

    @Test func `live view prefers go2rtc streams that exist`() throws {
        let cam = try camera(#"{"name": "porch", "live": {"streams": {"Main": "porch_main", "Sub": "porch_sub"}}}"#)
        #expect(cam.liveView(go2rtcStreams: []) == .snapshots)
        #expect(cam.liveView(go2rtcStreams: ["porch_sub", "other"]) == .webRTC(streams: ["Sub": "porch_sub"]))
    }

    @Test func `live view defaults to the camera name when no streams are configured`() throws {
        let cam = try camera(#"{"name": "porch"}"#)
        #expect(cam.liveView(go2rtcStreams: ["porch"]) == .webRTC(streams: ["porch": "porch"]))
        #expect(cam.liveView(go2rtcStreams: ["garage"]) == .snapshots)
    }

    @Test func `missing sections mean disabled, except the camera itself`() throws {
        let cam = try camera(#"{"name": "porch", "onvif": {"host": ""}, "ui": null}"#)
        #expect(cam.isEnabled)
        #expect(!cam.isDetecting && !cam.isRecording && !cam.hasONVIF)
        #expect(cam.order == 0 && cam.isOnDashboard)
        #expect(try camera(#"{"name": "ptz", "onvif": {"host": "192.0.2.9"}}"#).hasONVIF)
    }

    @Test func `in-progress review items have no end and unknown severities survive`() throws {
        let item = try decode(
            ReviewSegment.self,
            #"""
            {"id": "1", "camera": "porch", "start_time": 1893456000.5, "end_time": null, "severity": "critical",
             "data": {"objects": ["person"], "sub_labels": [["Alice", 0.9]]}}
            """#)
        #expect(item.isInProgress)
        #expect(item.severity == .other("critical"))
        #expect(item.subLabels == ["Alice"])
    }

    @Test func `top score falls back to data.top_score`() throws {
        let object = try decode(
            TrackedObject.self,
            #"""
            {"id": "1", "camera": "porch", "label": "car", "start_time": 1893456000, "end_time": null,
             "top_score": null, "data": {"top_score": 0.81}}
            """#)
        #expect(object.topScore == 0.81)
        #expect(object.end == nil)
    }

    @Test func `review summary splits last 24 hours from days`() throws {
        let summary = try decode(
            ReviewSummary.self,
            #"""
            {"last24Hours": {"total_alert": 5, "reviewed_alert": 2, "total_detection": 1, "reviewed_detection": 0},
             "2029-12-31": {"day": "2029-12-31", "total_alert": 3}}
            """#)
        #expect(summary.last24Hours.unreviewedAlerts == 3)
        #expect(summary.days["2029-12-31"]?.totalAlerts == 3)
        #expect(summary.days.count == 1)
    }
}
