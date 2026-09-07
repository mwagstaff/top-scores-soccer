import UIKit
import XCTest
@testable import TopScoresSoccer

@MainActor
final class ReceiverJoystickTests: XCTestCase {
    private let tick = 1.0 / 60.0
    private let origin = CGPoint(x: 160, y: 360)

    func testHeldFloatingJoystickDrivesReceiverWithoutAnotherMovementSample() throws {
        let (scene, input) = fixture()
        var frameTime = 100.0
        scene.update(frameTime)
        let radius = try beginJoystick(input)
        input.moveMovement(to: CGPoint(x: origin.x, y: origin.y - radius))
        let heldMovement = scene.simulation.movement
        XCTAssertEqual(heldMovement.y, 1, accuracy: 0.000001)

        scene.pressAction()
        scene.releaseAction(heldFor: 0.08)
        assertReceiverSelectedBeforeContact(scene)
        let receiverStart = scene.simulation.player.position
        let passerStart = scene.simulation.roster[0].state.position

        // The thumb stays exactly where it aimed the pass. No new move event
        // should be needed to make that direction belong to the selected receiver.
        advance(scene, frames: 12, time: &frameTime)

        assertReceiverSelectedBeforeContact(scene)
        XCTAssertEqual(input.joystickOrigin, origin)
        XCTAssertEqual(input.joystickOffset.y, -radius, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.movement, heldMovement)
        XCTAssertGreaterThan(scene.simulation.player.position.y, receiverStart.y + 0.3)
        XCTAssertGreaterThan(scene.simulation.player.velocity.y, 0)
        XCTAssertEqual(scene.simulation.player.position.x, receiverStart.x, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.roster[0].state.position, passerStart,
                       "The held thumb now controls the receiver, not the passer.")
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertEqual(scene.simulation.chipCount, 0)
    }

    func testSmallDragBeyondTouchDeadZoneMovesReceiverBeforeContact() throws {
        let (scene, input) = fixture()
        var frameTime = 200.0
        scene.update(frameTime)
        let radius = try beginJoystick(input)
        input.moveMovement(to: CGPoint(x: origin.x, y: origin.y - radius))
        scene.pressAction()
        scene.releaseAction(heldFor: 0.08)
        assertReceiverSelectedBeforeContact(scene)

        let deadZone = scene.simulation.tuning.joystickDeadZone
        // First verify the real controller keeps an inside-dead-zone drag neutral.
        input.moveMovement(to: CGPoint(x: origin.x + radius * (deadZone - 0.01), y: origin.y))
        XCTAssertEqual(scene.simulation.movement, .zero)
        input.moveMovement(to: CGPoint(x: origin.x + radius * (deadZone + 0.025), y: origin.y))
        let intendedMovement = scene.simulation.movement
        XCTAssertGreaterThan(intendedMovement.x, 0)
        XCTAssertLessThan(intendedMovement.length, 0.15,
                          "This deliberately exercises a drag that the old second dead zone swallowed.")
        XCTAssertEqual(intendedMovement.y, 0, accuracy: 0.000001)
        let receiverStart = scene.simulation.player.position

        advance(scene, frames: 8, time: &frameTime)

        assertReceiverSelectedBeforeContact(scene)
        XCTAssertEqual(scene.simulation.movement, intendedMovement)
        XCTAssertGreaterThan(scene.simulation.player.position.x, receiverStart.x + 0.005)
        XCTAssertGreaterThan(scene.simulation.player.velocity.x, 0)
        XCTAssertEqual(scene.simulation.player.position.y, receiverStart.y, accuracy: 0.000001,
                       "Automatic reception must not add its own direction over a deliberate sideways drag.")
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertEqual(scene.simulation.chipCount, 0)
    }

