import XCTest
@testable import TopScoresSoccer

final class OffsideTests: XCTestCase {
    private let tick = 1.0 / 60

    private func fixture(team: Team = .blue) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        let attack = team == .blue ? 1.0 : -1.0
        for id in simulation.roster.indices {
            let friendly = simulation.roster[id].team == team
            simulation.roster[id].state.position = Vector2(x: Double(id % 4 - 2) * 10,
                y: (friendly ? -30 : 10) * attack)
            simulation.roster[id].state.velocity = .zero
            if simulation.roster[id].isGoalkeeper {
                simulation.roster[id].state.position = Vector2(x: 0, y: friendly ? -50 * attack : 50 * attack)
            }
        }
        let passer = team == .blue ? 0 : 5
        let receiver = passer + 1
        simulation.roster[passer].state.position = Vector2(x: 0, y: 4 * attack)
        simulation.roster[receiver].state.position = Vector2(x: 0, y: 20 * attack)
        simulation.ball = BallState(position: Vector2(x: 0, y: 5 * attack), mode: .free)
        simulation.step(dt: tick) // A real controlled teammate touch establishes the offside snapshot.
        XCTAssertEqual(simulation.possessionTeam, team)
        return simulation
    }

    private func involve(_ simulation: inout FootballSimulation, id: Int) {
        let attack = simulation.roster[id].team == .blue ? 1.0 : -1.0
        simulation.ball = BallState(position: simulation.roster[id].state.position - .up * attack,
                                    velocity: .up * (6 * attack), mode: .pass)
        simulation.step(dt: tick)
    }

    func testPositionUsesSecondLastOpponentBallAndHalfwayWithLevelPlayersOnside() {
        let simulation = fixture()
        var roster = simulation.roster
        roster[1].state.position.y = 10
        XCTAssertFalse(OffsideRules.snapshot(actor: 0, ball: .zero, roster: roster)!.candidates.contains(1))
        roster[1].state.position.y = 10.2
        XCTAssertTrue(OffsideRules.snapshot(actor: 0, ball: .zero, roster: roster)!.candidates.contains(1))
        XCTAssertFalse(OffsideRules.snapshot(actor: 0, ball: Vector2(x: 0, y: 11), roster: roster)!.candidates.contains(1))
        roster[1].state.position.y = 0
        for id in 5...9 { roster[id].state.position.y = -8 }
        XCTAssertFalse(OffsideRules.snapshot(actor: 0, ball: Vector2(x: 0, y: -12), roster: roster)!.candidates.contains(1))
        roster[1].state.position.y = 1
        roster[1].isSentOff = true
        XCTAssertFalse(OffsideRules.snapshot(actor: 0, ball: .zero, roster: roster)!.candidates.contains(1))
    }

    func testExemptRestartsAndKeeperReleaseRules() {
        let simulation = fixture()
        for kind in [MatchRestartKind.throwIn, .corner, .goalKick] {
            XCTAssertNil(OffsideRules.snapshot(actor: 0, ball: simulation.ball.position, roster: simulation.roster, restart: kind))
        }
        for kind in [MatchRestartKind.kickoff, .freeKick, .offside] {
            XCTAssertTrue(OffsideRules.snapshot(actor: 0, ball: simulation.ball.position, roster: simulation.roster, restart: kind)!.candidates.contains(1))
        }
        XCTAssertTrue(OffsideRules.snapshot(actor: 4, ball: simulation.ball.position, roster: simulation.roster)!.candidates.contains(1),
                      "An open-play keeper throw/punt has no goal-kick exemption.")
    }

    func testReceptionAwardsOppositionRestartForEitherTeamWithoutFoulOrCard() {
        for team in [Team.blue, .red] {
            var simulation = fixture(team: team)
            let receiver = team == .blue ? 1 : 6
            let awarded: Team = team == .blue ? .red : .blue
            let position = simulation.roster[receiver].state.position
            involve(&simulation, id: receiver)
            XCTAssertEqual(simulation.phase, .restart(kind: .offside, team: awarded))
            XCTAssertEqual(simulation.matchRestart?.position, position)
            XCTAssertEqual(simulation.offsideCount, 1)
            XCTAssertEqual(simulation.foulCount, 0)
            XCTAssertNil(simulation.lastFoul)
            XCTAssertTrue(simulation.roster.allSatisfy { $0.yellowCards == 0 && !$0.isSentOff })
            let stopped = simulation.matchTimeElapsed
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.matchTimeElapsed, stopped)
        }
    }

    func testOffsidePlayerReturningOnsideStillOffendsButUninvolvedPlayerDoesNot() {
        var simulation = fixture()
        simulation.ball = BallState(position: Vector2(x: 25, y: 25), velocity: .up * 4, mode: .pass)
        for _ in 0..<5 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.offsideCount, 0)
        simulation.roster[1].state.position = Vector2(x: 0, y: 8)
        involve(&simulation, id: 1)
        XCTAssertEqual(simulation.offsideCount, 1)
        XCTAssertEqual(simulation.matchRestart?.position.y, 8)
    }

    func testOnsideAtTouchCanRunBeyondDefendersBeforeReception() {
        var simulation = fixture()
        simulation.roster[1].state.position.y = 8
        simulation.ball = BallState(position: simulation.roster[0].state.position + .up, mode: .free)
        simulation.step(dt: tick)
        for _ in 0..<15 { simulation.step(dt: tick) } // Fresh controlled touch replaces the old snapshot.
        simulation.roster[1].state.position.y = 22
        involve(&simulation, id: 1)
        XCTAssertEqual(simulation.offsideCount, 0)
        XCTAssertEqual(simulation.possessionTeam, .blue)
    }

    func testControlledOpponentPossessionResetsOldOffsideButPauseDoesNot() {
        var simulation = fixture()
        simulation.cancelInput()
        involve(&simulation, id: 1)
        XCTAssertEqual(simulation.offsideCount, 1, "Cancelling a gesture must not erase a pass's offside state.")
        simulation = fixture()
        simulation.ball = BallState(position: simulation.roster[5].state.position + .up, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .red)
        involve(&simulation, id: 1)
        XCTAssertEqual(simulation.offsideCount, 0)
    }

    func testOffsideRestartIsIndirectAndFreshResetClearsDecision() {
        var simulation = fixture(team: .red)
        involve(&simulation, id: 6)
        for _ in 0..<120 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.kind, .offside)
        XCTAssertEqual(simulation.matchRestart?.team, .blue)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.65)
        simulation.ball = BallState(position: Vector2(x: 0, y: 52.75), velocity: .up * 20, mode: .shot)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.northGoals, 0)
        XCTAssertEqual(simulation.matchRestart?.kind, .goalKick)
        simulation.reset(clearScore: true)
        XCTAssertEqual(simulation.offsideCount, 0)
        XCTAssertEqual(simulation.matchRestart?.kind, .kickoff)
    }

    func testPracticeModesKeepTheirExistingNoOffsideRules() {
        var simulation = FootballSimulation(mode: .passing)
        simulation.roster[1].state.position = Vector2(x: 0, y: 45)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        involve(&simulation, id: 1)
        XCTAssertEqual(simulation.offsideCount, 0)
        XCTAssertEqual(simulation.phase, .playing)
    }

    func testPostAndKeeperParryDoNotEraseOffsideSnapshot() {
        var post = fixture()
        post.ball = BallState(position: Vector2(x: Pitch.goalWidth / 2, y: 51.7), velocity: .up * 20, mode: .shot)
        post.step(dt: tick)
        XCTAssertLessThan(post.ball.velocity.y, 0)
        involve(&post, id: 1)
        XCTAssertEqual(post.offsideCount, 1)

        var parry = fixture()
        parry.roster[9].state.position = Vector2(x: 0, y: 50)
        parry.ball = BallState(position: Vector2(x: 0.2, y: 48.8), velocity: .up * 35, mode: .shot)
        parry.step(dt: tick)
        XCTAssertEqual(parry.goalkeeperSaveCount, 1)
        XCTAssertNil(parry.goalkeeperHoldingID)
        involve(&parry, id: 1)
        XCTAssertEqual(parry.offsideCount, 1)
    }

    func testIndirectKickCanScoreAfterAnotherPlayerTouchesIt() {
        var simulation = fixture(team: .red)
        involve(&simulation, id: 6)
        for _ in 0..<120 where simulation.phase != .playing { simulation.step(dt: tick) }
        let taker = simulation.selectedPlayerID
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        let other = (0..<4).first { $0 != taker }!
        simulation.roster[other].state.position = Vector2(x: 0, y: 30)
        simulation.ball = BallState(position: Vector2(x: 0, y: 31), mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        simulation.ball = BallState(position: Vector2(x: 0, y: 52.75), velocity: .up * 20, mode: .shot)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.northGoals, 1)
    }

    func testDirectGoalKickReceptionIsExemptInLiveSimulation() {
        var simulation = fixture(team: .red)
        simulation.ball = BallState(position: Vector2(x: 15, y: -52.7), velocity: -.up * 20, mode: .shot)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.matchRestart?.kind, .goalKick)
        XCTAssertEqual(simulation.matchRestart?.team, .blue)
        for _ in 0..<120 where simulation.phase != .playing { simulation.step(dt: tick) }
        for id in 5..<9 { simulation.roster[id].state.position = Vector2(x: Double(id - 6) * 10, y: 10) }
        simulation.roster[1].state.position = Vector2(x: 0, y: 20)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        involve(&simulation, id: 1)
        XCTAssertEqual(simulation.offsideCount, 0)
        XCTAssertEqual(simulation.possessionTeam, .blue)
    }

    func testPressThatDetectsOffsideCannotArmAnotherActionDuringTheRestart() {
        var simulation = fixture()
        simulation.ball = BallState(position: simulation.roster[1].state.position - .up, velocity: .up * 6, mode: .pass)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.8)
        simulation.releaseAction(heldFor: 0.8)
        XCTAssertEqual(simulation.offsideCount, 1)
        XCTAssertEqual(simulation.phase, .restart(kind: .offside, team: .red))
        XCTAssertNil(simulation.powerMeterKind)
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testThroughBallDoesNotHandControlToAnAlreadyOffsideRunner() {
        var simulation = fixture()
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.23)
        XCTAssertEqual(simulation.lastKickKind, "knock ahead", "An offside runner cannot turn an open-space tap into an assisted through pass.")
        XCTAssertNil(simulation.passTargetID)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.offsideCount, 0, "An untouched space pass must remain in play.")
    }

    func testCarriersNextTouchIsOffsideAfterAProtectedTeammateGlance() {
        var simulation = fixture()
        for id in 5..<9 { simulation.roster[id].state.position.y = 8 }
        simulation.roster[0].state.position = Vector2(x: 0, y: 12)
        simulation.roster[1].state.position = Vector2(x: -20, y: -30)
        simulation.ball = BallState(position: Vector2(x: 0, y: 13), mode: .free)
        simulation.step(dt: tick)
        XCTAssertTrue(simulation.hasControl)
        simulation.roster[1].state.position = Vector2(x: 0, y: 10)
        simulation.ball = BallState(position: Vector2(x: 0, y: 10.5), mode: .controlled)
        simulation.step(dt: tick)
        for _ in 0..<8 where simulation.phase == .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.offsideCount, 1)
        XCTAssertEqual(simulation.phase, .restart(kind: .offside, team: .red))
        XCTAssertEqual(simulation.ball.velocity, .zero)
        XCTAssertNil(simulation.possessionTeam)
    }
}
