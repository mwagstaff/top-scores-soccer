import XCTest
@testable import TopScoresSoccer

final class PassingIntelligenceTests: XCTestCase {
    private let tick = 1.0 / 60

    private func exercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.ball.position = .up * 1.25
        simulation.roster[1].state.position = Vector2(x: 0, y: 18)
        simulation.roster[2].state.position = Vector2(x: 8, y: 16)
        for id in 3..<6 {
            simulation.roster[id].state.position = Vector2(x: Double(id - 4) * 26, y: 42)
            simulation.roster[id].state.velocity = .zero
        }
        return simulation
    }

    private func pass(_ simulation: inout FootballSimulation, aim: Vector2 = .up, duration: Double = 0.12) {
        simulation.movement = aim
        simulation.pressAction()
        simulation.releaseAction(heldFor: duration)
        simulation.movement = .zero
    }

    func testAimTowardOpenLaneCompletesPassInsteadOfKickingThroughDefender() {
        var simulation = exercise()
        simulation.roster[3].state.position = Vector2(x: 0, y: 9)
        pass(&simulation, aim: (simulation.roster[2].state.position - simulation.ball.position).normalized)
        XCTAssertEqual(simulation.passTargetID, 2)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertGreaterThan(simulation.ball.velocity.x, 0)
        for _ in 0..<120 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testRequestedDirectionIsPreservedDespiteAMarkedReceiverAndCannotTurnBackwards() {
        var simulation = exercise()
        simulation.roster[2].state.position = Vector2(x: 5, y: 17)
        simulation.roster[3].state.position = simulation.roster[1].state.position + Vector2(x: 0.5, y: 0)
        pass(&simulation)
        XCTAssertEqual(simulation.passTargetID, 1, "A safer wider option must not silently override the requested recipient.")
        XCTAssertGreaterThan(simulation.ball.velocity.y, 0)

        var backward = exercise()
        backward.roster[1].state.position = Vector2(x: 0, y: -10)
        backward.roster[2].state.position = Vector2(x: 0, y: 12)
        backward.roster[3].state.position = Vector2(x: 0, y: 7)
        pass(&backward)
        XCTAssertEqual(backward.passTargetID, 2, "Risk scoring cannot turn a forward request into a backwards pass.")
    }

    func testPassRemainsInterceptableWhenOnlyRequestedLaneIsBlocked() {
        var simulation = exercise()
        simulation.roster[2].state.position = Vector2(x: -25, y: -25)
        simulation.roster[3].state.position = Vector2(x: 0, y: 9)
        pass(&simulation)
        XCTAssertEqual(simulation.passTargetID, 1)
        for _ in 0..<90 where simulation.possessionTeam != .red { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testNewForwardRunKeepsOnlyBriefOldLateralMomentum() {
        var stationary = exercise()
        stationary.roster[1].state.position = Vector2(x: 3, y: 28)
        stationary.roster[2].state.position = Vector2(x: -25, y: -25)
        var moving = stationary
        moving.roster[1].state.velocity = Vector2(x: 8, y: 0)
        pass(&stationary)
        pass(&moving)
        XCTAssertEqual(moving.passTargetID, 1)
        let crossingX = moving.ball.position.x + moving.ball.velocity.x / moving.ball.velocity.y
            * (28 - moving.ball.position.y)
        let stationaryCrossingX = stationary.ball.position.x + stationary.ball.velocity.x / stationary.ball.velocity.y
            * (28 - stationary.ball.position.y)
        XCTAssertGreaterThan(crossingX, stationaryCrossingX + 0.2)
        XCTAssertLessThan(crossingX, stationaryCrossingX + 1.5,
                          "The new upward input should not preserve a full-flight sideways AI run.")
        XCTAssertEqual(moving.ball.velocity.length, stationary.ball.velocity.length, accuracy: 0.5)
        XCTAssertEqual(moving.ball.height, 0)
    }

    func testLeadKeepsReceptionPointOnPitchAndBallNeverHomesAfterLaunch() {
        var simulation = exercise()
        simulation.roster[1].state.position = Vector2(x: 32, y: 18)
        simulation.roster[1].state.velocity = Vector2(x: 8, y: 0)
        simulation.roster[2].state.position = Vector2(x: -25, y: -25)
        pass(&simulation, aim: Vector2(x: 1, y: 0.5).normalized)
        let crossingX = simulation.ball.position.x + simulation.ball.velocity.x / simulation.ball.velocity.y
            * (18 - simulation.ball.position.y)
        XCTAssertLessThanOrEqual(crossingX, Pitch.width / 2 - 1 + 0.0001)
        let direction = simulation.ball.velocity.normalized
        simulation.roster[1].state.position = Vector2(x: -20, y: 30)
        for _ in 0..<6 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.ball.velocity.normalized.x, direction.x, accuracy: 0.000001)
        XCTAssertEqual(simulation.ball.velocity.normalized.y, direction.y, accuracy: 0.000001)
    }

    func testIntendedFriendlyPassHasForgivingClosePickupButLooseShotsAndAirborneBallsDoNot() {
        for mode in [BallMode.pass, .free, .shot] {
            var simulation = exercise()
            simulation.roster[2].state.position = Vector2(x: -25, y: -25)
            pass(&simulation)
            simulation.ball = BallState(position: simulation.player.position + Vector2(x: 2.65, y: 0),
                                        velocity: Vector2(x: -12, y: 0), mode: mode)
            simulation.step(dt: 0.001)
            XCTAssertEqual(simulation.hasControl, mode == .pass)
        }
        var airborne = exercise()
        airborne.roster[2].state.position = Vector2(x: -25, y: -25)
        pass(&airborne)
        airborne.ball = BallState(position: airborne.player.position + Vector2(x: 2.65, y: 0),
                                 velocity: Vector2(x: -12, y: 0), mode: .pass, height: 1.2)
        airborne.step(dt: 0.001)
        XCTAssertFalse(airborne.hasControl)
    }

    func testPhysicalReceptionCushionsIncomingSpeedAndAllowsImmediateReturnPass() {
        var simulation = exercise()
        simulation.roster[1].state.position = Vector2(x: 0, y: 12)
        simulation.roster[2].state.position = Vector2(x: -25, y: -25)
        pass(&simulation)
        simulation.ball = BallState(position: Vector2(x: 0, y: 8), velocity: .up * 28, mode: .pass)
        simulation.step(dt: 0.05)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertLessThan((simulation.ball.velocity - simulation.player.velocity).length, 2)
        XCTAssertGreaterThan((simulation.ball.position - simulation.player.position).length, 2,
                             "A forgiving contact still leaves the ball at its physical position.")
        pass(&simulation, aim: -.up)
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertEqual(simulation.passTargetID, 0)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
    }

    func testFirmRoughTapKeepsViableTeammateInsteadOfBecomingUnrequestedSpacePass() {
        var simulation = exercise()
        let angle = 70.0 * Double.pi / 180
        simulation.roster[1].state.position = Vector2(x: sin(angle), y: cos(angle)) * 12
        simulation.roster[2].state.position = Vector2(x: 0, y: -15)
        pass(&simulation, duration: 0.23)
        XCTAssertEqual(simulation.lastKickKind, "pass")
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertGreaterThan(simulation.ball.velocity.x, 0)
    }

    func testMovingReceiverMeetsPassWithNeutralStickThenSettlesAtFeet() {
        var simulation = exercise()
        simulation.roster[1].state.position = Vector2(x: 3, y: 28)
        simulation.roster[1].state.velocity = Vector2(x: 8, y: 0)
        simulation.roster[2].state.position = Vector2(x: -25, y: -25)
        let receiverStart = simulation.roster[1].state.position
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.23)
        simulation.movement = .zero
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        for _ in 0..<180 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl, "A prior running receiver must meet the physical pass without a new aim gesture.")
        XCTAssertGreaterThan(abs(simulation.player.position.x - receiverStart.x), 0.05)
        XCTAssertLessThan(abs(simulation.player.position.x - receiverStart.x), 2,
                          "Automatic reception meets the new flight line after the old sideways run brakes.")
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.movement = .zero
        for _ in 0..<36 { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertLessThan((simulation.ball.position - simulation.player.position).length, 2)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.chipCount, 0)
        XCTAssertEqual(simulation.slideCount, 0)
    }
}
