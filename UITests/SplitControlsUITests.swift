import XCTest
import UIKit

@MainActor
final class SplitControlsUITests: XCTestCase {
    func testSeparateButtonsPassImmediatelyAndDefendWithDifferentTackles() {
        let app = launch(["--solo"])
        let shoot = element("sandbox.action", in: app)
        let pass = element("sandbox.pass", in: app)
        XCTAssertTrue(pass.isHittable)
        XCTAssertTrue(shoot.isHittable)
        XCTAssertFalse(pass.frame.intersects(shoot.frame))
        attach(app, name: "Two-button controls")
        pass.press(forDuration: 0.6)
        expect(shoot, "lastKick:pass;")
        expect(shoot, "kicks:1;")
        pass.tap()
        expect(shoot, "standing:1;")
        expect(shoot, "slides:0;")
        shoot.tap()
        expect(shoot, "slides:1;")
        expect(shoot, "kicks:1;")
        attach(app, name: "Dedicated slide tackle")
    }

    func testShootTapNearGoalNeverPassesAndOutsideRangeAlwaysLofts() {
        var app = launch(["--solo", "--shot-lane"])
        var shoot = element("sandbox.action", in: app)
        XCTAssertEqual(shoot.label, "Shoot")
        shoot.tap()
        expect(shoot, "lastKick:shot;")
        expect(shoot, "kickKind:shot;")
        expect(shoot, "kicks:1;")
        app.terminate()
        app = launch(["--solo", "--high-clearance"])
        shoot = element("sandbox.action", in: app)
        XCTAssertEqual(shoot.label, "Long Ball")
        shoot.tap()
        expect(shoot, "kickKind:long kick;")
        expect(shoot, "kicks:1;")
    }

    func testBothButtonsAndDistancePowerMeterRemainReadableInDarkMode() {
        let app = launch(["--solo", "--split-power-preview"])
        let power = element("sandbox.power", in: app)
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        XCTAssertTrue(element("sandbox.pass", in: app).isHittable)
        XCTAssertTrue(element("sandbox.action", in: app).isHittable)
        XCTAssertTrue(app.frame.contains(power.frame))
        attach(app, name: "Distance-dependent power below the player")
        app.buttons["sandbox.settings"].tap()
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertFalse(power.exists, "Pausing cancels a charge without shooting.")
        expect(element("sandbox.action", in: app), "kicks:0;")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleInterfaceStyle", "Dark"] + arguments
        app.launch()
        XCTAssertTrue(element("sandbox.action", in: app).waitForExistence(timeout: 10))
        return app
    }
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func expect(_ element: XCUIElement, _ token: String) {
        let predicate = NSPredicate(format: "value CONTAINS %@", token)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5), .completed)
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
