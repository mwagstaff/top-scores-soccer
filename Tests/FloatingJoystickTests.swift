import UIKit
import XCTest
@testable import TopScoresSoccer

@MainActor
final class FloatingJoystickTests: XCTestCase {
    func testEntireLeftHalfStartsMovementWhileRightSideActionsKeepPriority() {
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
        let action = try? XCTUnwrap((input.accessibilityElements as? [UIAccessibilityElement])?
            .first { $0.accessibilityIdentifier == "sandbox.action" })
        let actionFrame = action?.accessibilityFrameInContainerSpace ?? .zero
        XCTAssertEqual(input.touchRole(at: CGPoint(x: actionFrame.midX, y: actionFrame.midY)), .action)

        // Even if a control overlaps the left half in a narrow intermediate
        // layout, the whole left side remains a reliable movement surface.
        input.bounds.size.width = 260
        XCTAssertEqual(input.touchRole(at: CGPoint(x: 125, y: 868)), .movement)
        XCTAssertTrue(input.beginMovement(at: CGPoint(x: 125, y: 868)))
        input.endMovement()
        XCTAssertEqual(input.touchRole(at: CGPoint(x: 136, y: 814)), .pass)
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

    func testFreeKickResetKeepsHeldJoystickActiveAndRestoresItsDirection() {
        let (input, scene) = controls()
        let origin = CGPoint(x: 100, y: 300)
        XCTAssertTrue(input.beginMovement(at: origin))
        input.moveMovement(to: CGPoint(x: origin.x + 52, y: origin.y))
        XCTAssertEqual(scene.simulation.movement.x, 1, accuracy: 0.000001)

        scene.cancelTouches()

        XCTAssertEqual(input.joystickOrigin, origin)
        XCTAssertEqual(input.joystickOffset.x, 52, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.movement.x, 1, accuracy: 0.000001,
                       "A scene reset must reapply the direction of a finger that is still down.")
    }

    func testJoystickPressedDuringFoulStaysVisibleAndAimsThePreparedFreeKick() {
        let scene = GameScene(mode: .passing)
        scene.simulation.tuning.aiSpeedScale = 0
        scene.simulation.tuning.foulContactDuration = 0.05
        scene.simulation.tuning.freeKickDelay = 0.05
        scene.simulation.player.position = .zero
        scene.simulation.ball.position = Vector2(x: 0.9, y: -0.9)
        scene.simulation.roster[3].state.position = Vector2(x: 0, y: -1.44)
        scene.simulation.roster[3].state.facing = .up
        scene.simulation.step(dt: 1.0 / 60.0)
        XCTAssertEqual(scene.simulation.phase, .foulContact(team: .blue))

        let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        input.scene = scene
        scene.onResetInput = { [weak input] in input?.sceneDidResetInput() }
        input.layoutIfNeeded()
        let origin = CGPoint(x: 100, y: 300)
        XCTAssertTrue(input.beginMovement(at: origin),
                      "The left side should capture a thumb even while the foul sequence is finishing.")
        input.moveMovement(to: CGPoint(x: origin.x + 52, y: origin.y))
        XCTAssertEqual(input.joystickOrigin, origin)
        XCTAssertEqual(scene.simulation.movement, .zero,
                       "Stoppage time may retain the thumb without moving a player.")

        var time = 100.0
        for _ in 0..<30 where !scene.simulation.isTakingFreeKick {
            time += 1.0 / 60.0
            scene.update(time)
        }

        XCTAssertTrue(scene.simulation.isTakingFreeKick)
        XCTAssertEqual(input.joystickOrigin, origin,
                       "Preparing the free kick must not make the held joystick disappear.")
        XCTAssertEqual(scene.simulation.movement.x, 1, accuracy: 0.000001)
        time += 1.0 / 60.0
        scene.update(time)
        XCTAssertGreaterThan(scene.simulation.player.facing.x, 0.99)
    }

    private func controls() -> (InputController, GameScene) {
        let scene = GameScene()
        scene.setMode(.solo)
        let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        input.scene = scene
        scene.onResetInput = { [weak input] in input?.sceneDidResetInput() }
        input.setNeedsLayout()
        input.layoutIfNeeded()
        return (input, scene)
    }
}
