import UIKit
import XCTest
@testable import TopScoresSoccer

@MainActor
final class FloatingJoystickTests: XCTestCase {
    func testUpperAndCentreLeftStartsWorkWhileActionKeepsPriority() {
        let (input, scene) = controls()
        for point in [CGPoint(x: 30, y: 180), CGPoint(x: 215, y: 300), CGPoint(x: 100, y: 860)] {
            XCTAssertEqual(input.touchRole(at: point), .movement)
            XCTAssertTrue(input.beginMovement(at: point))
            XCTAssertEqual(input.joystickOrigin, point)
            XCTAssertEqual(scene.simulation.movement, .zero)
            input.endMovement()
        }
        XCTAssertNil(input.touchRole(at: CGPoint(x: 300, y: 300)))
        XCTAssertNil(input.touchRole(at: CGPoint(x: -1, y: 300)))
        XCTAssertNil(input.touchRole(at: CGPoint(x: 100, y: 957)))
        XCTAssertEqual(input.touchRole(at: CGPoint(x: 354, y: 868)), .action)

        // Even in a narrow intermediate layout, the PASS hit target
        // takes precedence where it overlaps the left half of the surface.
        input.bounds.size.width = 260
        XCTAssertEqual(input.touchRole(at: CGPoint(x: 125, y: 868)), .pass)
        XCTAssertFalse(input.beginMovement(at: CGPoint(x: 125, y: 868)))
    }

    func testEveryTouchStartsNeutralAndRecentresExactlyWithoutPreviousDrag() {
        let (input, scene) = controls()
        let first = CGPoint(x: 85, y: 300)
        XCTAssertTrue(input.beginMovement(at: first))
        input.moveMovement(to: CGPoint(x: first.x + 52, y: first.y))
        XCTAssertEqual(scene.simulation.movement.x, 1, accuracy: 0.000001)
        input.endMovement()
        XCTAssertEqual(scene.simulation.movement, .zero)

        let second = CGPoint(x: 210, y: 210)
        XCTAssertTrue(input.beginMovement(at: second))
        XCTAssertEqual(input.joystickOrigin, second)
        XCTAssertEqual(input.joystickOffset, .zero)
        XCTAssertEqual(scene.simulation.movement, .zero)
        input.moveMovement(to: CGPoint(x: second.x, y: second.y - 52))
        XCTAssertEqual(scene.simulation.movement.x, 0, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.movement.y, 1, accuracy: 0.000001)
    }

    func testDeadZoneAndMaximumDragStayRelativeToTheTouchdown() {
        let (input, scene) = controls()
        let origin = CGPoint(x: 190, y: 280)
        XCTAssertTrue(input.beginMovement(at: origin))
        input.moveMovement(to: CGPoint(x: origin.x + 6, y: origin.y))
        XCTAssertEqual(scene.simulation.movement, .zero)
        input.moveMovement(to: CGPoint(x: origin.x + 26, y: origin.y))
        XCTAssertEqual(scene.simulation.movement.x, (0.5 - 0.12) / 0.88, accuracy: 0.000001)

        // Once captured, a thumb may cross the centre line and ACTION artwork
        // without changing roles or shifting its original neutral point.
        input.moveMovement(to: CGPoint(x: 600, y: origin.y))
        XCTAssertEqual(input.joystickOrigin, origin)
        XCTAssertEqual(input.joystickOffset.x, 52, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.movement.x, 1, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.movement.y, 0, accuracy: 0.000001)
    }

    func testSecondMovementStartCannotStealTheCapturedThumb() {
        let (input, scene) = controls()
        let origin = CGPoint(x: 40, y: 250)
        XCTAssertTrue(input.beginMovement(at: origin))
        input.moveMovement(to: CGPoint(x: 92, y: 250))
        XCTAssertFalse(input.beginMovement(at: CGPoint(x: 200, y: 600)))
        XCTAssertEqual(input.joystickOrigin, origin)
        XCTAssertEqual(scene.simulation.movement.x, 1, accuracy: 0.000001)
    }

    func testEndingMovementLeavesAnIndependentActionPressHeld() {
        let (input, scene) = controls()
        XCTAssertTrue(input.beginMovement(at: CGPoint(x: 100, y: 300)))
        input.moveMovement(to: CGPoint(x: 100, y: 248))
        scene.pressAction()
        XCTAssertEqual(scene.simulation.actionStatus, .pressed)
        input.endMovement()
        XCTAssertEqual(scene.simulation.movement, .zero)
        XCTAssertEqual(scene.simulation.actionStatus, .pressed)
        scene.releaseAction(heldFor: 0.05)
        XCTAssertEqual(scene.simulation.kickCount, 1)
    }

    func testLayoutChangeCancelsMovementAndActionWithoutReleasingAKick() {
        let (input, scene) = controls()
        XCTAssertTrue(input.beginMovement(at: CGPoint(x: 100, y: 300)))
        input.moveMovement(to: CGPoint(x: 100, y: 248))
        scene.pressAction()
        input.bounds.size.height = 900
        input.setNeedsLayout()
        input.layoutIfNeeded()
        XCTAssertNil(input.joystickOrigin)
        XCTAssertEqual(input.joystickOffset, .zero)
        XCTAssertEqual(scene.simulation.movement, .zero)
        XCTAssertEqual(scene.simulation.actionStatus, .idle)
        input.moveMovement(to: CGPoint(x: 100, y: 180))
        scene.releaseAction(heldFor: 1)
        XCTAssertEqual(scene.simulation.movement, .zero)
        XCTAssertEqual(scene.simulation.kickCount, 0)
        XCTAssertEqual(scene.simulation.slideCount, 0)
    }

    func testPauseRequiresFreshTouchAndAccessibilityFollowsActiveCentre() throws {
        let (input, scene) = controls()
        let joystick = try XCTUnwrap((input.accessibilityElements as? [UIAccessibilityElement])?.first)
        let restingFrame = joystick.accessibilityFrameInContainerSpace
        let origin = CGPoint(x: 200, y: 260)
        XCTAssertTrue(input.beginMovement(at: origin))
        XCTAssertEqual(joystick.accessibilityFrameInContainerSpace.midX, origin.x, accuracy: 0.000001)
        XCTAssertEqual(joystick.accessibilityFrameInContainerSpace.midY, origin.y, accuracy: 0.000001)
        input.moveMovement(to: CGPoint(x: 200, y: 208))
        scene.setGameplayPaused(true)
        XCTAssertNil(input.joystickOrigin)
        XCTAssertEqual(joystick.accessibilityFrameInContainerSpace, restingFrame)
        XCTAssertFalse(input.beginMovement(at: origin))
        scene.setGameplayPaused(false)
        input.moveMovement(to: CGPoint(x: 200, y: 150))
        XCTAssertEqual(scene.simulation.movement, .zero)
        XCTAssertTrue(input.beginMovement(at: CGPoint(x: 55, y: 400)))
        XCTAssertEqual(scene.simulation.movement, .zero)
    }

    private func controls() -> (InputController, GameScene) {
        let scene = GameScene()
        scene.setMode(.solo)
        let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        input.scene = scene
        scene.onResetInput = { [weak input] in input?.clearTouches() }
        input.setNeedsLayout()
        input.layoutIfNeeded()
        return (input, scene)
    }
}
