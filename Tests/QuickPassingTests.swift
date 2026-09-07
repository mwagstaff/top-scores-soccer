import XCTest
@testable import TopScoresSoccer

final class QuickPassingTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func exercise(movingAI: Bool = false) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        if !movingAI { tuning.aiSpeedScale = 0 }
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        for id in 3..<6 { simulation.roster[id].state.position = Vector2(x: Double(id - 4) * 20, y: 40) }
        return simulation
    }

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    func testOrdinaryQuickReleasePassesWhileDeliberateLongHoldStillShoots() {
        var quick = exercise()
        quick.movement = Vector2(x: -1, y: 0)
        quick.pressAction()
        quick.releaseAction(heldFor: 0.22)
        XCTAssertEqual(quick.lastKickKind, "pass")
        XCTAssertEqual(quick.lastKick, .pass)
        XCTAssertEqual(quick.passTargetID, 1)

        var held = exercise()
        held.player.position = Vector2(x: 0, y: 30)
        held.ball.position = held.player.position + .up * 1.25
        held.movement = .up
        held.pressAction()
        held.releaseAction(heldFor: 0.5)
        XCTAssertEqual(held.lastKick, .shot)
        XCTAssertEqual(held.lastKickKind, "shot")
        XCTAssertGreaterThan(held.ball.velocity.length, held.tuning.shotMinSpeed)
    }

    func testTinyReleaseNoiseAndNeutralLiftKeepTheDeliberatePassDirection() {
        for release in [Vector2.zero, Vector2(x: 0.08, y: 0.04)] {
            var simulation = exercise()
            simulation.movement = Vector2(x: -1, y: 0)
            simulation.pressAction()
            simulation.movement = release
            simulation.releaseAction(heldFor: 0.12)
            XCTAssertEqual(simulation.passTargetID, 1)
            XCTAssertLessThan(simulation.ball.velocity.x, 0)
            XCTAssertEqual(simulation.lastKickKind, "pass")
        }
    }

    func testDirectionChangeAndLiftAfterPressKeepCommittedReceiver() {
        var simulation = exercise()
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1, "The displayed recipient is committed at button-down.")
        XCTAssertLessThan(simulation.ball.velocity.x, 0)
    }

    func testRecentDeliberateDirectionSurvivesLiftBeforeActionButPauseClearsIt() {
        var simulation = exercise()
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.movement = .zero
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)

        var paused = exercise()
        paused.movement = Vector2(x: -1, y: 0)
        paused.cancelInput()
        paused.pressAction()
        paused.releaseAction(heldFor: 0.12)
        XCTAssertEqual(paused.passTargetID, 2, "A pause must clear pre-pause aim memory and use the current facing.")
    }

    func testRoughForwardAimFindsWideTeammateButCannotChooseBehindTheAim() {
        for angle in [70.0, 100.0] {
            var simulation = exercise()
            simulation.player.position = .zero
            simulation.ball.position = .up * 1.25
            simulation.roster[1].state.position = Vector2(x: sin(angle * .pi / 180), y: cos(angle * .pi / 180)) * 12
            simulation.roster[2].state.position = -.up * 15
            simulation.movement = .up
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.12)
            XCTAssertEqual(simulation.lastKickKind, angle < 90 ? "pass" : "knock ahead")
            XCTAssertEqual(simulation.passTargetID, angle < 90 ? 1 : nil)
        }
    }

    func testNearbyReturnOptionCanBeatDistantPerfectAlignment() {
        var simulation = exercise()
        simulation.player.position = .zero
        simulation.ball.position = .up * 1.25
        simulation.roster[1].state.position = Vector2(x: 4, y: 8)
        simulation.roster[2].state.position = Vector2(x: 0, y: 34)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.lastKickKind, "pass")
    }

    func testCloseTeammateIsAnAssistedPassInsteadOfAnAccidentalKnockAhead() {
        var simulation = exercise()
        simulation.player.position = .zero
        simulation.ball.position = .up * 1.25
        simulation.roster[1].state.position = Vector2(x: 1.9, y: 0)
        simulation.roster[2].state.position = Vector2(x: -15, y: 0)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.lastKickKind, "pass")
    }

    func testQuickPreparedReturnPassExecutesOnContactWithCapturedDirection() {
        var simulation = exercise()
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.movement = .zero
        advance(&simulation, frames: 8)
        XCTAssertEqual(simulation.receivingPlayerID, 1)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.22)
        XCTAssertEqual(simulation.queuedActionKind, "pass")
        simulation.movement = .zero
        for _ in 0..<120 where simulation.kickCount < 2 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertEqual(simulation.lastKick, .pass)
        XCTAssertEqual(simulation.passTargetID, 2)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testCommittedOrFallenTeammateIsNotAnAssistedTarget() {
        for fallen in [false, true] {
            var simulation = exercise()
            if fallen { simulation.roster[1].fallProgress = 0.5 }
            else { simulation.roster[1].isTackling = true }
            simulation.movement = Vector2(x: -1, y: 0)
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.12)
            XCTAssertNil(simulation.passTargetID)
            XCTAssertEqual(simulation.lastKickKind, "knock ahead")
        }
    }

    func testRecoveringTeammateIsNotAnAssistedTarget() {
        var simulation = exercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        simulation.releaseAction(heldFor: 0.3)
        advance(&simulation, frames: 20)
        XCTAssertEqual(simulation.actionStatus, .recovering)
        simulation.ball.position = simulation.roster[1].state.position + .up * 1.25
        simulation.ball.velocity = .zero
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertTrue(simulation.hasControl)
        simulation.movement = (simulation.roster[0].state.position - simulation.player.position).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertNotEqual(simulation.passTargetID, 0, "The former slider is still recovering and cannot offer an immediate return.")
    }

    func testRecentPasserCanReceiveReturnDespiteTheirOwnKickReacquisitionGuard() {
        var simulation = exercise()
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.movement = .zero
        simulation.ball.position = simulation.roster[1].state.position + .up * 1.25
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertTrue(simulation.hasControl)
        simulation.movement = (simulation.roster[0].state.position - simulation.player.position).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 0)
        XCTAssertEqual(simulation.kickCount, 2)
    }

    func testPasserOffersReturnLaneWithoutBendingTravellingPassTowardReceiver() {
        var simulation = exercise(movingAI: true)
        let origin = simulation.roster[0].state.position
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        let initialDirection = simulation.ball.velocity.normalized
        advance(&simulation, frames: 12)
        let passer = simulation.roster[0].state
        XCTAssertGreaterThan(passer.position.y, origin.y + 0.3)
        XCTAssertLessThan(abs(passer.velocity.x), abs(passer.velocity.y) * 0.5,
                          "The passer should move into a return lane rather than follow the pass diagonally.")
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.ball.velocity.normalized.x, initialDirection.x, accuracy: 0.000001)
        XCTAssertEqual(simulation.ball.velocity.normalized.y, initialDirection.y, accuracy: 0.000001)
    }
}
