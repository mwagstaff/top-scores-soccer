import XCTest
@testable import TopScoresSoccer

final class AdvancedKickTests: XCTestCase {
    private let tick = 1.0 / 60

    private func shot(distance: Double, aim: Vector2, hold: Double) -> FootballSimulation {
        var simulation = FootballSimulation()
        simulation.player.position = Vector2(x: 0, y: Pitch.length / 2 - distance - 1.25)
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.movement = aim
        simulation.pressAction()
        simulation.releaseAction(heldFor: hold)
        simulation.movement = .zero
        return simulation
    }

    func testCornerAimControlsGoalCrossingAndSweetHoldScoresWhileOverholdClearsBar() {
        for side in [-1.0, 1.0] {
            var controlled = shot(distance: 16, aim: Vector2(x: side * 0.5, y: 1).normalized, hold: 0.75)
            XCTAssertEqual(controlled.lastKickKind, "shot")
            XCTAssertGreaterThan(controlled.ball.verticalVelocity, 0)
            for _ in 0..<100 where controlled.phase == .playing { controlled.step(dt: tick) }
            XCTAssertEqual(controlled.phase, .goal(north: true))
            XCTAssertGreaterThan(controlled.ball.position.x * side, 2)

            var overhit = shot(distance: 16, aim: Vector2(x: side * 0.5, y: 1).normalized, hold: 1.3)
            XCTAssertEqual(overhit.lastKickKind, "overhit shot")
            for _ in 0..<100 where overhit.phase == .playing { overhit.step(dt: tick) }
            XCTAssertEqual(overhit.phase, .outOfPlay)
            XCTAssertEqual(overhit.northGoals, 0)
            XCTAssertGreaterThan(overhit.ball.height + Pitch.ballRadius * 2, Pitch.crossbarHeight)
        }
    }

