import XCTest
import UIKit

/// Exercises actual UIView touch timestamps. Contact geometry, buffered kicks,
/// discipline and the narrow chip gesture window have deterministic core tests.
@MainActor
final class GameplayRevisionUITests: XCTestCase {
    func testOffBallTapDoesNotTackleAndHeldActionCommitsASingleSlide() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--solo"]
        app.launch()

        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        let center = action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        // Solo has no moving opponents, so the released ball remains away from
        // the stationary player while accessibility snapshots are collected.
        center.tap()
        assertValue(of: action, contains: "lastKick:pass")
        assertValue(of: action, contains: "kicks:1;")
        assertValue(of: action, contains: "chipWindow:0.00")

        center.press(forDuration: 0.05)
        assertValue(of: action, contains: "slides:0;")
        assertValue(of: action, contains: "standing:0;")
        assertValue(of: action, contains: "kicks:1;")

        center.press(forDuration: 0.35)
        assertValue(of: action, contains: "slides:1;")
        assertValue(of: action, contains: "kicks:1;")

        element("sandbox.reset", in: app).tap()
        assertValue(of: action, contains: "queue:none;")
        assertValue(of: action, contains: "height:0.00")
        assertValue(of: action, contains: "player:0.00,-2.00;")
        XCTAssertTrue(action.isHittable)
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
}
