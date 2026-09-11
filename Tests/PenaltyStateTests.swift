import XCTest
@testable import TopScoresSoccer

final class PenaltyStateTests: XCTestCase {
    private let tick = 1.0 / 60

    private func penaltyFoul(atExpiry: Bool = false) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        for id in simulation.roster.indices {
            simulation.roster[id].state = PlayerState(position: Vector2(
                x: Double(id % 4 - 2) * 12, y: id < 5 ? -20 : 20))
        }
        simulation.roster[4].state.position = Vector2(x: 0, y: -50)
        simulation.roster[9].state.position = Vector2(x: 0, y: 50)
        let spot = Vector2(x: 0, y: 42)
        simulation.roster[0].state = PlayerState(position: spot)
        simulation.ball = BallState(position: spot + .up * 0.9, mode: .free)
        simulation.step(dt: tick)
        if atExpiry {
            simulation.tuning.matchDuration = 1
            while simulation.matchTimeElapsed < 1 - tick * 1.5 { simulation.step(dt: tick) }
        }
        simulation.roster[5].state = PlayerState(position: spot - .up * 1.44, facing: .up)
        simulation.ball = BallState(position: spot + Vector2(x: 0.9, y: -0.9), mode: .controlled)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        XCTAssertEqual(simulation.awardedFoulRestartKind, .penalty)
        return simulation
    }

    private func place(_ simulation: inout FootballSimulation) {
        for _ in 0..<300 where !simulation.isTakingPenalty { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.isTakingPenalty)
    }

    private func launch(_ simulation: inout FootballSimulation) -> Int {
        let taker = simulation.selectedPlayerID
        simulation.movement = Vector2(x: 0.22, y: 1)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.lastKickKind, "penalty")
        XCTAssertTrue(simulation.isPenaltyKickInFlight)
        return taker
    }

    func testPostReboundKeepsTakerRestrictionThroughInputCancellation() {
        var simulation = penaltyFoul()
        place(&simulation)
        let taker = launch(&simulation)
        simulation.roster[9].state.position = Vector2(x: 20, y: 20)
        // Produce a real swept post collision, without a goalkeeper or another player's touch.
        simulation.ball = BallState(position: Vector2(x: Pitch.goalWidth / 2, y: Pitch.length / 2 - 1),
                                    velocity: .up * 35, mode: .shot)
        for _ in 0..<4 where simulation.ball.velocity.y > 0 { simulation.step(dt: tick) }
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertEqual(simulation.phase, .playing)
        simulation.cancelInput()
        simulation.ball = BallState(position: simulation.roster[taker].state.position + .up,
                                    velocity: .zero, mode: .free)
        for _ in 0..<40 where simulation.phase == .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.kind, .indirectFreeKick)
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        XCTAssertEqual(simulation.penaltyDoubleTouchCount, 1)
        XCTAssertEqual(simulation.northGoals, 0)
        XCTAssertEqual(simulation.southGoals, 0)
        simulation.reset(clearScore: true)
        XCTAssertEqual(simulation.penaltyDoubleTouchCount, 0)
        XCTAssertFalse(simulation.isPenaltyKickInFlight)
    }

    func testAnotherPlayersPhysicalTouchAllowsTakerToReceiveAgain() {
        var simulation = penaltyFoul()
        place(&simulation)
        let taker = launch(&simulation)
        simulation.cancelInput()
        // Return onside before the teammate's touch; otherwise Law11 correctly takes priority
        // when this player later returns from an offside position to collect the ball.
        simulation.roster[taker].state = PlayerState(position: Vector2(x: 20, y: 0))
        simulation.roster[1].state = PlayerState(position: Vector2(x: -20, y: 0))
        simulation.ball = BallState(position: Vector2(x: -20, y: 1), velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertFalse(simulation.isPenaltyKickInFlight)
        for _ in 0..<24 { simulation.step(dt: tick) }
        simulation.roster[taker].state = PlayerState(position: Vector2(x: 20, y: 0))
        simulation.ball = BallState(position: Vector2(x: 20, y: 1), velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertNil(simulation.matchRestart)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertEqual(simulation.penaltyDoubleTouchCount, 0)
    }

    func testPenaltyAwardAtExpiryKeepsFullFoulSequenceThenCountsTheCompletedShot() {
        var simulation = penaltyFoul(atExpiry: true)
        // The foul occurred before the period expired; its visible aftermath and kick remain owed.
        for _ in 0..<20 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        place(&simulation)
        XCTAssertEqual(simulation.matchTimeRemaining, 0, accuracy: 0.000001)
        for _ in 0..<90 { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.isTakingPenalty, "Waiting to aim must not discard an owed penalty")
        _ = launch(&simulation)
        simulation.roster[9].state.position = Vector2(x: 20, y: 20)
        for _ in 0..<180 where simulation.phase != .halfTime { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .halfTime)
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertEqual(simulation.southGoals, 0)
        XCTAssertEqual(simulation.matchTimeElapsed, simulation.matchDuration)
    }

    func testPeriodExtendedForPenaltyEndsWhenBallIsClearedOutOfAttack() {
        var simulation = penaltyFoul(atExpiry: true)
        place(&simulation)
        _ = launch(&simulation)
        simulation.roster[1].state = PlayerState(position: Vector2(x: -20, y: 0))
        simulation.ball = BallState(position: Vector2(x: -20, y: 1), velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        // A clearance must remain safe through the brief rebound/possession grace period.
        for _ in 0..<60 where simulation.phase == .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .halfTime)
        XCTAssertEqual(simulation.northGoals, 0)
        XCTAssertEqual(simulation.penaltyDoubleTouchCount, 0)
    }
}
