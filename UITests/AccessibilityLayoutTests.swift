import XCTest
import UIKit

/// Run with the simulator's appearance and content-size settings to verify the
/// native settings layout under Dark Mode and accessibility text sizes.
@MainActor
final class AccessibilityLayoutTests: XCTestCase {
    func testSettingsRemainAccessibleWithSystemAppearanceAndTextSize() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--solo"]
        app.launch()

        let settings = app.buttons["sandbox.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        let title = app.staticTexts["Tune the feel"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(title.isHittable)
        let runningSpeed = app.sliders["Running speed"]
        // At the largest accessibility sizes, the introductory text can push
        // the first slider below the fold. Reach it with a real scroll gesture.
        let form = app.collectionViews.firstMatch
        for _ in 0..<6 where !(runningSpeed.exists && runningSpeed.isHittable) {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.72))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.28))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(runningSpeed.exists && runningSpeed.isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settings with system appearance and text size"
        attachment.lifetime = .keepAlways
        add(attachment)

        done.tap()
        let action = app.buttons["sandbox.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
    }
}
