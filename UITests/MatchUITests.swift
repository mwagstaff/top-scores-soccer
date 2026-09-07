import XCTest
import UIKit

@MainActor
final class MatchUITests: XCTestCase {
    func testDefaultMatchKickoffClockAndPracticeModes() throws {
        let app = launchMatch()
        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        assertValue(action, contains: "mode:match;")
        assertValue(action, contains: "players:10;")
        assertValue(action, contains: "keepers:2;")
        assertValue(action, contains: "selectedKeeper:false;")
        let clock = element("match.clock", in: app)
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        XCTAssertEqual(clock.label, "Time remaining 3:00")
        waitForKickoff(in: app)
        attach(app, name: "5v5 kickoff and match clock")
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertValue(action, contains: "kicks:1;")
        let clockRunning = NSPredicate(format: "label != %@", "Time remaining 3:00")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: clockRunning, object: clock)], timeout: 5), .completed)

        element("sandbox.pause", in: app).tap()
        XCTAssertTrue(element("sandbox.resume", in: app).waitForExistence(timeout: 5))
        element("sandbox.resume", in: app).tap()
        element("sandbox.settings", in: app).tap()
        chooseMode("Pass & defend", in: app)
        element("settings.done", in: app).tap()
        assertValue(action, contains: "mode:passing;")
        assertValue(action, contains: "players:6;")
        XCTAssertFalse(clock.exists)

        element("sandbox.settings", in: app).tap()
        chooseMode("5v5 match", in: app)
        element("settings.done", in: app).tap()
        assertValue(action, contains: "mode:match;")
        assertValue(action, contains: "players:10;")
        waitForKickoff(in: app)
        XCTAssertEqual(clock.label, "Time remaining 3:00")
    }

    func testFullTimeShowsResultAndPlayAgainResetsMatch() {
        let app = launchMatch(short: true)
        waitForKickoff(in: app)
        let action = element("sandbox.action", in: app)
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let again = app.buttons["match.play-again"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(element("match.clock", in: app).label, "Time remaining 0:00")
        XCTAssertEqual(element("match.result", in: app).label, "Honours even")
        XCTAssertTrue(again.isHittable)
        attach(app, name: "Full time and play again")
        again.tap()
        XCTAssertFalse(again.exists)
        waitForKickoff(in: app)
        XCTAssertEqual(element("match.clock", in: app).label, "Time remaining 0:02")
        assertValue(action, contains: "kicks:0;")
        assertValue(action, contains: "selectedKeeper:false;")
    }

    private func launchMatch(short: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + (short ? ["--short-match"] : [])
        app.launch()
        return app
    }

    private func waitForKickoff(in app: XCUIApplication) {
        let status = element("sandbox.status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "label == %@", "BLUE KICKOFF")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: status)], timeout: 5), .completed)
        assertValue(element("sandbox.action", in: app), contains: "restart:kickoff;")
        assertValue(element("sandbox.action", in: app), contains: "restartReady:true;")
    }

    private func chooseMode(_ name: String, in app: XCUIApplication) {
        let picker = element("settings.mode", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let option = app.buttons.matching(identifier: name).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertValue(_ element: XCUIElement, contains token: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@", token)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5),
                       .completed, "Expected \(token)", file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
