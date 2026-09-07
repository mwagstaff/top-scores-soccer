import XCTest
@testable import TopScoresSoccer

final class EarlyPassAdjustmentTests: XCTestCase {
    private let tick = 1.0 / 60

    private func exercise(enabled: Bool = true) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.passEarlyAdjustmentEnabled = enabled
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = Vector2(x: 0, y: -40)
        simulation.player.velocity = .zero
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.roster[1].state.position = simulation.ball.position + .up * 40
        simulation.roster[2].state.position = Vector2(x: -28, y: 44)
        for id in 3..<6 {
            simulation.roster[id].state.position = Vector2(x: id % 2 == 0 ? 28 : -28, y: 45)
            simulation.roster[id].state.velocity = .zero
        }
        return simulation
    }

    private func release(_ simulation: inout FootballSimulation) {
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
    }

    func testSelectedAssistanceIsEnabledByDefaultAndPreservesPace() {
        XCTAssertTrue(GameplayTuning.defaults.passEarlyAdjustmentEnabled)
        var disabled = exercise(enabled: false)
        var enabled = exercise()
        release(&disabled)
        release(&enabled)
        disabled.movement = Vector2(x: 0.2, y: 0)
        enabled.movement = disabled.movement
        disabled.step(dt: tick)
        enabled.step(dt: tick)
        XCTAssertEqual(disabled.earlyPassAdjustmentCount, 0)
        XCTAssertEqual(enabled.earlyPassAdjustmentCount, 1)
        XCTAssertEqual(enabled.ball.velocity.length, disabled.ball.velocity.length, accuracy: 0.000001)
        XCTAssertGreaterThan(enabled.ball.velocity.x, disabled.ball.velocity.x)
        XCTAssertLessThanOrEqual(abs(enabled.lastEarlyPassAdjustmentAngle), EarlyPassAdjustment.maximumAngle)
        XCTAssertEqual(enabled.selectedPlayerID, 1)
        XCTAssertEqual(enabled.passTargetID, 1)
        XCTAssertEqual(enabled.kickCount, 1)
        XCTAssertEqual(enabled.chipCount, 0)
    }

    func testOnlyOneCorrectionIsAllowedAndLaterSteeringDoesNotHome() {
        var simulation = exercise()
        release(&simulation)
        simulation.movement = Vector2(x: 0.2, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.earlyPassAdjustmentCount, 1)
        XCTAssertEqual(simulation.earlyPassAdjustmentRemaining, 0)
        let direction = simulation.ball.velocity.normalized
        simulation.movement = Vector2(x: -0.2, y: 0)
        for _ in 0..<8 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.earlyPassAdjustmentCount, 1)
        XCTAssertEqual(simulation.ball.velocity.normalized.x, direction.x, accuracy: 0.000001)
        XCTAssertEqual(simulation.ball.velocity.normalized.y, direction.y, accuracy: 0.000001)
    }

    func testNeutralJitterAndExpiredInputCannotAdjustThePass() {
        for input in [Vector2.zero, .up * 0.97, Vector2(x: 0.04, y: 0)] {
            var simulation = exercise()
            release(&simulation)
            let direction = simulation.ball.velocity.normalized
            simulation.movement = input
            for _ in 0..<9 { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
            XCTAssertEqual(simulation.earlyPassAdjustmentRemaining, 0)
            simulation.movement = Vector2(x: 0.2, y: 0)
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
            XCTAssertEqual(simulation.ball.velocity.normalized.x, direction.x, accuracy: 0.000001)
            XCTAssertEqual(simulation.ball.velocity.normalized.y, direction.y, accuracy: 0.000001)
        }
    }

    func testReverseChipPermanentlyClosesAdjustmentWindow() {
        var simulation = exercise()
        release(&simulation)
        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 1)
        XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
        XCTAssertEqual(simulation.earlyPassAdjustmentRemaining, 0)
        simulation.movement = Vector2(x: 0.2, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
    }

    func testNewActionQueueAndCancellationCannotReopenOldWindow() {
        for cancel in [false, true] {
            var simulation = exercise()
            simulation.roster[1].state.position = simulation.ball.position + .up * 12
            release(&simulation)
            XCTAssertGreaterThan(simulation.earlyPassAdjustmentRemaining, 0)
            if cancel { simulation.cancelInput() }
            else {
                simulation.pressAction()
                simulation.releaseAction(heldFor: 0.12)
                XCTAssertNotNil(simulation.queuedActionKind)
            }
            XCTAssertEqual(simulation.earlyPassAdjustmentRemaining, 0)
            simulation.movement = Vector2(x: 0.2, y: 0)
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
            XCTAssertEqual(simulation.kickCount, 1)
        }
    }

    func testReachableInterceptionOpportunityPermanentlyVetoesAdjustment() {
        var simulation = exercise()
        simulation.roster[3].state.position = simulation.ball.position + Vector2(x: 2.5, y: 12)
        release(&simulation)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.earlyPassAdjustmentRemaining, 0,
                       "A defender able to reach the original route closes the chance before a new input.")
        simulation.roster[3].state.position = Vector2(x: -28, y: 45)
        simulation.movement = Vector2(x: 0.2, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
    }

    func testDefenderOnPassRouteStillMakesPhysicalInterception() {
        var simulation = exercise()
        simulation.roster[3].state.position = simulation.ball.position + .up * 8
        release(&simulation)
        simulation.movement = Vector2(x: 0.2, y: 0)
        for _ in 0..<90 where simulation.possessionTeam != .red { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertNil(simulation.passTargetID)
        XCTAssertEqual(simulation.earlyPassAdjustmentRemaining, 0)
    }

    func testBothOriginalAndCorrectedCorridorsAreChecked() {
        let ball = BallState(position: .zero, velocity: .up * 35, mode: .pass)
        let receiver = PlayerState(position: Vector2(x: 6, y: 30))
        let correctedRay = Vector2.up.rotated(by: -EarlyPassAdjustment.maximumAngle)
        for position in [Vector2(x: 0, y: 20), correctedRay * 20] {
            let decision = EarlyPassAdjustment.evaluate(ball: ball, receiver: receiver,
                movement: Vector2(x: 0.5, y: 0), launchMovement: .up, originalDirection: .up,
                receiverSpeed: 11.76, acceleration: 42, deceleration: 30, friction: 5,
                opponents: [EarlyPassAdjustment.Opponent(position: position, maximumSpeed: 0, reach: 1.06)])
            guard case .veto = decision else { return XCTFail("Neither an old-route nor a new-route interception may be avoided.") }
        }
    }

    func testLargeNewRunCanOnlyMakeSixDegreeSpeedPreservingCorrection() {
        let decision = EarlyPassAdjustment.evaluate(
            ball: BallState(position: .zero, velocity: .up * 35, mode: .pass),
            receiver: PlayerState(position: Vector2(x: 6, y: 30)),
            movement: Vector2(x: 1, y: 0), launchMovement: .up, originalDirection: .up,
            receiverSpeed: 11.76, acceleration: 42, deceleration: 30, friction: 5, opponents: [])
        guard case .correction(let velocity, let angle) = decision else {
            return XCTFail("An early reachable new run can use the limited correction.")
        }
        XCTAssertEqual(abs(angle), EarlyPassAdjustment.maximumAngle, accuracy: 0.000001)
        XCTAssertEqual(velocity.length, 35, accuracy: 0.000001)
        XCTAssertGreaterThan(velocity.x, 0)
        XCTAssertEqual(velocity.normalized.dot(.up), cos(EarlyPassAdjustment.maximumAngle), accuracy: 0.000001)
    }
}
