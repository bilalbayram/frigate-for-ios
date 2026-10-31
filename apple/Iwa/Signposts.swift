import os

/// Points of interest on the way from launch to the first video frame.
///
/// They show up in Instruments' Points of Interest track, and `IwaUITests` measures the launch interval
/// with `XCTOSSignpostMetric`, so keep the names stable.
enum Signposts {
    static let subsystem = "com.bilalbayram.iwa"
    static let launchInterval: StaticString = "Launch to first frame"

    private static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
    private static var launch: OSSignpostIntervalState?

    static func appStarted() {
        launch = signposter.beginInterval(launchInterval)
    }

    /// Ends the launch interval the first time the root view appears.
    static func firstFrameShown() {
        guard let launch else { return }
        signposter.endInterval(launchInterval, launch)
        self.launch = nil
    }

    static func routesResolved() { signposter.emitEvent("Routes resolved") }
    static func firstThumbnailShown() { signposter.emitEvent("First thumbnail") }
    static func firstVideoFrameShown() { signposter.emitEvent("First video frame") }
}
