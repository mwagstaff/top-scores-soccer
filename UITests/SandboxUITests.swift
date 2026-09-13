import XCTest
import UIKit

/// Integration checks for the real game surface, touch controls and native settings.
/// Gameplay trajectories and event edge cases are covered by the simulation tests.
@MainActor
final class SandboxUITests: XCTestCase {
    func testPortraitControlsRemainPortraitWhenDeviceRotates() throws {
        let app = launchSandbox()
        let surface = element("sandbox.surface", in: app)
        let action = element("sandbox.action", in: app)
        let score = element("sandbox.score", in: app)

        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(score.exists)

        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let frames = try waitForSettledPortraitGeometry(in: app)
            XCTAssertTrue(action.isHittable)
            XCTAssertTrue(element("sandbox.reset", in: app).isHittable)
            XCTAssertTrue(element("sandbox.settings", in: app).isHittable)
            // Use one hierarchy snapshot, so app and control frames share the
            // same completed rotation rather than separate live observations.
            let bounds = frames[0]
            let actionBounds = frames[2]
            XCTAssertGreaterThanOrEqual(actionBounds.minX, bounds.minX)
            XCTAssertLessThanOrEqual(actionBounds.maxX, bounds.maxX)
            XCTAssertGreaterThanOrEqual(actionBounds.minY, bounds.minY)
            XCTAssertLessThanOrEqual(actionBounds.maxY, bounds.maxY)
            attachScreenshot(app, name: "Portrait sandbox with device orientation \(orientation.rawValue)")
        }
    }

    func testJoystickMovesPlayerAndResetRecoversBall() throws {
        let app = launchSandbox()
        let action = element("sandbox.action", in: app)
        let joystick = element("sandbox.joystick", in: app)
        XCTAssertTrue(joystick.waitForExistence(timeout: 10))
        assertValue(of: action, contains: "player:")
        let before = try playerPosition(from: action)
        let origin = joystick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = origin.withOffset(CGVector(dx: 44, dy: -44))
        origin.press(forDuration: 0.05, thenDragTo: destination,
                     withVelocity: .fast, thenHoldForDuration: 1.0)
        let after = try playerPosition(from: action)
        XCTAssertGreaterThan(after.x - before.x, 2, "Rightward joystick input should move the player right.")
        XCTAssertGreaterThan(after.y - before.y, 2, "Upward joystick input should move the player up the pitch.")
        attachScreenshot(app, name: "Diagonal dribble")

        element("sandbox.reset", in: app).tap()
        assertValue(of: action, contains: "player:0.00,-2.00")
        assertLabel(of: element("sandbox.status", in: app), equals: "BALL AT FEET")
    }

    func testTapPassAndHeldShotUseRealTouchInput() throws {
        let app = launchSandbox()
        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        let buttonCenter = action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        // Coordinates exercise UIView touch delivery and event timing, including lift.
        app.buttons["sandbox.pass"].tap()
        assertValue(of: action, contains: "lastKick:pass")
        attachScreenshot(app, name: "Tap pass")

        element("sandbox.reset", in: app).tap()
        buttonCenter.press(forDuration: 0.9)
        assertValue(of: action, contains: "lastKick:shot")
        attachScreenshot(app, name: "Charged shot")

        element("sandbox.reset", in: app).tap()
        assertLabel(of: element("sandbox.status", in: app), equals: "BALL AT FEET")
    }

    func testSettingsRestoreDefaultsAndReturnToPlay() throws {
        let app = launchSandbox()
        let settings = element("sandbox.settings", in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let done = element("settings.done", in: app)
        let defaults = element("settings.defaults", in: app)
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        // Large text can put the first slider below the initial viewport.
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let firstSlider = app.sliders["Running speed"]
        for _ in 0..<6 where !(firstSlider.exists && firstSlider.isHittable) {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.72))
                .press(forDuration: 0.05, thenDragTo:
                    form.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.28)))
        }
        XCTAssertTrue(firstSlider.exists && firstSlider.isHittable)
        // Derive a gutter inside the row padding, just left of its slider.
        // Screen-wide gestures can land on sliders or outside the form content.
        let viewport = form.frame
        let gutterX = firstSlider.frame.minX - viewport.minX - 4
        let origin = form.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: gutterX, dy: viewport.height * 0.83))
        let end = origin.withOffset(CGVector(dx: gutterX, dy: viewport.height * 0.24))
        let haptics = app.switches["settings.haptics"].firstMatch
        for _ in 0..<18 where !(haptics.exists && haptics.isHittable) {
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .fast, thenHoldForDuration: 0)
        }
        XCTAssertTrue(haptics.exists && haptics.isHittable)
        XCTAssertEqual(haptics.value as? String, "1")
        // SwiftUI exposes the whole labelled row as a switch. Tap the visible
        // trailing control instead of the empty centre of that accessibility row.
        let hapticControl = haptics.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        hapticControl.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "0"), object: haptics)], timeout: 3), .completed)
        hapticControl.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"), object: haptics)], timeout: 3), .completed)
        attachScreenshot(app, name: "Haptic feedback setting")
        for _ in 0..<18 where !(defaults.exists && defaults.isHittable) {
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .fast, thenHoldForDuration: 0)
        }
        attachScreenshot(app, name: "Scrolled diagnostics")
        XCTAssertTrue(defaults.exists && defaults.isHittable)
        defaults.tap()
        attachScreenshot(app, name: "Tuning panel")
        done.tap()

        XCTAssertTrue(element("sandbox.action", in: app).waitForExistence(timeout: 5))
        element("sandbox.reset", in: app).tap()
        XCTAssertTrue(element("sandbox.action", in: app).isHittable)
        element("sandbox.pause", in: app).tap()
        let resume = element("sandbox.resume", in: app)
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        resume.tap()
        XCTAssertFalse(resume.exists)
    }

    private func waitForSettledPortraitGeometry(in app: XCUIApplication) throws -> [CGRect] {
        let identifiers = ["sandbox.surface", "sandbox.action", "sandbox.reset", "sandbox.settings"]
        var previousFrames: [CGRect]?
        var stableSince = Date.timeIntervalSinceReferenceDate
        var settledFrames: [CGRect]?
        var lastGeometry = "No complete accessibility snapshot"
        let settled = NSPredicate { _, _ in
            guard let snapshot = try? app.snapshot() else { return false }
            let descendants = identifiers.compactMap { self.descendant($0, in: snapshot) }
            guard descendants.count == identifiers.count else { return false }
            let frames = [snapshot.frame] + descendants.map(\.frame)
            lastGeometry = zip(["app"] + identifiers, frames)
                .map { "\($0.0): \($0.1)" }.joined(separator: "; ")
            let now = Date.timeIntervalSinceReferenceDate
            if previousFrames != frames {
                previousFrames = frames
                stableSince = now
                return false
            }
            let portrait = frames[1].height > frames[1].width
            let controlsInsideApp = frames.dropFirst(2).allSatisfy { frames[0].contains($0) }
            guard portrait, controlsInsideApp, now - stableSince >= 1 else { return false }
            settledFrames = frames
            return true
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: app)], timeout: 10)
        if result != .completed {
            attachScreenshot(app, name: "Unsettled portrait rotation geometry")
        }
        XCTAssertEqual(result, .completed, "Portrait controls did not settle inside app bounds. \(lastGeometry)")
        return try XCTUnwrap(settledFrames)
    }

    private func descendant(_ identifier: String, in snapshot: any XCUIElementSnapshot) -> (any XCUIElementSnapshot)? {
        if snapshot.identifier == identifier { return snapshot }
        for child in snapshot.children {
            if let match = descendant(identifier, in: child) { return match }
        }
        return nil
    }

    private func launchSandbox() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--solo"]
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func playerPosition(from element: XCUIElement) throws -> CGPoint {
        let value = try XCTUnwrap(element.value as? String)
        let field = try XCTUnwrap(value.split(separator: ";").first { $0.hasPrefix("player:") })
        let coordinates = field.dropFirst("player:".count).split(separator: ",")
        XCTAssertEqual(coordinates.count, 2)
        return CGPoint(x: try XCTUnwrap(Double(coordinates[0])),
                       y: try XCTUnwrap(Double(coordinates[1])))
    }

    private func assertValue(of element: XCUIElement, contains token: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@", token)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \(token), found \(String(describing: element.value))", file: file, line: line)
    }

    private func assertLabel(of element: XCUIElement, equals label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, file: file, line: line)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
