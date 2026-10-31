/// How Iwa can show a camera live.
public enum LiveView: Hashable, Sendable {
    /// go2rtc restreams the camera: WebRTC with low latency and audio. Label → go2rtc stream name.
    case webRTC(streams: [String: String])
    /// No go2rtc stream. Frigate's web UI falls back to jsmpeg (MPEG-1 over a websocket), which has no
    /// native decoder on Apple platforms, so Iwa refreshes `GET /api/<camera>/latest.jpg` instead.
    case snapshots
}

extension FrigateConfig.Camera {
    /// - Parameter go2rtcStreams: Stream names from `GET /api/go2rtc/streams`, the runtime source of truth.
    public func liveView(go2rtcStreams: Set<String>) -> LiveView {
        // Frigate uses the camera name as the stream when `live.streams` is empty.
        let candidates = liveStreams.isEmpty ? [name: name] : liveStreams
        let available = candidates.filter { go2rtcStreams.contains($0.value) }
        return available.isEmpty ? .snapshots : .webRTC(streams: available)
    }
}
