import XCTest
import UIKit

@MainActor
final class AerialPlayUITests: XCTestCase {
    func testTapHeadsReachableBallWithoutSlideAndFreshLaunchAllowsHeldClearance() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--solo", "--header"]
        app.launch()
        let action = app.descendants(matching: .any).matching(identifier: "sandbox.action").firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        check(action, "headers:0;")
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Reachable header touch control"
        before.lifetime = .keepAlways
        add(before)
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.12)
        check(action, "headers:1;")
        check(action, "kickKind:header;")
        check(action, "slides:0;")
        app.terminate()
        app.launchArguments = ["--uitesting", "--solo", "--high-clearance"]
        app.launch()
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.95)
        check(action, "kickKind:long kick;")
        check(action, "kicks:1;")
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "After high defensive clearance"
        after.lifetime = .keepAlways
        add(after)
    }

    private func check(_ element: XCUIElement, _ token: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", token), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Expected \(token); got \(String(describing: element.value))", file: file, line: line)
    }
}
