import UIKit
import XCTest
@testable import TopScoresSoccer

@MainActor
final class PenaltyPresentationTests: XCTestCase {
    func testPenaltyKeepsFallThenWhistleCardAndRecoveryBeforeTheKick() throws {
        let (scene, victim) = pendingPenaltyScene()
        var hud = SandboxHUD()
        var whistles = 0
        scene.onHUDUpdate = { hud = $0 }
        scene.onWhistle = { whistles += 1 }
        var time = 10.0
        for _ in 0..<15 where scene.simulation.phase == .playing { advance(scene, time: &time) }
        XCTAssertEqual(scene.simulation.phase, .foulContact(team: .blue))
        XCTAssertEqual(scene.simulation.awardedFoulRestartKind, .penalty)
        XCTAssertEqual(hud.status, "LATE CHALLENGE")
        XCTAssertEqual(whistles, 0)
        XCTAssertNil(hud.card)
        XCTAssertFalse(scene.simulation.isTakingPenalty)
        advance(scene, time: &time, frames: 12)
        let fall = scene.simulation.roster[victim].fallProgress
        XCTAssertGreaterThan(fall, 0)
        XCTAssertLessThan(fall, 1)

        scene.setGameplayPaused(true)
        time += 30
        scene.update(time)
        XCTAssertEqual(scene.simulation.roster[victim].fallProgress, fall)
        XCTAssertEqual(whistles, 0)
        scene.setGameplayPaused(false)
        for _ in 0..<180 {
            if case .freeKick = scene.simulation.phase { break }
            advance(scene, time: &time)
        }
        XCTAssertEqual(scene.simulation.phase, .freeKick(team: .blue))
        XCTAssertEqual(hud.status, "BLUE PENALTY")
        XCTAssertEqual(whistles, 1)
        XCTAssertEqual(scene.simulation.roster[victim].fallProgress, 1)
        let foul = try XCTUnwrap(scene.simulation.lastFoul)
        let expectedCard: String? = foul.card == .red ? "red" : foul.card == .yellow ? "yellow" : nil
        XCTAssertEqual(hud.card, expectedCard)
        XCTAssertNil(hud.power)
        let kicks = scene.simulation.kickCount
        scene.releaseAction(heldFor: 0.8)
        for _ in 0..<240 where !scene.simulation.isTakingPenalty { advance(scene, time: &time) }
        XCTAssertTrue(scene.simulation.isTakingPenalty)
        XCTAssertEqual(scene.simulation.matchRestart?.kind, .penalty)
        XCTAssertEqual(scene.simulation.kickCount, kicks, "The pre-award release must not take the penalty.")
        XCTAssertEqual(whistles, 1)
        XCTAssertEqual(hud.status, "BLUE PENALTY")
        XCTAssertTrue(hud.detail.contains("Tap to shoot"))
        XCTAssertEqual(scene.simulation.ball.position.x, 0, accuracy: 0.001)
        XCTAssertEqual(scene.simulation.ball.position.y, Pitch.length / 2 - 11, accuracy: 0.001)
        XCTAssertNil(scene.simulation.passTargetID)
        XCTAssertTrue(scene.simulation.footballers.allSatisfy { $0.fallProgress == 0 })
    }

    func testPenaltyTapAndHeldShotUseLivePitchControlsAndShotMeter() throws {
        for held in [false, true] {
            let (scene, _) = pendingPenaltyScene()
            var time = 100.0
            for _ in 0..<360 where !scene.simulation.isTakingPenalty { advance(scene, time: &time) }
            XCTAssertTrue(scene.simulation.isTakingPenalty)
            let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
            input.scene = scene
            scene.onControlFeedback = { [weak input] status, hasBall, curving in
                input?.feedback(status: status, hasBall: hasBall, curving: curving)
            }
            var hud = SandboxHUD()
            scene.onHUDUpdate = { hud = $0 }
            scene.setMovement(Vector2(x: 0.08, y: 1).normalized)
            input.feedback(status: scene.simulation.actionStatus, hasBall: true, curving: false)
            XCTAssertEqual(input.actionTitle, "SHOOT")
            let action = try XCTUnwrap((input.accessibilityElements as? [UIAccessibilityElement])?
                .first { $0.accessibilityIdentifier == "sandbox.action" })
            XCTAssertEqual(action.accessibilityLabel, "Take penalty")
            XCTAssertTrue(action.accessibilityHint?.contains("Tap to shoot") == true)
            let sweet = KickMechanics.shotSweetSpotDurations(tuning: scene.simulation.tuning)
            let duration = held ? (sweet.lowerBound + sweet.upperBound) / 2 : 0.08
            let before = scene.simulation.kickCount
            scene.pressAction()
            scene.simulation.updateActionHold(heldFor: duration)
            scene.refreshHUD()
            input.feedback(status: scene.simulation.actionStatus, hasBall: true, curving: false)
            XCTAssertEqual(scene.powerFeedback?.kind, .shot)
            XCTAssertNotNil(scene.powerFeedback?.sweetSpot)
            XCTAssertEqual(input.actionTitle, "SHOOT")
            XCTAssertTrue(hud.status.hasPrefix("PENALTY ·"))
            if held {
                XCTAssertTrue(scene.powerFeedback?.isSweet == true)
                attach(input, named: "Live penalty — green shot band and SHOOT control")
            }
            scene.releaseAction(heldFor: duration)
            XCTAssertEqual(scene.simulation.kickCount, before + 1)
            XCTAssertEqual(scene.simulation.lastKickKind, "penalty")
            XCTAssertEqual(scene.simulation.ball.mode, .shot)
            XCTAssertGreaterThan(scene.simulation.ball.velocity.y, 0)
            XCTAssertFalse(scene.simulation.isTakingPenalty)
            XCTAssertNil(scene.powerFeedback)
        }
    }

    /// The defender's real standing challenge reaches the attacker before the
    /// ball. No foul, penalty, possession or restart private state is assigned.
    private func pendingPenaltyScene() -> (GameScene, Int) {
        let scene = GameScene(mode: .match)
        scene.simulation.tuning.aiSpeedScale = 0
        scene.simulation.pressAction()
        scene.simulation.releaseAction(heldFor: 0.12)
        scene.simulation.cancelInput()
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state = PlayerState(position: Vector2(
                x: Double(id % 4 - 2) * 12, y: id < 5 ? -20 : 20))
        }
        scene.simulation.roster[4].state.position = Vector2(x: 0, y: -50)
        scene.simulation.roster[9].state.position = Vector2(x: 0, y: 50)
        let spot = Vector2(x: 0, y: 42)
        scene.simulation.roster[0].state = PlayerState(position: spot)
        scene.simulation.ball = BallState(position: spot + .up * 0.9, mode: .free)
        scene.simulation.step(dt: 1 / 60)
        scene.simulation.roster[5].state = PlayerState(position: spot - .up * 1.44, facing: .up)
        scene.simulation.ball = BallState(position: spot + Vector2(x: 0.9, y: -0.9), mode: .controlled)
        return (scene, 0)
    }

    private func advance(_ scene: GameScene, time: inout Double, frames: Int = 1) {
        for _ in 0..<frames { time += 1 / 60; scene.update(time) }
        scene.refreshHUD()
    }

    private func attach(_ input: InputController, named name: String) {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 440, height: 306)).image { context in
            UIColor(red: 0.08, green: 0.29, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 440, height: 306))
            context.cgContext.translateBy(x: 0, y: -650)
            input.draw(input.bounds)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