    func testShotMeterUsesSharedSweetAndOverhitTimingWithoutAutoRelease() {
        var simulation = FootballSimulation()
        simulation.player.position = Vector2(x: 0, y: 30)
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.75)
        XCTAssertEqual(simulation.powerMeterKind, .shot)
        XCTAssertTrue(simulation.powerMeterSweetSpot!.contains(simulation.powerMeterFraction))
        XCTAssertFalse(simulation.isOverchargingShot)
        simulation.updateActionHold(heldFor: 1.3)
        XCTAssertEqual(simulation.powerMeterFraction, 1, accuracy: 0.000001)
        XCTAssertTrue(simulation.isOverchargingShot)
        XCTAssertLessThan(simulation.powerMeterSweetSpot!.upperBound, simulation.powerMeterOverhitStart!)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.cancelInput()
        XCTAssertNil(simulation.powerMeterKind)
        XCTAssertEqual(simulation.powerMeterFraction, 0)
    }

    func testUnchangedCornerAimDoesNotBendUntilFreshAftertouch() {
        var simulation = FootballSimulation()
        simulation.player.position = Vector2(x: 0, y: 35)
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.movement = Vector2(x: 0.6, y: 1).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.75)
        let launch = simulation.ball.velocity.normalized
        for _ in 0..<8 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.ball.velocity.normalized.x, launch.x, accuracy: 0.000001)
        XCTAssertEqual(simulation.ball.velocity.normalized.y, launch.y, accuracy: 0.000001)
        simulation.movement = launch.perpendicular
        for _ in 0..<6 { simulation.step(dt: tick) }
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(launch.perpendicular), 0.02)
    }

    func testRaisedCornerCanBeatLowDiveWhileCentralShotMeetsUprightKeeper() {
        func attempt(side: Double) -> FootballSimulation {
            var tuning = GameplayTuning.defaults
            tuning.aiSpeedScale = 0
            var simulation = FootballSimulation(tuning: tuning, mode: .match)
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.12)
            simulation.cancelInput()
            for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
                simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -25 : 25, y: 0)
            }
            simulation.roster[0].state.position = Vector2(x: 0, y: 39.25)
            simulation.roster[9].state.position = Vector2(x: 0, y: 50.3)
            simulation.ball = BallState(position: Vector2(x: 0, y: 40.5), velocity: .zero, mode: .free)
            simulation.step(dt: tick)
            simulation.movement = Vector2(x: side * 0.6, y: 1).normalized
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.9)
            simulation.movement = .zero
            for _ in 0..<80 where simulation.phase == .playing && simulation.goalkeeperSaveCount == 0 {
                simulation.step(dt: tick)
            }
            return simulation
        }
        let center = attempt(side: 0)
        XCTAssertEqual(center.northGoals, 0)
        XCTAssertGreaterThan(center.goalkeeperSaveCount, 0)
        for side in [-1.0, 1.0] {
            let corner = attempt(side: side)
            XCTAssertEqual(corner.northGoals, 1)
            XCTAssertEqual(corner.goalkeeperSaveCount, 0)
        }
    }

    func testFreshChipStillAddsLiftAfterShotIsAirborneWithoutLoweringOverhit() {
        var simulation = shot(distance: 28, aim: .up, hold: 0.6)
        for _ in 0..<6 { simulation.step(dt: tick) }
        XCTAssertGreaterThan(simulation.ball.height, 0.05)
        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 1)
        XCTAssertGreaterThanOrEqual(simulation.ball.verticalVelocity, simulation.tuning.chipLiftSpeed - 0.31)
        var overhit = shot(distance: 16, aim: .up, hold: 1.3)
        let originalLift = overhit.ball.verticalVelocity
        overhit.movement = -.up
        overhit.step(dt: tick)
        XCTAssertGreaterThanOrEqual(overhit.ball.verticalVelocity, originalLift - 0.31)
    }

    func testUntargetedTapsStayChaseableWithoutATinyTimingBand() {
        var tiny = FootballSimulation()
        tiny.movement = Vector2(x: 1, y: 0)
        tiny.pressAction()
        tiny.releaseAction(heldFor: 0.10)
        XCTAssertEqual(tiny.lastKickKind, "knock ahead")
        var firm = FootballSimulation()
        firm.movement = Vector2(x: 1, y: 0)
        firm.pressAction()
        firm.releaseAction(heldFor: 0.23)
        XCTAssertEqual(firm.lastKickKind, "knock ahead")
        XCTAssertEqual(firm.ball.mode, .pass)
        XCTAssertEqual(firm.ball.velocity.length, tiny.ball.velocity.length, accuracy: 0.000001)
        XCTAssertEqual(firm.ball.velocity.y, 0, accuracy: 0.000001)
        XCTAssertEqual(firm.ball.height, 0)
    }

    func testThroughBallRunsOnRequestedLineAndHandsControlToRunnerAhead() {
        var simulation = FootballSimulation(mode: .passing)
        simulation.roster[1].state.position = Vector2(x: 9, y: -1)
        simulation.roster[2].state.position = Vector2(x: -25, y: -30)
        for id in 3..<6 { simulation.roster[id].state.position = Vector2(x: Double(id - 4) * 20, y: 40) }
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.23)
        // Any viable option inside the configured pass cone keeps teammate-to-teammate play.
        XCTAssertEqual(simulation.lastKickKind, "pass")
        simulation.reset()
        // With explicitly narrower assistance, the wide runner is outside the direct-pass
        // cone but can still run onto an intentional ball played along the requested line.
        simulation.tuning.passAssistAngle = 40
        simulation.roster[1].state.position = Vector2(x: 9, y: -3)
        simulation.roster[2].state.position = Vector2(x: -25, y: -30)
        for id in 3..<6 { simulation.roster[id].state.position = Vector2(x: Double(id - 4) * 20, y: 40) }
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.18)
        XCTAssertEqual(simulation.lastKickKind, "through ball")
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertEqual(simulation.ball.velocity.x, 0, accuracy: 0.000001)
        let start = simulation.player.position
        simulation.movement = Vector2(x: -0.5, y: 1).normalized
        for _ in 0..<8 { simulation.step(dt: tick) }
        XCTAssertGreaterThan(simulation.player.position.y, start.y)
        XCTAssertLessThan(simulation.player.position.x, start.x)
    }

    func testBackheelNeedsFreshReverseSwipeRelativeToPreGestureFacing() {
        var simulation = FootballSimulation()
        simulation.updateMovement(.up, timestamp: 10)
        simulation.pressAction(timestamp: 10)
        simulation.updateMovement(-.up, timestamp: 10.09)
        simulation.updateMovement(.zero, timestamp: 10.10)
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.lastKickKind, "backheel")
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertEqual(simulation.player.facing, .up)
        XCTAssertEqual(simulation.ball.verticalVelocity, 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 0)

        var ordinary = FootballSimulation()
        ordinary.updateMovement(-.up, timestamp: 20)
        ordinary.pressAction(timestamp: 20)
        ordinary.releaseAction(heldFor: 0.12)
        XCTAssertEqual(ordinary.lastKickKind, "knock ahead")

        var stale = FootballSimulation()
        stale.updateMovement(.up, timestamp: 30)
        stale.pressAction(timestamp: 30)
        stale.updateMovement(-.up, timestamp: 30.02)
        stale.releaseAction(heldFor: 0.20)
        XCTAssertNotEqual(stale.lastKickKind, "backheel")
    }

    func testReverseAfterReleaseIsChipRatherThanBackheel() {
        var simulation = FootballSimulation()
        simulation.movement = .up
        simulation.pressAction(timestamp: 4)
        simulation.releaseAction(heldFor: 0.1)
        simulation.updateMovement(-.up, timestamp: 4.13)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastKickKind, "knock ahead")
        XCTAssertEqual(simulation.chipCount, 1)
        XCTAssertGreaterThan(simulation.ball.height, 0)
    }
}
