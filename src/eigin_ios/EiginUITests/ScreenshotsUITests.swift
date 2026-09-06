import XCTest

/// Captures the App Store screenshot scenes. Each method launches the dev app
/// with `--screenshot-scenario <name>` — the app seeds the scene's data and
/// fakes, renders it, and the test snapshots it (see `fastlane/Snapfile`).
///
/// Anchors use identifiers, not text, so copy or locale changes can't break
/// the captures. The `index:` numbering is the App Store listing order.
@MainActor
final class ScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCareScene() {
        capture("care", index: 1)
    }

    func testOnDeviceScene() {
        capture("on-device", index: 2)
    }

    func testAsksFirstScene() {
        capture("asks-first", index: 3)
    }

    func testMemoryScene() {
        capture("memory", index: 4)
    }

    func testFollowUpScene() {
        capture("follow-up", index: 5)
    }

    func testConnectionsScene() {
        capture("connections", index: 6)
    }

    private func capture(_ scenario: String, index: Int) {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["--screenshot-scenario", scenario]
        app.launch()

        XCTAssertTrue(
            waitForScene(app),
            "Scene \(scenario) did not render"
        )

        // Let SwiftUI settle (markdown, theme, sheet presentation).
        Thread.sleep(forTimeInterval: 2)

        snapshot("0\(index)-\(scenario)")
    }

    private func waitForScene(_ app: XCUIApplication) -> Bool {
        // The anchor element wraps the whole scene root.
        app.otherElements[ScreenshotAnchor.identifier].waitForExistence(timeout: 30)
    }
}

/// Mirrors `ScreenshotSceneRoot.anchorIdentifier`; the app and UI test targets
/// share no code, so the value is spelled out in both.
private enum ScreenshotAnchor {
    static let identifier = "screenshot-scene"
}
