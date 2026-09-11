import XCTest
@testable import TopScoresSoccer

final class MatchEndsAndQuickShotTests: XCTestCase {
    private let tick = 1.0 / 60

    private func liveMatch(north: Bool, secondHalf: Bool = false) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var match = FootballSimulation(tuning: tuning, mode: .match, chooseStartingEnds: { north })
        match.pressAction()
        match.releaseAction(heldFor: 0.12)
        for _ in 0..<40 { match.step(dt: tick) }
        if secondHalf {
            match.tuning.matchDuration = 2
            for _ in 0..<180 where match.phase != .halfTime { match.step(dt: tick) }
            XCTAssertEqual(match.phase, .halfTime)
            match.resumeAfterHalfTime()
            for _ in 0..<60 where match.isTakingRestart { match.step(dt: tick) }
            match.tuning.matchDuration = 180
        }
        return match
    }

    private func setUpAttack(_ match: inout FootballSimulation, progress: Double = 38) {
        match.cancelInput()
        let attack = match.ends.attackSign(for: .blue)
        for id in match.roster.indices {
            match.roster[id].state.position = Vector2(x: 26, y: Double(id) - 10)
            match.roster[id].state.velocity = .zero
        }
        match.player.position = Vector2(x: 0, y: progress * attack)
        match.player.facing = .up * attack
        match.ball = BallState(position: match.player.position + .up * (1.2 * attack), mode: .free)
        match.movement = .up * attack
    }

    func testQuickTapShootsOnTargetInBothDirectionsAndBothHalves() {
        for north in [true, false] {
            for secondHalf in [false, true] {
                for duration in [0.0, 0.08, 0.24] {
                    var match = liveMatch(north: north, secondHalf: secondHalf)
                    setUpAttack(&match)
                    match.pressAction()
                    XCTAssertNil(match.passTargetID)
                    XCTAssertTrue(match.quickTapWillShoot)
                    match.releaseAction(heldFor: duration)
                    XCTAssertEqual(match.lastKickKind, "shot")
                    XCTAssertEqual(match.ball.mode, .shot)
                    XCTAssertNil(match.passTargetID)
                    XCTAssertGreaterThan(match.ball.velocity.dot(match.ends.direction(for: .blue)), 20)
                    for _ in 0..<100 where match.phase == .playing { match.step(dt: tick) }
                    XCTAssertEqual(match.northGoals, 1, "Blue's score follows the team across ends.")
                    XCTAssertEqual(match.southGoals, 0)
                    XCTAssertEqual(match.matchRestart?.team, .red)
                }
            }
        }
    }

    func testQuickTapPreservesNearbyDeliberatePass() {
        for north in [true, false] {
            var match = liveMatch(north: north)
            setUpAttack(&match)
            let actor = match.selectedPlayerID
            let receiver = match.roster.first { $0.team == .blue && $0.id != actor && !$0.isGoalkeeper }!.id
            let attack = match.ends.attackSign(for: .blue)
            match.roster[receiver].state.position = match.player.position + Vector2(x: 6, y: 5 * attack)
            // Keep the receiver onside and clear of defenders.
            for id in [5, 6, 9] { match.roster[id].state.position = Vector2(x: 25, y: 48 * attack) }
            match.movement = (match.roster[receiver].state.position - match.player.position).normalized
            match.pressAction()
            XCTAssertEqual(match.passTargetID, receiver)
            match.releaseAction(heldFor: 0.08)
            XCTAssertEqual(match.lastKickKind, "pass")
            XCTAssertEqual(match.selectedPlayerID, receiver)
        }
    }

    func testMidfieldAndAwayFromGoalTapsDoNotBecomeShots() {
        for north in [true, false] {
            for midfield in [true, false] {
                var match = liveMatch(north: north)
                setUpAttack(&match, progress: midfield ? 0 : 38)
                if !midfield { match.movement = -match.ends.direction(for: .blue) }
                match.pressAction()
                match.releaseAction(heldFor: 0.08)
                XCTAssertNotEqual(match.lastKickKind, "shot")
                XCTAssertNotEqual(match.ball.mode, .shot)
            }
        }
    }

    func testCoinTossIsUsedOnlyForNewMatchesAndHalfTimeSwapsBothTeams() {
        var tosses = 0
        var tuning = GameplayTuning.defaults
        tuning.matchDuration = 2
        tuning.aiSpeedScale = 0
        var match = FootballSimulation(tuning: tuning, mode: .match, chooseStartingEnds: {
            tosses += 1
            return tosses.isMultiple(of: 2)
        })
        XCTAssertFalse(match.ends.blueAttacksNorth)
        XCTAssertEqual(tosses, 1)
        for team in [Team.blue, .red] {
            let keeper = match.roster.first { $0.team == team && $0.isGoalkeeper }!
            XCTAssertLessThan(keeper.state.position.y * match.ends.attackSign(for: team), -45)
        }
        match.pressAction()
        match.releaseAction(heldFor: 0.08)
        for _ in 0..<180 where match.phase != .halfTime { match.step(dt: tick) }
        XCTAssertEqual(match.phase, .halfTime)
        match.resumeAfterHalfTime()
        XCTAssertTrue(match.ends.blueAttacksNorth)
        XCTAssertEqual(tosses, 1)
        for team in [Team.blue, .red] {
            let keeper = match.roster.first { $0.team == team && $0.isGoalkeeper }!
            XCTAssertLessThan(keeper.state.position.y * match.ends.attackSign(for: team), -45)
        }
        match.resumeAfterHalfTime()
        XCTAssertTrue(match.ends.blueAttacksNorth, "A repeated resume must not swap again.")
        match.startAdditionalPeriod(duration: 60)
        XCTAssertEqual(tosses, 1, "Extra time belongs to the same match and keeps its coin toss.")
        XCTAssertFalse(match.ends.blueAttacksNorth)
        match.reset()
        XCTAssertEqual(tosses, 2)
        XCTAssertTrue(match.ends.blueAttacksNorth)
        XCTAssertEqual(match.matchHalf, 1)
    }

    func testGoalAtEitherEndCreditsAttackingTeamAndAwardsOtherTeamKickoff() {
        for north in [true, false] {
            for goalNorth in [true, false] {
                var match = liveMatch(north: north)
                for id in match.roster.indices { match.roster[id].state.position = Vector2(x: 25, y: 0) }
                let sign = goalNorth ? 1.0 : -1.0
                match.ball = BallState(position: .up * (52 * sign), velocity: .up * (120 * sign), mode: .shot)
                match.step(dt: tick)
                let blueScored = goalNorth == north
                XCTAssertEqual(match.northGoals, blueScored ? 1 : 0)
                XCTAssertEqual(match.southGoals, blueScored ? 0 : 1)
                XCTAssertEqual(match.matchRestart?.team, blueScored ? .red : .blue)
            }
        }
    }

    func testReversedEndsMovePenaltyAndKeeperAreasAndOffsideLine() {
        let ends = MatchEnds(blueAttacksNorth: false)
        XCTAssertTrue(PenaltyRules.awardsPenalty(at: Vector2(x: 0, y: -45), offender: .red, awarded: .blue, ends: ends))
        XCTAssertEqual(PenaltyRules.mark(for: .blue, ends: ends).y, -41.5)
        var configuration = GoalkeeperAI.Configuration.defaults
        configuration.ends = ends
        XCTAssertTrue(GoalkeeperAI.isInOwnBox(Vector2(x: 0, y: 48), team: .blue, configuration: configuration))
        XCTAssertFalse(GoalkeeperAI.isInOwnBox(Vector2(x: 0, y: -48), team: .blue, configuration: configuration))
        var match = liveMatch(north: false)
        for id in match.roster.indices { match.roster[id].state.position = .zero }
        match.roster[0].state.position = Vector2(x: 0, y: -20)
        match.roster[1].state.position = Vector2(x: 0, y: -40)
        match.roster[5].state.position = Vector2(x: 0, y: -30)
        match.roster[9].state.position = Vector2(x: 0, y: -50)
        XCTAssertEqual(OffsideRules.snapshot(actor: 0, ball: Vector2(x: 0, y: -21), roster: match.roster, ends: ends)?.candidates, [1])
    }

    func testEndLineRestartsFollowCurrentDefendingTeam() {
        for north in [true, false] {
            for exitNorth in [true, false] {
                for touchTeam in [Team.blue, .red] {
                    var match = liveMatch(north: north)
                    let toucher = touchTeam == .blue ? 0 : 5
                    match.ball = BallState(position: match.roster[toucher].state.position
                        + match.ends.direction(for: touchTeam) * 1.2, mode: .free)
                    match.step(dt: tick)
                    XCTAssertEqual(match.lastTouchTeam, touchTeam)
                    for id in match.roster.indices { match.roster[id].state.position = Vector2(x: 25, y: 0) }
                    let sign = exitNorth ? 1.0 : -1.0
                    match.ball = BallState(position: Vector2(x: 12, y: 52 * sign), velocity: .up * (120 * sign), mode: .free)
                    match.step(dt: tick)
                    let attacker = match.ends.attackingTeam(atNorthGoal: exitNorth)
                    let defender: Team = attacker == .blue ? .red : .blue
                    XCTAssertEqual(match.matchRestart?.kind, touchTeam == defender ? .corner : .goalKick)
                    XCTAssertEqual(match.matchRestart?.team, touchTeam == defender ? attacker : defender)
                }
            }
        }
    }
}

