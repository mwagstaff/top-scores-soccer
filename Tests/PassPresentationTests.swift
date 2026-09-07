import UIKit
import XCTest
@testable import TopScoresSoccer

@MainActor
final class PassPresentationTests: XCTestCase {
    func testReceivingControlRemainsExplicitWhenFirstTimeKickIsAvailable() throws {
        let scene = passingScene()
        let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        input.scene = scene
        var hud = SandboxHUD()
        scene.onHUDUpdate = { hud = $0 }
        scene.setMovement(.up)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.08)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 1)
        // Keep an actual assisted pass context, now entering the receiver's
        // first-time-action window. Both guidance conditions are true together.
        scene.simulation.ball.position = scene.simulation.player.position - .up * 8
        scene.simulation.ball.velocity = .up * 16
        scene.refreshHUD()
        input.feedback(status: scene.simulation.actionStatus, hasBall: scene.simulation.hasControl, curving: false)
        XCTAssertTrue(scene.simulation.isControllingPassReceiver)
        XCTAssertTrue(scene.simulation.canPrepareReceivingKick)
        XCTAssertEqual(hud.status, "CONTROL THE RECEIVER")
        XCTAssertEqual(hud.detail, "Steer to move · Centre to meet the ball")
        XCTAssertEqual(hud.selectedPlayerName, "YOU · PLAYER 2")
        let action = try XCTUnwrap((input.accessibilityElements as? [UIAccessibilityElement])?
            .first { $0.accessibilityIdentifier == "sandbox.action" })
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            XCTAssertTrue(action.accessibilityValue?.contains("You control the intended receiver") == true)
        }
    }

    func testPassingGuidanceDistinguishesTeammateTargetFromOpenSpace() {
        let scene = passingScene()
        var hud = SandboxHUD()
        scene.onHUDUpdate = { hud = $0 }
        scene.setMovement(.up)
        scene.refreshHUD()
        XCTAssertEqual(scene.simulation.passTargetID, 1)
        XCTAssertEqual(hud.detail, "Tap to pass to #2 · Hold for power")
        scene.setMovement(Vector2(x: 1, y: 0))
        scene.refreshHUD()
        XCTAssertNil(scene.simulation.passTargetID)
        XCTAssertEqual(hud.detail, "Tap into space · Hold for power")
    }

    func testSceneUsesReceiverFramingAndRestoresNormalScaleOnReset() throws {
        let scene = passingScene()
        scene.size = CGSize(width: 393, height: 852)
        scene.simulation.roster[0].state.position = Vector2(x: -20, y: 0)
        scene.simulation.roster[1].state.position = Vector2(x: 20, y: 0)
        scene.simulation.ball.position = Vector2(x: -18.75, y: 0)
        scene.update(1)
        scene.setMovement(Vector2(x: 1, y: 0))
        scene.pressAction()
        scene.releaseAction(heldFor: 0.08)
        scene.update(1 + 1 / 60)
        XCTAssertTrue(scene.simulation.isControllingPassReceiver)
        let camera = try XCTUnwrap(scene.camera)
        for point in [scene.simulation.player.position, scene.simulation.ball.position] {
            let x = (point.x - camera.position.x) / camera.xScale + scene.size.width / 2
            let y = (point.y * 0.86 - camera.position.y) / camera.yScale + scene.size.height / 2
            XCTAssertGreaterThan(x, 10)
            XCTAssertLessThan(x, scene.size.width - 10)
            XCTAssertGreaterThan(y - 1.8 / camera.yScale, 300,
                                 "The player marker must clear the full identity and guidance panel.")
            XCTAssertLessThan(y, scene.size.height - 170)
        }
        XCTAssertTrue(try XCTUnwrap(camera.childNode(withName: "controlled-receiver-edge")).isHidden)
        scene.resetSandbox()
        XCTAssertEqual(camera.xScale, CameraController.recommendedScale(viewport: scene.size,
                                                                       topInset: 170, bottomInset: 300), accuracy: 0.000001)
        XCTAssertTrue(try XCTUnwrap(camera.childNode(withName: "controlled-receiver-edge")).isHidden)
    }

    private func passingScene() -> GameScene {
        let scene = GameScene(mode: .passing)
        scene.simulation.tuning.aiSpeedScale = 0
        let positions = [Vector2.zero, Vector2(x: 0, y: 24), Vector2(x: -25, y: -25),
                         Vector2(x: 25, y: 35), Vector2(x: -25, y: 35), Vector2(x: 25, y: -25)]
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state = PlayerState(position: positions[id])
        }
        scene.simulation.ball = BallState(position: .up * 1.25, mode: .controlled)
        return scene
    }
}
