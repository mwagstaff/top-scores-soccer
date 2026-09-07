import XCTest
@testable import TopScoresSoccer

final class PenaltyIntegrationTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func blueFoul(at position: Vector2) -> FootballSimulation {
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
        simulation.roster[0].state = PlayerState(position: position)
        simulation.ball = BallState(position: position + .up * 0.9, mode: .free)
        simulation.step(dt: tick)
        simulation.roster[5].state = PlayerState(position: position - .up * 1.44, facing: .up)
        simulation.ball = BallState(position: position + Vector2(x: 0.9, y: -0.9), mode: .controlled)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        return simulation
    }

    func testBoxFoulPreservesFallThenAwardsPenaltyAtTheWhistle() {
        var simulation = blueFoul(at: Vector2(x: 0, y: 42))
        XCTAssertNil(simulation.lastFoul)
        XCTAssertEqual(simulation.foulCount, 1)
        XCTAssertGreaterThan(simulation.roster[0].fallProgress, 0)
        for _ in 0..<10 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        XCTAssertNil(simulation.lastFoul)
        for _ in 0..<300 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.kind, .penalty)
        XCTAssertEqual(simulation.matchRestart?.team, .blue)
        XCTAssertEqual(simulation.ball.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(simulation.ball.position.y, Pitch.length / 2 - 11, accuracy: 0.0001)
        XCTAssertEqual(simulation.foulCount, 1)
    }

    func testFoulJustOutsideBoxRemainsFreeKick() {
        var simulation = blueFoul(at: Vector2(x: 0, y: 35.7))
        for _ in 0..<300 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.kind, .freeKick)
        XCTAssertEqual(simulation.ball.position.y, simulation.lastFoul!.position.y, accuracy: 0.0001)
    }

    func testBoxLinesBelongToTheAreaButAttackingFoulInOtherBoxIsNotAPenalty() {
        for (spot, kind) in [(Vector2(x: 0, y: 36), MatchRestartKind.penalty),
                             (Vector2(x: 20.16, y: 42), .penalty),
                             (Vector2(x: 20.3, y: 42), .freeKick),
                             (Vector2(x: 0, y: -42), .freeKick)] {
            var simulation = blueFoul(at: spot)
            for _ in 0..<300 where simulation.phase != .playing { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.matchRestart?.kind, kind)
        }
    }

    func testPenaltyKeepsKeeperOnLineAndOthersOutsideAreaUntilFreshShot() {
        var simulation = blueFoul(at: Vector2(x: 0, y: 42))
        for _ in 0..<300 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.isTakingPenalty)
        let clock = simulation.matchTimeElapsed
        let positions = simulation.roster.map(\.state.position)
        let mark = simulation.ball.position
        let taker = simulation.selectedPlayerID
        simulation.movement = Vector2(x: -1, y: 0)
        for _ in 0..<60 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchTimeElapsed, clock)
        XCTAssertEqual(simulation.roster.map(\.state.position), positions)
        XCTAssertEqual(simulation.ball.position, mark)
        XCTAssertEqual(simulation.roster[9].state.position.y, Pitch.length / 2)
        XCTAssertNil(simulation.passTargetID)
        XCTAssertTrue(simulation.restartShortOutletIDs.isEmpty)
        for player in simulation.roster where player.id != taker && player.id != 9 && !player.isSentOff {
            XCTAssertFalse(PenaltyRules.insideOwnArea(player.state.position, team: .red))
            XCTAssertLessThan(player.state.position.y, mark.y)
            XCTAssertGreaterThanOrEqual((player.state.position - mark).length, 9.15)
        }
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.08)
        XCTAssertFalse(simulation.isTakingPenalty)
        XCTAssertTrue(simulation.isPenaltyKickInFlight)
        XCTAssertEqual(simulation.ball.mode, .shot)
        XCTAssertLessThan(simulation.ball.velocity.x, 0)
        XCTAssertGreaterThan(simulation.ball.velocity.y, 0)
        XCTAssertGreaterThan(simulation.ball.velocity.length, 25)
    }

    func testPenaltyShotCanScoreAndAnOverheldShotGoesOverWithoutAutomaticGoal() {
        for overheld in [false, true] {
            var simulation = blueFoul(at: Vector2(x: 0, y: 42))
            for _ in 0..<300 where simulation.phase != .playing { simulation.step(dt: tick) }
            simulation.movement = .up
            simulation.pressAction()
            simulation.releaseAction(heldFor: overheld ? 1.6 : 0.08)
            // Isolate actual goal-height adjudication from the autonomous goalkeeper's save.
            simulation.roster[9].state.position = Vector2(x: 20, y: 20)
            simulation.movement = .zero
            for _ in 0..<120 where simulation.phase == .playing { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.northGoals, overheld ? 0 : 1)
            XCTAssertEqual(simulation.matchRestart?.kind, overheld ? .goalKick : .kickoff)
        }
    }

    func testRedPenaltyFromRealSlideKeepsCardAndReleasesAutomatically() {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.movement = .zero
        for _ in 0..<30 { simulation.step(dt: tick) }
        let offender = simulation.selectedPlayerID
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state = PlayerState(position: Vector2(
                x: id.isMultiple(of: 2) ? -25 : 25, y: 10))
        }
        simulation.roster[offender].state = PlayerState(position: Vector2(x: -7, y: -39.4),
                                                       velocity: -.up * 16, facing: -.up)
        simulation.roster[offender].yellowCards = 1
        simulation.roster[5].state = PlayerState(position: Vector2(x: -7, y: -42), facing: -.up)
        simulation.ball = BallState(position: Vector2(x: 25, y: 0), mode: .free)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        for _ in 0..<15 where simulation.phase == .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertGreaterThan(simulation.slideCount, 0)
        for _ in 0..<300 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.kind, .penalty)
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        XCTAssertEqual(simulation.ball.position.y, -Pitch.length / 2 + 11)
        XCTAssertEqual(simulation.roster[4].state.position.y, -Pitch.length / 2)
        XCTAssertEqual(simulation.lastFoul?.offenderID, offender)
        XCTAssertEqual(simulation.roster[offender].yellowCards, 1)
        // Existing discipline decides severity; awarding a penalty must not reset prior cards.
        XCTAssertNotNil(simulation.lastFoul)
        XCTAssertFalse(simulation.isControllingGoalkeeper)
        for _ in 0..<90 where simulation.isTakingPenalty { simulation.step(dt: tick) }
        XCTAssertFalse(simulation.isTakingPenalty)
        XCTAssertTrue(simulation.isPenaltyKickInFlight)
        XCTAssertEqual(simulation.ball.mode, .shot)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
    }
}