    func testHeldThumbReceivesAndRetainsTenTwentyFiveAndFortyMetrePasses() throws {
        for distance in [10.0, 25, 40] {
            let (scene, input) = fixture(distance: distance)
            var frameTime = 300.0
            scene.update(frameTime)
            let radius = try beginJoystick(input)
            input.moveMovement(to: CGPoint(x: origin.x, y: origin.y - radius))
            let heldMovement = scene.simulation.movement
            XCTAssertEqual(heldMovement, .up)
            XCTAssertEqual(scene.simulation.passTargetID, 1)

            // The right thumb taps ACTION while the floating left thumb remains
            // held. No further left-thumb move event occurs anywhere in this play.
            scene.pressAction()
            scene.releaseAction(heldFor: 0.12)
            XCTAssertEqual(scene.simulation.selectedPlayerID, 1)
            XCTAssertEqual(scene.simulation.passTargetID, 1)
            let beforeReception = scene.simulation.player.position
            receiveAndRetain(scene, expectedMovement: heldMovement,
                             time: &frameTime, context: "held thumb, \(distance)m")
            XCTAssertEqual(input.joystickOrigin, origin)
            XCTAssertEqual(input.joystickOffset.y, -radius, accuracy: 0.000001)
            XCTAssertGreaterThan(scene.simulation.player.position.y, beforeReception.y + 8,
                                 "The whole receive-and-run sequence must respond to the still-held thumb.")
        }
    }

    func testDirectionChangeDuringActionKeepsTargetThenNeutralReceivesAndRetains() throws {
        for distance in [10.0, 25, 40] {
            let (scene, input) = fixture(distance: distance)
            // This second teammate makes the changed rightward aim meaningful:
            // the committed upfield recipient must not silently become this player.
            scene.simulation.roster[2].state.position = Vector2(x: 18, y: -38)
            var frameTime = 400.0
            scene.update(frameTime)
            let radius = try beginJoystick(input)
            input.moveMovement(to: CGPoint(x: origin.x, y: origin.y - radius))
            XCTAssertEqual(scene.simulation.passTargetID, 1)
            let actionStart = ProcessInfo.processInfo.systemUptime
            scene.pressAction(startedAt: actionStart)
            input.moveMovement(to: CGPoint(x: origin.x + radius, y: origin.y), timestamp: actionStart + 0.06)
            XCTAssertEqual(scene.simulation.movement, Vector2(x: 1, y: 0))
            XCTAssertEqual(scene.simulation.passTargetID, 1,
                           "The preview remains with the teammate chosen by the independent ACTION press.")
            scene.releaseAction(heldFor: 0.12)
            XCTAssertEqual(scene.simulation.selectedPlayerID, 1)
            XCTAssertEqual(scene.simulation.passTargetID, 1)
            XCTAssertEqual(input.joystickOrigin, origin)

            // Lift the movement thumb only after the kick leaves the foot. Neutral
            // assistance must meet that physical delivery and retain its first touch.
            input.endMovement(timestamp: actionStart + 0.13)
            XCTAssertNil(input.joystickOrigin)
            XCTAssertEqual(scene.simulation.movement, .zero)
            receiveAndRetain(scene, expectedMovement: .zero,
                             time: &frameTime, context: "target locked, changed thumb then neutral, \(distance)m")
        }
    }

