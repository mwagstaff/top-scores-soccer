import XCTest
import UIKit
@testable import TopScoresSoccer

@MainActor
final class MatchSceneTests: XCTestCase {
    private func advance(_ scene: GameScene, time: inout Double, frames: Int) {
        for _ in 0..<frames { time += 1.0 / 60; scene.update(time) }
        scene.refreshHUD()
    }

    func testKickoffAllowsStationaryAimAndStartsClockOnRelease() {
        let scene = GameScene(mode: .match)
        var hud = SandboxHUD()
        scene.onHUDUpdate = { hud = $0 }
        var time = 0.0
        let spot = scene.simulation.player.position
        scene.setMovement(Vector2(x: -1, y: 0))
        advance(scene, time: &time, frames: 90)
        XCTAssertEqual(scene.simulation.player.position, spot)
        XCTAssertLessThan(scene.simulation.player.facing.x, -0.9)
        XCTAssertEqual(hud.status, "BLUE KICKOFF")
        XCTAssertEqual(hud.clockText, "3:00")
        scene.pressAction()
        scene.releaseAction(heldFor: 0.12)
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertLessThan(scene.simulation.ball.velocity.x, 0)
        XCTAssertNil(scene.simulation.matchRestart)
        advance(scene, time: &time, frames: 75)
        XCTAssertLessThan(scene.simulation.matchTimeRemaining, 179)
    }

    func testPausingStopsMatchClockAndCancelsHeldActionWithoutCatchUp() {
        let scene = GameScene(mode: .match)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.12)
        var time = 0.0
        advance(scene, time: &time, frames: 30)
        let elapsed = scene.simulation.matchTimeElapsed
        scene.setMovement(.up)
        scene.pressAction()
        scene.setGameplayPaused(true)
        time += 30
        scene.update(time)
        XCTAssertEqual(scene.simulation.matchTimeElapsed, elapsed)
        XCTAssertEqual(scene.simulation.movement, .zero)
        scene.setGameplayPaused(false)
        advance(scene, time: &time, frames: 1)
        XCTAssertEqual(scene.simulation.matchTimeElapsed, elapsed + 1.0 / 60, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.kickCount, 1)
    }

    func testFullTimeWhistlesOnceRejectsInputAndNewMatchResetsPresentation() {
        let scene = GameScene(mode: .match)
        scene.simulation.tuning.matchDuration = 1
        var hud = SandboxHUD()
        var whistles = 0
        scene.onHUDUpdate = { hud = $0 }
        scene.onWhistle = { whistles += 1 }
        scene.pressAction()
        scene.releaseAction(heldFor: 0.12)
        var time = 0.0
        advance(scene, time: &time, frames: 90)
        XCTAssertEqual(scene.simulation.phase, .fullTime)
        XCTAssertEqual(hud.status, "FULL TIME")
        XCTAssertEqual(hud.clockText, "0:00")
        XCTAssertEqual(hud.matchResult, "Honours even")
        XCTAssertEqual(whistles, 1)
        let ball = scene.simulation.ball.position
        scene.setMovement(.up)
        scene.pressAction()
        scene.releaseAction(heldFor: 1)
        advance(scene, time: &time, frames: 90)
        XCTAssertEqual(scene.simulation.ball.position, ball)
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertEqual(whistles, 1)
        scene.resetSandbox()
        XCTAssertEqual(hud.status, "BLUE KICKOFF")
        XCTAssertEqual(hud.clockText, "0:01")
        XCTAssertEqual(scene.simulation.kickCount, 0)
        advance(scene, time: &time, frames: 30)
        XCTAssertEqual(whistles, 1)
    }

    func testChangingModesRemovesClockAndRestoresFullMatchRoster() {
        let scene = GameScene(mode: .match)
        var hud = SandboxHUD()
        scene.onHUDUpdate = { hud = $0 }
        scene.setMode(.passing)
        XCTAssertNil(hud.matchTimeRemaining)
        XCTAssertEqual(scene.simulation.footballers.count, 6)
        scene.setMode(.solo)
        XCTAssertNil(hud.matchTimeRemaining)
        XCTAssertEqual(scene.simulation.footballers.count, 1)
        scene.setMode(.match)
        XCTAssertEqual(hud.matchTimeRemaining, 180)
        XCTAssertEqual(scene.simulation.footballers.count, 10)
        XCTAssertEqual(hud.status, "BLUE KICKOFF")
    }

    func testClockRoundsUpAndResultUsesBlueAndRedScores() {
        var hud = SandboxHUD()
        hud.matchTimeRemaining = 179.01
        XCTAssertEqual(hud.clockText, "3:00")
        hud.matchTimeRemaining = 60
        XCTAssertEqual(hud.clockText, "1:00")
        hud.matchTimeRemaining = -0.01
        XCTAssertEqual(hud.clockText, "0:00")
        hud.northGoals = 2
        XCTAssertEqual(hud.matchResult, "Blue win")
        hud.southGoals = 3
        XCTAssertEqual(hud.matchResult, "Red win")
        hud.phase = .practiceEnded(losingTeam: .blue)
        XCTAssertEqual(hud.matchResult, "Match abandoned")
    }

    func testBlueKeeperHoldAllowsManualDistributionAndKickoffRestoresOutfieldControl() throws {
        let scene = GameScene(mode: .match)
        let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        input.scene = scene
        let action = try XCTUnwrap((input.accessibilityElements as? [UIAccessibilityElement])?.last)
        input.feedback(status: .idle, hasBall: true, curving: false)
        XCTAssertFalse(action.accessibilityTraits.contains(.notEnabled))
        scene.pressAction()
        scene.releaseAction(heldFor: 0.12)
        scene.simulation.tuning.aiSpeedScale = 0
        scene.simulation.ball = BallState(position: scene.simulation.roster[5].state.position + .up,
                                          velocity: .zero, mode: .free)
        scene.simulation.step(dt: 1.0 / 60)
        scene.simulation.roster[4].state.position = Vector2(x: 0, y: -48)
        scene.simulation.ball = BallState(position: Vector2(x: 0, y: -46.8), velocity: -.up * 4, mode: .free)
        scene.simulation.step(dt: 1.0 / 60)
        XCTAssertEqual(scene.simulation.goalkeeperPossessionTeam, .blue)
        XCTAssertTrue(scene.simulation.isHoldingGoalkeeper)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 4)
        input.feedback(status: .idle, hasBall: true, curving: false)
        XCTAssertFalse(action.accessibilityTraits.contains(.notEnabled))
        scene.pressAction()
        scene.releaseAction(heldFor: 0.12)
        XCTAssertFalse(scene.simulation.isHoldingGoalkeeper)
        XCTAssertEqual(scene.simulation.kickCount, 2)
        scene.resetSandbox()
        input.feedback(status: .idle, hasBall: true, curving: false)
        XCTAssertFalse(action.accessibilityTraits.contains(.notEnabled))
    }
}
