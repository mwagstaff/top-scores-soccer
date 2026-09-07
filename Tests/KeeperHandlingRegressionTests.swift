import XCTest
@testable import TopScoresSoccer

final class KeeperHandlingRegressionTests: XCTestCase {
    private let tick = 1.0 / 60

    private func liveMatch() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -24 : 24,
                                                           y: id < 5 ? -20 : 20)
            simulation.roster[id].state.velocity = .zero
        }
        return simulation
    }

    private func opponentTouch(_ simulation: inout FootballSimulation) {
        simulation.ball = BallState(position: simulation.roster[5].state.position + .up,
                                    velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
    }

    private func bringBallToKeeper(_ simulation: inout FootballSimulation) {
        simulation.roster[4].state.position = Vector2(x: 0, y: -47)
        simulation.roster[4].state.velocity = .zero
        simulation.ball = BallState(position: Vector2(x: 0, y: -45.9), velocity: -.up * 4, mode: .free)
        for _ in 0..<8 { simulation.step(dt: tick) }
        simulation.movement = .zero
    }

    func testOpponentsCannotPushAHoldingKeeperBackwardsOrForceAnAutomaticBlueOutlet() {
        var simulation = liveMatch()
        opponentTouch(&simulation)
        bringBallToKeeper(&simulation)
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        let start = simulation.player.position
        let kicks = simulation.kickCount
        for _ in 0..<120 {
            simulation.roster[5].state.position = simulation.player.position + .up * 0.8
            simulation.roster[5].state.velocity = -.up * 8
            simulation.step(dt: tick)
        }
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertLessThan((simulation.player.position - start).length, 0.05)
        XCTAssertEqual(simulation.kickCount, kicks)
        XCTAssertGreaterThan(simulation.ball.height, simulation.tuning.airborneContactHeight)
    }

    func testBackpassStaysAtFeetAcrossRepeatedLooseBallTouches() {
        var simulation = liveMatch()
        // The last deliberate kick was blue's kickoff; marking it free must not remove the restriction.
        bringBallToKeeper(&simulation)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        for _ in 0..<90 { simulation.step(dt: tick) }
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertLessThanOrEqual(simulation.ball.height, simulation.tuning.airborneContactHeight)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertNil(simulation.lastDistributionKind)
    }

    func testOppositionTouchRestoresHandlingAfterAnOwnTeamBackpass() {
        var simulation = liveMatch()
        bringBallToKeeper(&simulation)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        opponentTouch(&simulation)
        bringBallToKeeper(&simulation)
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)
    }

    func testCancelledDistributionKeepsTheCatchButRequiresANewPress() {
        var simulation = liveMatch()
        opponentTouch(&simulation)
        bringBallToKeeper(&simulation)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.8)
        simulation.cancelInput()
        simulation.releaseAction(heldFor: 0.8)
        for _ in 0..<90 { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.kickCount, 1)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.lastDistributionKind, .overarmThrow)
        XCTAssertEqual(simulation.kickCount, 2)
    }

    func testLongOverarmThrowAcceptsLateralAftertouchWhileTappedThrowStaysStraight() {
        var caught = liveMatch()
        opponentTouch(&caught)
        bringBallToKeeper(&caught)
        var long = caught
        long.movement = .up
        long.pressAction()
        long.releaseAction(heldFor: 0.85)
        XCTAssertEqual(long.lastDistributionKind, .longThrow)
        XCTAssertGreaterThan(long.aftertouchRemaining, 0)
        let longInitialLift = long.ball.verticalVelocity
        let direction = long.ball.velocity.normalized
        long.movement = direction.perpendicular
        for _ in 0..<8 { long.step(dt: tick) }
        XCTAssertGreaterThan(long.ball.velocity.normalized.dot(direction.perpendicular), 0.03)

        var thrown = caught
        thrown.movement = .up
        thrown.pressAction()
        thrown.releaseAction(heldFor: 0.12)
        XCTAssertEqual(thrown.lastDistributionKind, .overarmThrow)
        XCTAssertEqual(thrown.aftertouchRemaining, 0)
        XCTAssertGreaterThan(longInitialLift, thrown.ball.verticalVelocity,
                             "A high long throw can trade horizontal speed for a higher arc.")
    }
}