final class MatchSimulationTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func liveMatch(movingAI: Bool = false) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        if !movingAI { tuning.aiSpeedScale = 0 }
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.movement = .zero
        return simulation
    }

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    private func recordTouch(_ team: Team, in simulation: inout FootballSimulation) {
        let id = team == .blue ? 0 : 5
        simulation.ball.position = simulation.roster[id].state.position + (team == .blue ? .up : -.up) * 1.2
        simulation.ball.velocity = .zero
        simulation.ball.height = 0
        simulation.ball.verticalVelocity = 0
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastTouchTeam, team)
    }

    func testMatchStartsFourOutfieldAndOneAutonomousKeeperPerTeamAtKickoff() {
        var simulation = FootballSimulation(mode: .match)
        XCTAssertEqual(simulation.footballers.count, 10)
        for team in [Team.blue, .red] {
            XCTAssertEqual(simulation.footballers.filter { $0.team == team && !$0.isGoalkeeper }.count, 4)
            XCTAssertEqual(simulation.footballers.filter { $0.team == team && $0.isGoalkeeper }.count, 1)
        }
        XCTAssertEqual(simulation.matchDuration, 180)
        XCTAssertEqual(simulation.matchTimeRemaining, 180)
        XCTAssertEqual(simulation.matchRestart?.kind, .kickoff)
        XCTAssertEqual(simulation.matchRestart?.team, .blue)
        XCTAssertTrue(simulation.isTakingRestart)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertFalse(simulation.roster[simulation.selectedPlayerID].isGoalkeeper)
        advance(&simulation, frames: 120)
        XCTAssertEqual(simulation.matchTimeRemaining, 180, "The kickoff waits for the player's fresh action.")
    }

    func testClockRunsOnlyDuringLivePlayAndFullTimeFreezesUntilNewMatch() {
        var simulation = liveMatch()
        simulation.tuning.matchDuration = 0.25
        advance(&simulation, frames: 60)
        XCTAssertEqual(simulation.phase, .halfTime)
        simulation.resumeAfterHalfTime()
        advance(&simulation, frames: 120)
        XCTAssertEqual(simulation.phase, .fullTime)
        XCTAssertEqual(simulation.matchTimeElapsed, simulation.matchDuration, accuracy: 0.000001)
        XCTAssertEqual(simulation.matchTimeRemaining, 0)
        let stopped = simulation.ball.position
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 60)
        XCTAssertEqual(simulation.ball.position, stopped)
        XCTAssertEqual(simulation.kickCount, 1)
        simulation.reset()
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.matchTimeElapsed, 0)
        XCTAssertEqual(simulation.matchRestart?.kind, .kickoff)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testGoalAwardsOppositionKickoffAndKeepsScoreCardsAndClock() {
        var simulation = liveMatch()
        simulation.roster[0].yellowCards = 1
        simulation.roster[9].state.position = Vector2(x: 15, y: 45)
        simulation.ball.position = Vector2(x: 0, y: 52)
        simulation.ball.velocity = .up * 120
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .goal(north: true))
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertEqual(simulation.matchRestart?.kind, .kickoff)
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        let clock = simulation.matchTimeElapsed
        for _ in 0..<100 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertEqual(simulation.roster[0].yellowCards, 1)
        XCTAssertEqual(simulation.matchTimeElapsed, clock)
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        advance(&simulation, frames: 45)
        XCTAssertNil(simulation.matchRestart, "The red kickoff is autonomous.")
        XCTAssertGreaterThan(simulation.matchTimeElapsed, clock)
    }

    func testTouchlineAwardsThrowToOppositeLastTouchAndClockWaitsForPlacement() {
        for lastTouch in [Team.blue, .red] {
            var simulation = liveMatch()
            recordTouch(lastTouch, in: &simulation)
            simulation.ball.position = Vector2(x: 34.2, y: 10)
            simulation.ball.velocity = Vector2(x: 100, y: 0)
            simulation.step(dt: tick)
            let awarded: Team = lastTouch == .blue ? .red : .blue
            XCTAssertEqual(simulation.phase, .restart(kind: .throwIn, team: awarded))
            XCTAssertEqual(simulation.matchRestart?.team, awarded)
            let clock = simulation.matchTimeElapsed
            for _ in 0..<60 where simulation.phase != .playing { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.matchTimeElapsed, clock)
            XCTAssertNotNil(simulation.matchRestart?.takerID)
            if awarded == .blue {
                XCTAssertTrue(simulation.hasControl)
                simulation.movement = Vector2(x: -1, y: 0)
                simulation.pressAction()
                simulation.releaseAction(heldFor: 0.12)
                XCTAssertGreaterThan(simulation.ball.height, 0)
                XCTAssertGreaterThan(simulation.ball.verticalVelocity, 0)
                XCTAssertNil(simulation.matchRestart)
            }
        }
    }

    func testEndLinesAwardCornerOrGoalKickFromTheLastTouch() {
        for north in [true, false] {
            for lastTouch in [Team.blue, .red] {
                var simulation = liveMatch()
                recordTouch(lastTouch, in: &simulation)
                simulation.ball.position = Vector2(x: 12, y: north ? 52 : -52)
                simulation.ball.velocity = .up * (north ? 120 : -120)
                simulation.step(dt: tick)
                let defending: Team = north ? .red : .blue
                let attacking: Team = north ? .blue : .red
                let kind: MatchRestartKind = lastTouch == defending ? .corner : .goalKick
                XCTAssertEqual(simulation.matchRestart?.kind, kind)
                XCTAssertEqual(simulation.matchRestart?.team, kind == .corner ? attacking : defending)
                XCTAssertEqual(simulation.northGoals + simulation.southGoals, 0)
            }
        }
    }

    func testBlueGoalKickSelectsKeeperAndWaitsForManualAimedFootKick() throws {
        var simulation = liveMatch()
        recordTouch(.red, in: &simulation)
        simulation.ball.position = Vector2(x: 12, y: -52)
        simulation.ball.velocity = -.up * 120
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.matchRestart?.kind, .goalKick)
        for _ in 0..<60 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.takerID, 4)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertTrue(simulation.isControllingGoalkeeper)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.ball.position,
            Vector2(x: RestartSupport.goalAreaHalfWidth,
                    y: -Pitch.length / 2 + RestartSupport.goalAreaDepth))
        XCTAssertEqual(simulation.player.position,
            simulation.ball.position - Vector2.up * 1.2)
        XCTAssertEqual(simulation.restartShortOutletIDs.count, 1)
        let outlet = simulation.restartShortOutletIDs[0]
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.roster[outlet].state.position,
            Vector2(x: -RestartSupport.goalAreaHalfWidth, y: simulation.ball.position.y))
        simulation.movement = (simulation.roster[outlet].state.position - simulation.ball.position).normalized
        XCTAssertEqual(simulation.passTargetID, outlet)
        simulation.movement = .zero
        let context = try XCTUnwrap(simulation.matchRestart)
        for opponent in simulation.roster where opponent.team == .red && !opponent.isSentOff {
            XCTAssertTrue(RestartSupport.isLegalOpponentPosition(opponent.state.position,
                team: opponent.team, restart: context))
        }
        let kicks = simulation.kickCount
        let clock = simulation.matchTimeElapsed
        let position = simulation.player.position
        simulation.movement = Vector2(x: -0.5, y: 1).normalized
        advance(&simulation, frames: 90)
        XCTAssertEqual(simulation.player.position, position)
        XCTAssertEqual(simulation.matchTimeElapsed, clock)
        XCTAssertEqual(simulation.kickCount, kicks)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.6)
        XCTAssertNil(simulation.matchRestart)
        XCTAssertEqual(simulation.kickCount, kicks + 1)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.lastDistributionKind, .longGoalKick)
        XCTAssertEqual(simulation.ball.height, 0, "A goal kick starts at the feet.")
    }

    func testKeeperCatchesOppositionBallAndWaitsForManualThrowToNearbyReceiver() {
        var simulation = liveMatch()
        recordTouch(.red, in: &simulation)
        simulation.roster[4].state.position = Vector2(x: 0, y: -48)
        simulation.roster[4].state.velocity = .zero
        simulation.roster[0].state.position = Vector2(x: -3, y: -41)
        simulation.ball.position = Vector2(x: 0, y: -46.8)
        simulation.ball.velocity = -.up * 4
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)
        XCTAssertEqual(simulation.goalkeeperPossessionTeam, .blue)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        let kicks = simulation.kickCount
        advance(&simulation, frames: 90)
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.kickCount, kicks)
        simulation.movement = (simulation.roster[0].state.position - simulation.player.position).normalized
        XCTAssertEqual(simulation.passTargetID, 0)
        let delivery = simulation.distributionPreviewKind
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertNil(simulation.goalkeeperPossessionTeam)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)
        XCTAssertEqual(simulation.kickCount, kicks + 1)
        XCTAssertEqual(simulation.lastDistributionKind, delivery)
    }

    func testHardShotIsParriedAndKeeperBecomesLastTouchForCornerAward() {
        var simulation = liveMatch()
        simulation.roster[9].state.position = Vector2(x: 0, y: 50)
        simulation.roster[9].state.velocity = .zero
        simulation.ball.position = Vector2(x: 0, y: 47)
        simulation.ball.velocity = .up * 100
        simulation.ball.mode = .shot
        simulation.step(dt: 0.03)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)
        XCTAssertNil(simulation.goalkeeperPossessionTeam)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        simulation.ball.position = Vector2(x: 12, y: 52)
        simulation.ball.velocity = .up * 100
        simulation.ball.height = 0
        simulation.ball.verticalVelocity = 0
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.matchRestart?.kind, .corner)
        XCTAssertEqual(simulation.matchRestart?.team, .blue)
    }

    func testWholeBallCrossingCannotBeUndoneByKeeperMotionLaterInTheTick() {
        var simulation = liveMatch()
        simulation.roster[9].state.position = Vector2(x: 1.8, y: 51.75)
        simulation.roster[9].state.velocity = Vector2(x: -6, y: 0)
        simulation.ball.position = Vector2(x: 0, y: 52.75)
        simulation.ball.velocity = .up * 100
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .goal(north: true))
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
    }

    func testFormationKeepsSupportingPlayersWideInsteadOfSendingEveryoneAtBall() {
        var simulation = liveMatch(movingAI: true)
        simulation.movement = .zero
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        advance(&simulation, frames: 60)
        let redOutfield = simulation.roster.filter { $0.team == .red && !$0.isGoalkeeper }
        XCTAssertGreaterThanOrEqual(redOutfield.filter { abs($0.state.position.x) >= 8 }.count, 3)
        XCTAssertEqual(simulation.footballers.count, 10)
        XCTAssertFalse(simulation.roster[simulation.selectedPlayerID].isGoalkeeper)
    }

    func testManualNewMatchClearsScoreAndDisciplineButPracticeModesKeepTheirRosters() {
        var simulation = liveMatch()
        simulation.roster[0].yellowCards = 2
        simulation.roster[0].isSentOff = true
        advance(&simulation, frames: 10)
        simulation.reset()
        XCTAssertEqual(simulation.matchTimeElapsed, 0)
        XCTAssertEqual(simulation.northGoals + simulation.southGoals, 0)
        XCTAssertTrue(simulation.roster.allSatisfy { !$0.isSentOff && $0.yellowCards == 0 })
        simulation.setMode(.passing)
        XCTAssertEqual(simulation.footballers.count, 6)
        XCTAssertNil(simulation.matchRestart)
        simulation.setMode(.solo)
        XCTAssertEqual(simulation.footballers.count, 1)
        simulation.setMode(.match)
        XCTAssertEqual(simulation.footballers.count, 10)
        XCTAssertEqual(simulation.matchTimeRemaining, 180)
    }

    func testTouchlineRestartMovesAnOutsideOpponentInwardToKeepClearance() {
        var simulation = liveMatch()
        recordTouch(.red, in: &simulation)
        simulation.ball.position = Vector2(x: 34.2, y: 10)
        simulation.ball.velocity = Vector2(x: 100, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.matchRestart?.team, .blue)
        simulation.roster[5].state.position = Vector2(x: Pitch.width / 2 - Pitch.playerRadius, y: 10)
        for _ in 0..<60 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertGreaterThanOrEqual((simulation.roster[5].state.position - simulation.ball.position).length,
                                   RestartSupport.throwInDistance - 0.001)
        XCTAssertLessThanOrEqual(abs(simulation.roster[5].state.position.x), Pitch.width / 2 - Pitch.playerRadius)
    }

    func testMatchFoulPreservesDisciplineAndPausesClockThroughTheFreeKick() {
        var simulation = liveMatch()
        advance(&simulation, frames: 30)
        let offender = simulation.selectedPlayerID
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -25 : 25, y: -30)
            simulation.roster[id].state.velocity = .zero
        }
        simulation.roster[offender].state.position = Vector2(x: -7, y: 20.6)
        simulation.roster[offender].state.facing = -.up
        simulation.roster[offender].state.velocity = -.up * 16
        simulation.roster[offender].yellowCards = 1
        simulation.roster[5].state.position = Vector2(x: -7, y: 18)
        simulation.roster[5].state.facing = -.up
        simulation.ball.position = Vector2(x: 25, y: 0)
        simulation.ball.velocity = .zero
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        for _ in 0..<15 where simulation.phase == .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        let clock = simulation.matchTimeElapsed
        for _ in 0..<240 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.matchRestart?.kind, .freeKick)
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        XCTAssertEqual(simulation.matchTimeElapsed, clock)
        XCTAssertEqual(simulation.lastFoul?.card, .red)
        XCTAssertTrue(simulation.roster[offender].isSentOff)
        XCTAssertEqual(simulation.northGoals + simulation.southGoals, 0)
    }

    func testNaturalThreeMinuteMatchCompletesWithFiniteStateAndReachableRestarts() {
        var simulation = FootballSimulation(mode: .match)
        var ticks = 0
        while simulation.phase != .fullTime && ticks < 40_000 {
            if simulation.phase == .halfTime { simulation.resumeAfterHalfTime() }
            if simulation.pendingInjuryID != nil {
                if let replacement = simulation.injuryReplacements.first {
                    simulation.substituteInjuredPlayer(with: replacement.id)
                } else { simulation.continueWithoutInjuryReplacement() }
            }
            if simulation.phase == .playing {
                if simulation.hasControl {
                    simulation.movement = (simulation.ends.direction(for: .blue) * (Pitch.length / 2) - simulation.ball.position).normalized
                    if simulation.isTakingRestart || ticks.isMultiple(of: 35) {
                        simulation.pressAction()
                        simulation.releaseAction(heldFor: simulation.isTakingRestart ? 0.12 : 0.6)
                    }
                } else {
                    simulation.movement = (simulation.ball.position - simulation.player.position).normalized
                }
            }
            simulation.step(dt: tick)
            XCTAssertTrue(simulation.ball.position.x.isFinite && simulation.ball.position.y.isFinite)
            XCTAssertTrue(simulation.roster.allSatisfy { $0.state.position.x.isFinite && $0.state.position.y.isFinite })
            XCTAssertTrue(!simulation.roster[simulation.selectedPlayerID].isGoalkeeper || simulation.isControllingGoalkeeper)
            ticks += 1
            if case .practiceEnded = simulation.phase { break }
        }
        XCTAssertEqual(simulation.phase, .fullTime)
        XCTAssertEqual(simulation.matchTimeRemaining, 0)
        XCTAssertGreaterThan(simulation.kickCount, 10)
        XCTAssertGreaterThan(simulation.northGoals + simulation.southGoals, 0)
        XCTAssertLessThan(ticks, 40_000, "No restart may strand a live match indefinitely.")
    }
}
