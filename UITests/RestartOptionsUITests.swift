import XCTest
import UIKit

@MainActor
final class RestartOptionsUITests: XCTestCase {
    func testPenaltyFoulBecomesLiveTapOrHeldShot() throws {
        let app = launch("--penalty")
        let action = element("sandbox.action", in: app)
        for held in [false, true] {
            if held { app.terminate(); app.launch() }
            assertValue(action, contains: "penaltyReady:true;", timeout: 12)
            assertValue(action, contains: "restart:penalty;")
            XCTAssertTrue(app.staticTexts["BLUE PENALTY"].exists)
            XCTAssertEqual(action.label, "Take penalty")
            XCTAssertFalse(app.staticTexts["PENALTY SHOOTOUT"].exists,
                           "An in-match penalty uses the live pitch, not the World Cup shootout screen.")
            let before = try integerField("kicks", in: action)
            attach(app, name: held ? "Live penalty — ready for held shot" : "Live penalty — foul awarded and ready")
            let centre = action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            if held { centre.press(forDuration: 0.6) } else { centre.tap() }
            assertValue(action, contains: "kicks:\(before + 1);")
            assertValue(action, contains: "kickKind:penalty;")
            assertValue(action, contains: "lastKick:shot;")
            assertValue(action, contains: "penaltyReady:false;")
            attach(app, name: held ? "Live penalty — held shot released" : "Live penalty — tap shoots at goal")
        }
    }

    func testFreeKickShowsShortTargetAndTapPassesToIt() throws {
        let app = launch("--free-kick")
        let action = element("sandbox.action", in: app)
        assertValue(action, contains: "freeKickReady:true;", timeout: 12)
        assertValue(action, contains: "shortOptionsReady:2;", timeout: 8)
        // Short options sit beside/behind the ball so the shot lane stays open.
        let joystick = element("sandbox.joystick", in: app)
        let origin = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: -44, dy: 0)),
                     withVelocity: .fast, thenHoldForDuration: 0.12)
        waitForTarget(action)
        _ = try integerField("target", in: action)
        XCTAssertTrue(app.staticTexts["BLUE FREE KICK"].exists)
        attach(app, name: "Free kick — nearby outlet and opponents standing back")
        let before = try integerField("kicks", in: action)
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertValue(action, contains: "kicks:\(before + 1);")
        // Native scene tests verify the immediate target handover. UI inspection takes
        // time while defenders continue playing, so check the completed restart here.
        assertValue(action, contains: "kickKind:pass;")
        assertValue(action, contains: "lastKick:pass;")
        assertValue(action, contains: "restartReady:false;")
        assertValue(action, contains: "freeKickReady:false;")
        attach(app, name: "Free kick — short pass released")
    }

    func testThrowInShowsNearbyOptionAndTapReleasesShortThrow() throws {
        let app = launch("--throw-in")
        let action = element("sandbox.action", in: app)
        assertValue(action, contains: "restart:throwIn;")
        assertValue(action, contains: "restartReady:true;")
        assertValue(action, contains: "shortOptionsReady:2;", timeout: 8)
        waitForTarget(action)
        _ = try integerField("target", in: action)
        let before = try integerField("kicks", in: action)
        attach(app, name: "Throw-in — nearby receiving options")
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertValue(action, contains: "kicks:\(before + 1);")
        assertValue(action, contains: "kickKind:throw in;")
        assertValue(action, contains: "lastKick:pass;")
        attach(app, name: "Throw-in — short tap release")
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

    private func assertValue(_ element: XCUIElement, contains token: String, timeout: TimeInterval = 5,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@", token)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout),
                       .completed, "Expected \(token)", file: file, line: line)
    }

    private func integerField(_ key: String, in element: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(element.value as? String)
        let field = try XCTUnwrap(value.split(separator: ";").first { $0.hasPrefix(key + ":") })
        return try XCTUnwrap(Int(field.dropFirst(key.count + 1)))
    }

    private func waitForTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@ AND NOT (value CONTAINS %@)",
                                    "target:", "target:none;")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 8),
                       .completed, "A teammate must arrive as a short restart option.", file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
