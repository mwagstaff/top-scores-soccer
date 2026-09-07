import XCTest
@testable import TopScoresSoccer

final class ReceiverMovementPriorityTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func exercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.player.facing = .up
        simulation.ball.position = .up * 1.25
        simulation.roster[1].state.position = .up * 22
        simulation.roster[2].state.position = Vector2(x: -25, y: -25)
        for id in 3..<6 {
            simulation.roster[id].state.position = Vector2(x: Double(id - 4) * 25, y: 43)
        }
        for id in 1..<6 { simulation.roster[id].state.velocity = .zero }
        XCTAssertTrue(simulation.hasControl)
        return simulation
    }

    private func pass(_ simulation: inout FootballSimulation, aim: Vector2 = .up, duration: Double = 0.12) {
        simulation.movement = aim
        simulation.pressAction()
        simulation.releaseAction(heldFor: duration)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertFalse(simulation.hasControl)
    }

    func testUnchangedPassDirectionImmediatelyRunsReceiverEvenAwayFromIncomingBall() {
        var simulation = exercise()
        pass(&simulation)
        let start = simulation.player.position
        let ballDirection = simulation.ball.velocity.normalized
        // Keep precisely the original input; there is no fresh gesture or neutral sample.
        simulation.step(dt: tick)
        XCTAssertGreaterThan(simulation.player.velocity.y, 0.1)
        XCTAssertGreaterThan(simulation.player.position.y, start.y)
        XCTAssertEqual(simulation.player.position.x, start.x, accuracy: 0.000001)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.switchCount, 1)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.ball.velocity.normalized, ballDirection)
        XCTAssertEqual(simulation.chipCount, 0)
    }

    func testSmallNonzeroInputControlsReceiverProportionallyWithoutAnExtraDeadZone() {
        for magnitude in [0.01, 0.04] {
            var simulation = exercise()
            pass(&simulation)
            let start = simulation.player.position
            // These are valid values already processed by the touch controller's dead zone.
            simulation.movement = Vector2(x: magnitude, y: 0)
            simulation.step(dt: tick)
            XCTAssertGreaterThan(simulation.player.position.x, start.x)
            XCTAssertGreaterThan(simulation.player.velocity.x, 0.01)
            XCTAssertLessThan(simulation.player.velocity.length, 1, "Small input should not become a full-speed automatic run")
            XCTAssertEqual(simulation.player.position.y, start.y, accuracy: 0.000001)
            XCTAssertEqual(simulation.selectedPlayerID, 1)
            XCTAssertTrue(simulation.isControllingPassReceiver)
        }
    }

    func testReversalChangesAccelerationOnTheNextTickWithoutWaitingForReception() {
        var simulation = exercise()
        pass(&simulation)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.step(dt: tick)
        let rightwardVelocity = simulation.player.velocity.x
        XCTAssertGreaterThan(rightwardVelocity, 0)
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.step(dt: tick)
        XCTAssertLessThan(simulation.player.velocity.x, rightwardVelocity,
                          "Steering reverses acceleration immediately while retaining ordinary momentum")
        simulation.step(dt: tick)
        XCTAssertLessThan(simulation.player.velocity.x, 0)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testNeutralMovingReceiverMeetsLedPhysicalPassAndKeepsControl() {
        var simulation = exercise()
        simulation.roster[1].state.position = Vector2(x: 3, y: 28)
        simulation.roster[1].state.velocity = Vector2(x: 8, y: 0)
        let start = simulation.roster[1].state.position
        pass(&simulation)
        simulation.movement = .zero
        let ballDirection = simulation.ball.velocity.normalized
        for _ in 0..<180 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertGreaterThan(abs(simulation.player.position.x - start.x), 0.05)
        XCTAssertLessThan(abs(simulation.player.position.x - start.x), 2)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.switchCount, 1)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertEqual(simulation.movement, .zero)
        XCTAssertGreaterThan(ballDirection.x, 0)
        for _ in 0..<30 { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertLessThan((simulation.ball.position - simulation.player.position).length, 2)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.chipCount, 0)
    }

    func testThroughBallRunnerUsesHeldDirectionOrNeutralInterceptionAsRequested() {
        var directed = exercise()
        directed.tuning.passAssistAngle = 40
        directed.roster[1].state.position = Vector2(x: 9, y: 7)
        pass(&directed, duration: 0.18)
        XCTAssertEqual(directed.lastKickKind, "through ball")
        let start = directed.player.position
        var automatic = directed
        automatic.movement = .zero
        for _ in 0..<3 {
            directed.step(dt: tick)
            automatic.step(dt: tick)
        }
        XCTAssertGreaterThan(directed.player.position.y, start.y)
        XCTAssertEqual(directed.player.position.x, start.x, accuracy: 0.000001)
        XCTAssertLessThan(automatic.player.position.x, start.x)
        XCTAssertEqual(directed.selectedPlayerID, 1)
        XCTAssertEqual(automatic.selectedPlayerID, 1)
        XCTAssertEqual(directed.ball.velocity.x, 0, accuracy: 0.000001)
        XCTAssertEqual(automatic.ball.velocity.x, 0, accuracy: 0.000001)
        XCTAssertFalse(directed.hasControl)
        XCTAssertFalse(automatic.hasControl)
    }

    func testNeutralReceiverChasesSlowOrJustPassedBallInsteadOfStanding() {
        for passed in [false, true] {
            var simulation = exercise()
            pass(&simulation)
            let start = simulation.player.position
            let offset = passed ? Vector2(x: 0, y: 3.2) : Vector2(x: -4, y: 0)
            simulation.ball = BallState(position: start + offset,
                velocity: passed ? .up * 8 : Vector2(x: 0.5, y: 0), mode: .pass)
            simulation.movement = .zero
            simulation.step(dt: tick)
            XCTAssertGreaterThan(simulation.player.velocity.dot(offset.normalized), 0.1)
            XCTAssertGreaterThan((simulation.player.position - start).dot(offset.normalized), 0)
            XCTAssertEqual(simulation.selectedPlayerID, 1)
            XCTAssertTrue(simulation.isControllingPassReceiver)
            XCTAssertFalse(simulation.hasControl)
            XCTAssertEqual(simulation.movement, .zero)
        }
    }

    private func keeperBackpass(movingKeeper: Bool) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -26 : 26,
                                                           y: simulation.roster[id].team == .blue ? -15 : 20)
            simulation.roster[id].state.velocity = .zero
        }
        simulation.ball = BallState(position: Vector2(x: 20, y: 0), mode: .free)
        for _ in 0..<20 { simulation.step(dt: tick) }
        simulation.roster[0].state.position = Vector2(x: 0, y: -32)
        simulation.roster[0].state.velocity = .zero
        simulation.ball = BallState(position: Vector2(x: 0, y: -33.2), mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertTrue(simulation.hasControl)
        simulation.roster[4].state.position = Vector2(x: 3, y: -46)
        simulation.roster[4].state.velocity = movingKeeper ? Vector2(x: 6, y: 0) : .zero
        simulation.movement = -.up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertEqual(simulation.passTargetID, 4)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertFalse(simulation.hasControl)
        return simulation
    }

    func testNeutralKeeperMeetsLedBackpassWithFeetWithoutAutomaticRetreat() {
        var simulation = keeperBackpass(movingKeeper: true)
        let start = simulation.player.position
        simulation.movement = .zero
        for _ in 0..<150 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertGreaterThan(abs(simulation.player.position.x - start.x), 0.05)
        XCTAssertLessThan(abs(simulation.player.position.x - start.x), 2)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertTrue(simulation.isControllingGoalkeeper)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
        XCTAssertEqual(simulation.phase, .playing)
    }

    func testKeeperBackpassAlsoHonoursUnchangedLaunchDirectionImmediately() {
        var simulation = keeperBackpass(movingKeeper: false)
        let start = simulation.player.position
        simulation.step(dt: tick)
        XCTAssertLessThan(simulation.player.velocity.y, -0.1)
        XCTAssertLessThan(simulation.player.position.y, start.y)
        XCTAssertEqual(simulation.player.position.x, start.x, accuracy: 0.000001)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
    }
}
