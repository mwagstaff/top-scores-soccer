import XCTest
import UIKit

@MainActor
final class OffsideUITests: XCTestCase {
    func testOffsideAwardWaitsForManualKickAndPauseDoesNotLoseRestart() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--offside"]
        app.launch()
        let action = app.descendants(matching: .any).matching(identifier: "sandbox.action").firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        check(action, "restart:offside;")
        check(action, "restartReady:true;")
        let status = app.descendants(matching: .any).matching(identifier: "sandbox.status").firstMatch
        XCTAssertEqual(status.label, "BLUE FREE KICK")
        let clock = app.descendants(matching: .any).matching(identifier: "match.clock").firstMatch
        let stopped = clock.label
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Offside indirect kick ready"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["sandbox.pause"].tap()
        app.buttons["sandbox.resume"].tap()
        XCTAssertEqual(clock.label, stopped)
        check(action, "restart:offside;")
        app.buttons["sandbox.pass"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        check(action, "kicks:2;")
        check(action, "restart:none;")
    }

    private func check(_ element: XCUIElement, _ token: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", token), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Expected \(token); got \(String(describing: element.value))", file: file, line: line)
    }
}
