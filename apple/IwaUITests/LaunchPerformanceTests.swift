import XCTest

/// Launch budgets from AGENTS.md. Simulator numbers are trends only until the device lab exists (M1).
final class LaunchPerformanceTests: XCTestCase {
    @MainActor
    func testLaunchToFirstFrame() {
        let firstFrame = XCTOSSignpostMetric(
            subsystem: "com.bilalbayram.iwa",
            category: "PointsOfInterest",
            name: "Launch to first frame"
        )
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), firstFrame], options: options) {
            XCUIApplication().launch()
        }
    }
}
