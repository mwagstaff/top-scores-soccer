import XCTest
import UIKit

/// Explicit practice launch enters the six-player passing and defending exercise. Detailed
/// AI selection and tackle timing are covered deterministically in core tests.
@MainActor
final class PassingExerciseUITests: XCTestCase {
    func testPassingExercisePassAndPracticeModeSelection() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--passing"]
        app.launch()

        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        assertValue(of: action, contains: "mode:passing")
        assertValue(of: action, contains: "players:6")
        XCTAssertTrue(element("sandbox.joystick", in: app).exists)
        XCTAssertTrue(element("sandbox.status", in: app).exists)
        XCTAssertTrue(element("sandbox.score", in: app).exists)
        XCTAssertTrue(action.isHittable)

        // Reset immediately before the pass so active defenders cannot make the
        // initial possession depend on how long accessibility snapshots take.
        element("sandbox.reset", in: app).tap()
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertValue(of: action, contains: "lastKick:pass")
        attachScreenshot(app, name: "Pass and defend exercise")

        element("sandbox.settings", in: app).tap()
        let picker = element("settings.mode", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        selectMode("Solo practice", with: picker, in: app)
        element("settings.done", in: app).tap()
        assertValue(of: action, contains: "mode:solo")
        assertValue(of: action, contains: "players:1")
        XCTAssertTrue(action.isHittable)

        element("sandbox.settings", in: app).tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        selectMode("Pass & defend", with: picker, in: app)
        element("settings.done", in: app).tap()
        assertValue(of: action, contains: "mode:passing")
        assertValue(of: action, contains: "players:6")
        XCTAssertTrue(action.isHittable)
    }

    private func selectMode(_ label: String, with picker: XCUIElement, in app: XCUIApplication) {
        let option = app.buttons.matching(identifier: label).firstMatch
        if !(option.exists && option.isHittable) {
            picker.tap()
        }
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        XCTAssertTrue(option.isHittable)
        option.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertValue(of element: XCUIElement, contains token: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@", token)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \(token), found \(String(describing: element.value))", file: file, line: line)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
