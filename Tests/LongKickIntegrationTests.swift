import XCTest
@testable import TopScoresSoccer

final class LongKickIntegrationTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func controlledBall(at point: Vector2, aim: Vector2 = .up,
                                mode: ExerciseMode = .passing) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: mode)
        simulation.player.position = point - aim * 1.25
        simulation.player.velocity = .zero
        simulation.player.facing = aim
        simulation.ball.position = point
        simulation.ball.velocity = .zero
        simulation.ball.height = 0
        simulation.ball.verticalVelocity = 0
        for id in simulation.roster.indices where id != simulation.selectedPlayerID {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? 28 : -28,
                                                           y: 27 + Double(id) * 3)
            simulation.roster[id].state.velocity = .zero
        }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertTrue(simulation.canKick)
        return simulation
    }

    private func hold(_ duration: Double, aim: Vector2, in simulation: inout FootballSimulation) {
        simulation.movement = aim
        simulation.pressAction()
        simulation.updateActionHold(heldFor: duration)
        XCTAssertEqual(simulation.kickCount, 0, "Charging waits for release")
        simulation.releaseAction(heldFor: duration)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertFalse(simulation.hasControl)
    }

    func testDefensiveGoalwardHoldClearsHighInRequestedDirectionWithoutGoalSnap() {
        let aim = Vector2(x: 0.25, y: 1).normalized
        for mode in [ExerciseMode.solo, .passing] {
            var simulation = controlledBall(at: Vector2(x: 5, y: -35), aim: aim, mode: mode)
            let start = simulation.ball.position
            hold(0.9, aim: aim, in: &simulation)
            XCTAssertEqual(simulation.lastKickKind, "long kick")
            XCTAssertGreaterThan(simulation.ball.verticalVelocity, 12)
            XCTAssertEqual(simulation.ball.velocity.normalized.x, aim.x, accuracy: 0.000001)
            XCTAssertEqual(simulation.ball.velocity.normalized.y, aim.y, accuracy: 0.000001)
            simulation.movement = .zero
            var maximumHeight = 0.0
            for _ in 0..<84 {
                simulation.step(dt: tick)
                maximumHeight = max(maximumHeight, simulation.ball.height)
            }
            XCTAssertEqual(simulation.phase, .playing)
            XCTAssertGreaterThan(maximumHeight, 4)
            XCTAssertGreaterThan((simulation.ball.position - start).dot(aim), 56)
            XCTAssertEqual((simulation.ball.position - start).dot(aim.perpendicular), 0, accuracy: 0.0001)
            XCTAssertEqual(simulation.chipCount, 0, "The loft comes from the hold, without a pull-back gesture")
        }
    }

    func testSidewaysHeldClearanceTravelsAcrossPitchInAirBeforeFirstBounce() {
        let right = Vector2(x: 1, y: 0)
        var simulation = controlledBall(at: Vector2(x: -29, y: -22), aim: right)
        let start = simulation.ball.position
        hold(0.9, aim: right, in: &simulation)
        simulation.movement = .zero
        var previousVerticalVelocity = simulation.ball.verticalVelocity
        var landingDistance: Double?
        for _ in 0..<100 {
            simulation.step(dt: tick)
            if previousVerticalVelocity < 0, simulation.ball.verticalVelocity > 0 {
                landingDistance = simulation.ball.position.x - start.x
                break
            }
            previousVerticalVelocity = simulation.ball.verticalVelocity
        }
        XCTAssertEqual(simulation.lastKickKind, "long kick")
        XCTAssertNotNil(landingDistance, "The real simulation must reach a physical first landing")
        if let landingDistance {
            XCTAssertGreaterThan(landingDistance, 57)
            XCTAssertLessThan(landingDistance, 60)
        }
        XCTAssertEqual(simulation.ball.position.y, start.y, accuracy: 0.000001)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.lastTouchTeam, .blue)
    }

    func testFullClearancePhysicallyPassesAboveStandingOpponentsWithoutTouch() {
        for obstacleDistance in [15.0, 30, 42] {
            var simulation = controlledBall(at: Vector2(x: 0, y: -35))
            let start = simulation.ball.position
            simulation.roster[3].state.position = start + .up * obstacleDistance
            simulation.roster[3].state.facing = -.up
            hold(0.9, aim: .up, in: &simulation)
            simulation.movement = .zero
            var minimumHeightOverOpponent = Double.infinity
            for _ in 0..<90 {
                simulation.step(dt: tick)
                let offset = simulation.ball.position.y - simulation.roster[3].state.position.y
                if abs(offset) < 1.7 { minimumHeightOverOpponent = min(minimumHeightOverOpponent, simulation.ball.height) }
                if offset > 3 { break }
            }
            XCTAssertGreaterThan(simulation.ball.position.y, simulation.roster[3].state.position.y + 3)
            XCTAssertTrue(minimumHeightOverOpponent.isFinite)
            XCTAssertGreaterThan(minimumHeightOverOpponent, 2.65)
            XCTAssertEqual(simulation.ball.velocity.x, 0, accuracy: 0.000001)
            XCTAssertGreaterThan(simulation.ball.velocity.y, 40)
            XCTAssertEqual(simulation.lastTouchTeam, .blue)
            XCTAssertEqual(simulation.headerCount, 0)
            XCTAssertEqual(simulation.standingTackleCount, 0)
            XCTAssertEqual(simulation.phase, .playing)
        }
    }

    func testModerateHoldGetsAirborneImmediatelyInGameplay() {
        for duration in [0.4, 0.6] {
            var simulation = controlledBall(at: Vector2(x: 0, y: -35))
            let start = simulation.ball.position
            hold(duration, aim: .up, in: &simulation)
            simulation.movement = .zero
            for _ in 0..<30 where simulation.ball.position.y < start.y + 5 { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.lastKickKind, "long kick")
            XCTAssertGreaterThan(simulation.ball.height, 1.1)
            XCTAssertGreaterThan(simulation.ball.verticalVelocity, 0)
            XCTAssertEqual(simulation.chipCount, 0)
            XCTAssertNil(simulation.passTargetID)
        }
    }

    func testCloseGoalShotMeterAndReleaseAgreeOnThirtyTwoMetreBoundary() {
        for mode in [ExerciseMode.solo, .passing] {
            for distance in [31.9, 32.1] {
                var simulation = controlledBall(at: Vector2(x: 0, y: Pitch.length / 2 - distance), mode: mode)
                simulation.movement = .up
                simulation.pressAction()
                simulation.updateActionHold(heldFor: 0.75)
                if distance < 32 {
                    XCTAssertEqual(simulation.powerMeterKind, .shot)
                    XCTAssertNotNil(simulation.powerMeterSweetSpot)
                    XCTAssertNotNil(simulation.powerMeterOverhitStart)
                } else {
                    XCTAssertEqual(simulation.powerMeterKind, .longKick)
                    XCTAssertNil(simulation.powerMeterSweetSpot)
                    XCTAssertNil(simulation.powerMeterOverhitStart)
                }
                simulation.releaseAction(heldFor: 0.75)
                XCTAssertEqual(simulation.lastKickKind, distance < 32 ? "shot" : "long kick")
            }
        }
    }

    func testNearGoalSweetCornerShotCanScoreWhileOverhitStillGoesOverBar() {
        for duration in [0.75, 1.3] {
            let aim = duration < 1 ? Vector2(x: 0.45, y: 1).normalized : .up
            var simulation = controlledBall(at: Vector2(x: 0, y: 32.5), aim: aim)
            hold(duration, aim: aim, in: &simulation)
            XCTAssertEqual(simulation.lastKickKind, duration < 1 ? "shot" : "overhit shot")
            simulation.movement = .zero
            for _ in 0..<120 where simulation.phase == .playing { simulation.step(dt: tick) }
            if duration < 1 {
                XCTAssertEqual(simulation.phase, .goal(north: true))
                XCTAssertEqual(simulation.northGoals, 1)
                XCTAssertGreaterThan(simulation.ball.position.x, 3)
                XCTAssertLessThan(simulation.ball.height + Pitch.ballRadius * 2, Pitch.crossbarHeight)
            } else {
                XCTAssertEqual(simulation.phase, .outOfPlay)
                XCTAssertEqual(simulation.northGoals, 0)
                XCTAssertGreaterThan(simulation.ball.height + Pitch.ballRadius * 2, Pitch.crossbarHeight)
            }
        }
    }

    func testFreshAftertouchCurvesClearanceWithoutAddingPowerOrChangingLoft() {
        var straight = controlledBall(at: Vector2(x: 0, y: -35))
        hold(0.9, aim: .up, in: &straight)
        XCTAssertGreaterThan(straight.aftertouchRemaining, 0)
        var curved = straight
        straight.movement = .up
        curved.movement = Vector2(x: 1, y: 0)
        for _ in 0..<30 {
            straight.step(dt: tick)
            curved.step(dt: tick)
        }
        XCTAssertEqual(straight.ball.velocity.x, 0, accuracy: 0.000001)
        XCTAssertGreaterThan(curved.ball.velocity.x, 4)
        XCTAssertGreaterThan(curved.ball.position.x, straight.ball.position.x + 1)
        XCTAssertEqual(curved.ball.velocity.length, straight.ball.velocity.length, accuracy: 0.000001)
        XCTAssertEqual(curved.ball.height, straight.ball.height, accuracy: 0.000001)
        XCTAssertEqual(curved.ball.verticalVelocity, straight.ball.verticalVelocity, accuracy: 0.000001)
        XCTAssertEqual(curved.kickCount, 1)
        XCTAssertEqual(curved.chipCount, 0)
    }
}