    private func receiveAndRetain(_ scene: GameScene, expectedMovement: Vector2,
                                  time: inout TimeInterval, context: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var received = false
        for _ in 0..<360 {
            advance(scene, frames: 1, time: &time)
            guard scene.simulation.phase == .playing && scene.simulation.selectedPlayerID == 1 else {
                XCTFail("Pass lost its selected receiver before contact: \(context)", file: file, line: line)
                return
            }
            XCTAssertEqual(scene.simulation.movement, expectedMovement, file: file, line: line)
            if scene.simulation.hasControl { received = true; break }
        }
        XCTAssertTrue(received, "No controlled reception: \(context)", file: file, line: line)
        guard received else { return }
        // One extra render interval covers floating-point accumulation at the
        // scene's fixed-step boundary, so at least two simulation seconds elapse.
        for frame in 1...121 {
            advance(scene, frames: 1, time: &time)
            guard scene.simulation.phase == .playing && scene.simulation.selectedPlayerID == 1
                    && scene.simulation.hasControl else {
                XCTFail("Reception lost after \(Double(frame) * tick)s of dribbling: \(context)", file: file, line: line)
                return
            }
            XCTAssertEqual(scene.simulation.movement, expectedMovement, file: file, line: line)
        }
        XCTAssertEqual(scene.simulation.kickCount, 1, file: file, line: line)
        XCTAssertEqual(scene.simulation.chipCount, 0, file: file, line: line)
        XCTAssertEqual(scene.simulation.slideCount, 0, file: file, line: line)
        XCTAssertLessThanOrEqual((scene.simulation.ball.position - scene.simulation.player.position).length,
                                scene.simulation.tuning.controlReleaseDistance, context, file: file, line: line)
    }

    private func fixture(distance: Double) -> (GameScene, InputController) {
        let (scene, input) = fixture()
        let start = Vector2(x: 0, y: -40)
        scene.simulation.roster[0].state = PlayerState(position: start)
        scene.simulation.ball = BallState(position: start + .up * 1.25, mode: .controlled)
        scene.simulation.roster[1].state = PlayerState(position: scene.simulation.ball.position + .up * distance)
        scene.simulation.roster[2].state = PlayerState(position: Vector2(x: -28, y: 46))
        for id in 3..<6 {
            scene.simulation.roster[id].state = PlayerState(position: Vector2(x: Double(id - 4) * 27, y: -49))
        }
        return (scene, input)
    }

    private func fixture() -> (GameScene, InputController) {
        let scene = GameScene(mode: .passing)
        scene.simulation.tuning.aiSpeedScale = 0
        let positions = [Vector2.zero, Vector2(x: 0, y: 24), Vector2(x: -25, y: -25),
                         Vector2(x: 25, y: 35), Vector2(x: -25, y: 35), Vector2(x: 25, y: -25)]
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state = PlayerState(position: positions[id])
        }
        scene.simulation.ball = BallState(position: .up * 1.25, mode: .controlled)
        let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        input.scene = scene
        scene.onResetInput = { [weak input] in input?.clearTouches() }
        scene.onControlFeedback = { [weak input] status, hasBall, curving in
            input?.feedback(status: status, hasBall: hasBall, curving: curving)
        }
        input.setNeedsLayout()
        input.layoutIfNeeded()
        return (scene, input)
    }

    private func beginJoystick(_ input: InputController) throws -> CGFloat {
        XCTAssertTrue(input.beginMovement(at: origin))
        let element = try XCTUnwrap((input.accessibilityElements as? [UIAccessibilityElement])?
            .first { $0.accessibilityIdentifier == "sandbox.joystick" })
        return element.accessibilityFrameInContainerSpace.width / 2
    }

    private func assertReceiverSelectedBeforeContact(_ scene: GameScene,
                                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(scene.simulation.selectedPlayerID, 1, file: file, line: line)
        XCTAssertEqual(scene.simulation.passTargetID, 1, file: file, line: line)
        XCTAssertTrue(scene.simulation.isControllingPassReceiver, file: file, line: line)
        XCTAssertEqual(scene.simulation.ball.mode, .pass, file: file, line: line)
        XCTAssertFalse(scene.simulation.hasControl, file: file, line: line)
        XCTAssertGreaterThan((scene.simulation.ball.position - scene.simulation.player.position).length, 10,
                             "The regression concerns steering while the ball is still travelling.", file: file, line: line)
    }

    private func advance(_ scene: GameScene, frames: Int, time: inout TimeInterval) {
        for _ in 0..<frames {
            time += tick
            scene.update(time)
        }
    }
}
