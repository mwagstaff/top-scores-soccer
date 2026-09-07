import XCTest
import UIKit

@MainActor
final class FloatingJoystickUITests: XCTestCase {
    func testHigherLeftTouchesRecentreAndMoveWithoutTheOldFixedArea() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--solo"]
        app.launch()
        let action = element("sandbox.action", in: app)
        let surface = element("sandbox.surface", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertTrue(surface.waitForExistence(timeout: 5))

        for location in [CGVector(dx: 0.22, dy: 0.30), CGVector(dx: 0.49, dy: 0.35)] {
            element("sandbox.reset", in: app).tap()
            let reset = NSPredicate(format: "value CONTAINS %@", "player:0.00,-2.00")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reset, object: action)], timeout: 5), .completed)
            let before = try playerPosition(from: action)
            let origin = surface.coordinate(withNormalizedOffset: location)

            // A fresh touch well above the former lower-left activation zone
            // must remain neutral until it moves, including after a previous drag.
            origin.press(forDuration: 0.25)
            let neutral = try playerPosition(from: action)
            XCTAssertEqual(neutral.x, before.x, accuracy: 0.05)
            XCTAssertEqual(neutral.y, before.y, accuracy: 0.05)
            origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: -52)),
                         withVelocity: .fast, thenHoldForDuration: 0.75)
            let after = try playerPosition(from: action)
            XCTAssertGreaterThan(after.y - before.y, 3)
            XCTAssertEqual(after.x, before.x, accuracy: 0.5)
            XCTAssertEqual(element("sandbox.joystick", in: app).value as? String,
                           "Ready: touch and drag on the left")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Floating joystick higher-left drags complete"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func playerPosition(from element: XCUIElement) throws -> CGPoint {
        let value = try XCTUnwrap(element.value as? String)
        let field = try XCTUnwrap(value.split(separator: ";").first { $0.hasPrefix("player:") })
        let coordinates = field.dropFirst("player:".count).split(separator: ",")
        XCTAssertEqual(coordinates.count, 2)
        return CGPoint(x: try XCTUnwrap(Double(coordinates[0])), y: try XCTUnwrap(Double(coordinates[1])))
    }
}
