import XCTest
import UIKit

@MainActor
final class KeeperAndKickUITests: XCTestCase {
    func testCaughtBallWaitsForManualTargetedThrowAndHeldLongThrow() {
        let app = launch("--keeper-hands")
        let action = element("sandbox.action", in: app)
        assertValue(action, contains: "keeperHands:true;")
        assertValue(action, contains: "selectedKeeper:true;")
        assertValue(action, contains: "kicks:1;")
        XCTAssertTrue(action.isEnabled)
        attach(app, name: "Keeper holding an opposition ball")
        app.buttons["sandbox.pass"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let shortThrow = NSPredicate(format: "value CONTAINS %@ OR value CONTAINS %@ OR value CONTAINS %@",
                                     "kickKind:underarm throw;", "kickKind:overarm throw;", "kickKind:high throw;")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: shortThrow, object: action)], timeout: 5),
                       .completed, "A tap must use an adaptive targeted throw, never the held long throw.")
        assertValue(action, contains: "kicks:2;")
        assertValue(action, contains: "selectedKeeper:false;")

        app.terminate()
        app.launch()
        assertValue(action, contains: "keeperHands:true;")
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.85)
        assertValue(action, contains: "kickKind:long throw;")
        assertValue(action, contains: "kicks:2;")
        attach(app, name: "Keeper held high long overarm throw")
    }

    func testGoalKickTapTargetsReceiverAndHoldSendsHighLongKick() throws {
        let app = launch("--goal-kick")
        let action = element("sandbox.action", in: app)
        assertValue(action, contains: "restart:goalKick;")
        assertValue(action, contains: "restartReady:true;")
        assertValue(action, contains: "selectedKeeper:true;")
        attach(app, name: "Goal kick — highlighted short outlet")
        let value = try XCTUnwrap(action.value as? String)
        let targetField = try XCTUnwrap(value.split(separator: ";").first { $0.hasPrefix("shortTarget:") })
        let target = try XCTUnwrap(Int(targetField.dropFirst("shortTarget:".count)),
                                   "The goal kick must offer a highlighted short receiver")
        app.buttons["sandbox.pass"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertValue(action, contains: "kickKind:goal kick pass;")
        assertValue(action, contains: "selected:\(target);")
        assertValue(action, contains: "kicks:2;")
        attach(app, name: "Goal-kick pass — receiver now controlled")

        app.terminate()
        app.launch()
        assertValue(action, contains: "restartReady:true;")
        let joystick = element("sandbox.joystick", in: app)
        let origin = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 36, dy: -36)),
                     withVelocity: .fast, thenHoldForDuration: 0.12)
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.85)
        assertValue(action, contains: "kickKind:long goal kick;")
        assertValue(action, contains: "kicks:2;")
        attach(app, name: "Goal kick — held high long clearance")
    }

    func testBackpassSelectsKeeperAtFeetAndJoystickMovesHimBeforePassing() throws {
        let app = launch("--keeper-feet")
        let action = element("sandbox.action", in: app)
        assertValue(action, contains: "selectedKeeper:true;")
        assertValue(action, contains: "keeperHands:false;")
        let before = try position(action)
        let joystick = element("sandbox.joystick", in: app)
        let origin = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 40, dy: -40)),
                     withVelocity: .fast, thenHoldForDuration: 0.65)
        let after = try position(action)
        XCTAssertGreaterThan(after.y - before.y, 1)
        assertValue(action, contains: "selectedKeeper:true;")
        assertValue(action, contains: "keeperHands:false;")
        app.buttons["sandbox.pass"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertValue(action, contains: "kicks:2;")
        attach(app, name: "Keeper plays a backpass with his feet")
    }

    func testHeldThrowInRemainsAThrowInsteadOfBecomingAShot() {
        let app = launch("--throw-in")
        let action = element("sandbox.action", in: app)
        assertValue(action, contains: "restart:throwIn;")
        assertValue(action, contains: "restartReady:true;")
        attach(app, name: "Blue throw-in ready")
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8)
        assertValue(action, contains: "kickKind:throw in;")
        assertValue(action, contains: "lastKick:pass;")
        assertValue(action, contains: "kicks:2;")
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", scenario]
        app.launch()
        XCTAssertTrue(element("sandbox.action", in: app).waitForExistence(timeout: 10))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertValue(_ element: XCUIElement, contains token: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@", token)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5),
                       .completed, "Expected \(token), got \(String(describing: element.value))", file: file, line: line)
    }

    private func position(_ element: XCUIElement) throws -> CGPoint {
        let value = try XCTUnwrap(element.value as? String)
        let field = try XCTUnwrap(value.split(separator: ";").first { $0.hasPrefix("player:") })
        let coordinates = field.dropFirst("player:".count).split(separator: ",")
        XCTAssertEqual(coordinates.count, 2)
        return CGPoint(x: try XCTUnwrap(Double(coordinates[0])), y: try XCTUnwrap(Double(coordinates[1])))
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
