import CoreGraphics
import XCTest
@testable import PPTTimer

final class PPTTimerTests: XCTestCase {
    func testFormatsCountdownAndOvertime() {
        XCTAssertEqual(CountdownMath.format(seconds: 1_200), "20:00")
        XCTAssertEqual(CountdownMath.format(seconds: 3_661), "1:01:01")
        XCTAssertEqual(CountdownMath.format(seconds: -9), "+00:09")
    }

    func testRemainingUsesWholeElapsedSeconds() {
        XCTAssertEqual(CountdownMath.remaining(duration: 10, elapsed: 0.99), 10)
        XCTAssertEqual(CountdownMath.remaining(duration: 10, elapsed: 1.0), 9)
        XCTAssertEqual(CountdownMath.remaining(duration: 10, elapsed: 11.2), -1)
    }

    func testConfigurationNormalization() {
        var configuration = TimerConfiguration()
        configuration.duration = 0
        configuration.warningTime = 999
        configuration.opacity = 4
        configuration.backgroundColor = "not-a-color"
        configuration.fontName = "  "
        configuration.normalize()

        XCTAssertEqual(configuration.duration, 1)
        XCTAssertEqual(configuration.warningTime, 1)
        XCTAssertEqual(configuration.opacity, 1)
        XCTAssertEqual(configuration.backgroundColor, "FFFFAA")
        XCTAssertEqual(configuration.fontName, "PingFang SC")
    }

    func testFullscreenRectangleMatchingAllowsSmallRoundingDifference() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        XCTAssertTrue(FullscreenDetector.rect(CGRect(x: 1, y: -1, width: 1_918, height: 1_082), covers: screen))
        XCTAssertFalse(FullscreenDetector.rect(CGRect(x: 0, y: 0, width: 1_200, height: 800), covers: screen))
    }

    func testPowerPointIdentification() {
        XCTAssertTrue(FullscreenDetector.isPowerPoint(bundleIdentifier: "com.microsoft.Powerpoint", applicationName: "Microsoft PowerPoint"))
        XCTAssertTrue(FullscreenDetector.isPowerPoint(bundleIdentifier: nil, applicationName: "POWERPOINT Slide Show"))
        XCTAssertFalse(FullscreenDetector.isPowerPoint(bundleIdentifier: "com.apple.Keynote", applicationName: "Keynote"))
    }

    func testWPSPresentationIdentification() {
        XCTAssertTrue(FullscreenDetector.isWPS(bundleIdentifier: "com.kingsoft.wpsoffice.mac", applicationName: "WPS Office"))
        XCTAssertTrue(FullscreenDetector.isNativeWPS(bundleIdentifier: "com.kingsoft.wpsoffice.mac"))
        XCTAssertTrue(FullscreenDetector.isWPSPresentationLayer(2_147_483_630))
        XCTAssertFalse(FullscreenDetector.isWPSPresentationLayer(0))
        XCTAssertTrue(FullscreenDetector.isWPSPresentationContent(
            bounds: CGRect(x: 0, y: 33, width: 1_470, height: 923),
            screen: CGRect(x: 0, y: 0, width: 1_470, height: 956),
            title: ""
        ))
        XCTAssertFalse(FullscreenDetector.isWPSPresentationContent(
            bounds: CGRect(x: 75, y: 33, width: 1_362, height: 822),
            screen: CGRect(x: 0, y: 0, width: 1_470, height: 956),
            title: "presentation.pptx"
        ))
        XCTAssertFalse(FullscreenDetector.isWPS(bundleIdentifier: "com.apple.Keynote", applicationName: "Keynote"))
        XCTAssertFalse(FullscreenDetector.isWPS(bundleIdentifier: "com.parallels.winapp.wps", applicationName: "WPS Office"))
    }
}
