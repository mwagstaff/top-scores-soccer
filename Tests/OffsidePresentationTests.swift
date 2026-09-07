import XCTest
@testable import TopScoresSoccer

@MainActor
final class OffsidePresentationTests: XCTestCase {
    func testOffsideWhistlesOnceShowsAwardAndPausesWithoutAReplay() throws {
        let scene = try pendingReception(attacking: .blue)
        var hud = SandboxHUD()
        var whistles = 0
        scene.onHUDUpdate = { hud = $0 }
        scene.onWhistle = { whistles += 1 }
        var time = 10.0
        advance(scene, time: &time, frames: 1)
        XCTAssertEqual(scene.simulation.phase, .restart(kind: .offside, team: .red))
        XCTAssertEqual(scene.simulation.offsideCount, 1)
        XCTAssertEqual(hud.status, "OFFSIDE")
        XCTAssertTrue(hud.detail.contains("Red indirect free kick"))
        XCTAssertTrue(hud.detail.contains("Clock paused"))
        XCTAssertNil(hud.card)
        XCTAssertNil(hud.power)
        XCTAssertEqual(scene.simulation.foulCount, 0)
        XCTAssertEqual(whistles, 1)

        let remaining = scene.simulation.matchTimeRemaining
        scene.setGameplayPaused(true)
        time += 30
        scene.update(time)
        XCTAssertEqual(scene.simulation.matchTimeRemaining, remaining)
        XCTAssertEqual(whistles, 1)
        scene.setGameplayPaused(false)
        advance(scene, time: &time, frames: 3)
        XCTAssertEqual(whistles, 1, "Resuming the same offside decision must not repeat its whistle.")
        XCTAssertEqual(scene.simulation.matchTimeRemaining, remaining)
        for _ in 0..<180 where !scene.simulation.isTakingRestart {
            advance(scene, time: &time, frames: 1)
        }
        XCTAssertTrue(scene.simulation.isTakingRestart)
        XCTAssertEqual(scene.simulation.matchRestart?.kind, .offside)
        XCTAssertEqual(hud.status, "RED FREE KICK")
        XCTAssertTrue(hud.detail.contains("indirect kick"))
        XCTAssertEqual(whistles, 1)
    }

    func testOwnIndirectKickKeepsItsReminderDuringChargeAndNeedsFreshInput() throws {
        let scene = try pendingReception(attacking: .red)
        var hud = SandboxHUD()
        scene.onHUDUpdate = { hud = $0 }
        var time = 20.0
        advance(scene, time: &time, frames: 1)
        XCTAssertEqual(scene.simulation.phase, .restart(kind: .offside, team: .blue))
        let kicks = scene.simulation.kickCount
        // A stale release during the decision cannot take the awarded restart.
        scene.releaseAction(heldFor: 0.8)
        for _ in 0..<180 where !scene.simulation.isTakingRestart {
            advance(scene, time: &time, frames: 1)
        }
        XCTAssertEqual(scene.simulation.kickCount, kicks)
        XCTAssertEqual(hud.status, "BLUE FREE KICK")
        XCTAssertTrue(hud.detail.contains("Indirect kick"))
        XCTAssertNil(hud.card)
        let position = scene.simulation.player.position
        scene.setMovement(Vector2(x: 1, y: 0))
        advance(scene, time: &time, frames: 3)
        XCTAssertEqual(scene.simulation.player.position, position)
        scene.pressAction()
        scene.simulation.updateActionHold(heldFor: 0.7)
        scene.refreshHUD()
        XCTAssertNotNil(hud.power)
        XCTAssertTrue(hud.detail.contains("Another player must touch before a goal"))
        scene.releaseAction(heldFor: 0.7)
        XCTAssertEqual(scene.simulation.kickCount, kicks + 1)
        XCTAssertNil(scene.simulation.matchRestart)
        XCTAssertNil(hud.power)
    }

    func testResetDropsAnUnpresentedOffsideDecisionAndItsOldInput() throws {
        let scene = try pendingReception(attacking: .blue)
        // Commit the actual involvement without yet presenting a scene frame.
        scene.simulation.step(dt: 1.0 / 60)
        XCTAssertEqual(scene.simulation.phase, .restart(kind: .offside, team: .red))
        var whistles = 0
        var hud = SandboxHUD()
        scene.onWhistle = { whistles += 1 }
        scene.onHUDUpdate = { hud = $0 }
        scene.resetSandbox()
        var time = 40.0
        advance(scene, time: &time, frames: 10)
        XCTAssertEqual(whistles, 0)
        XCTAssertEqual(scene.simulation.offsideCount, 0)
        XCTAssertEqual(hud.status, "BLUE KICKOFF")
        XCTAssertNil(hud.card)
        XCTAssertEqual(scene.simulation.kickCount, 0)
        XCTAssertEqual(scene.simulation.movement, .zero)
    }

    /// Set up a teammate touch with a receiver beyond the second-last defender,
    /// then leave the incoming ball just before their actual acquisition step.
    /// Neither the decision phase nor restart ownership is written by the test.
    private func pendingReception(attacking team: Team) throws -> GameScene {
        let scene = GameScene(mode: .match)
        scene.simulation.tuning.aiSpeedScale = 0
        let openingTaker = scene.simulation.selectedPlayerID
        scene.simulation.pressAction()
        scene.simulation.releaseAction(heldFor: 0.12)
        let attack = team == .blue ? 1.0 : -1.0
        let outfield = scene.simulation.roster.filter {
            $0.team == team && !$0.isGoalkeeper && $0.id != openingTaker
        }.map(\.id)
        let carrier = try XCTUnwrap(outfield.first)
        let receiver = try XCTUnwrap(outfield.dropFirst().first)
        for id in scene.simulation.roster.indices {
            let player = scene.simulation.roster[id]
            let direction = player.team == .blue ? 1.0 : -1.0
            scene.simulation.roster[id].state.position = Vector2(
                x: player.isGoalkeeper ? 0 : id.isMultiple(of: 2) ? -25 : 25,
                y: -direction * (player.isGoalkeeper ? 48 : 10))
            scene.simulation.roster[id].state.velocity = .zero
        }
        scene.simulation.roster[carrier].state.position = Vector2(x: 0, y: 5 * attack)
        scene.simulation.roster[receiver].state.position = Vector2(x: 0, y: 20 * attack)
        scene.simulation.ball = BallState(position: Vector2(x: 0, y: 6 * attack),
                                          velocity: .zero, mode: .free)
        scene.simulation.step(dt: 1.0 / 60)
        XCTAssertEqual(scene.simulation.possessionTeam, team)
        XCTAssertEqual(scene.simulation.offsideCount, 0)
        scene.simulation.ball = BallState(position: Vector2(x: 0, y: 19 * attack),
                                          velocity: .up * (3 * attack), mode: .pass)
        return scene
    }

    private func advance(_ scene: GameScene, time: inout Double, frames: Int) {
        for _ in 0..<frames { time += 1.0 / 60; scene.update(time) }
        scene.refreshHUD()
    }
}
