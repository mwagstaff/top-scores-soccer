import XCTest
@testable import TopScoresSoccer

final class DifficultyAndMatchFlowTests: XCTestCase {
    private let tick = 1.0 / 60

    private func liveMatch(secondHalf: Bool = false) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.foulInjuryChance = 0
        tuning.matchDuration = 2
        var match = FootballSimulation(tuning: tuning, mode: .match)
        match.pressAction()
        match.releaseAction(heldFor: 0.12)
        if secondHalf {
            for _ in 0..<120 where match.phase != .halfTime { match.step(dt: tick) }
            XCTAssertEqual(match.phase, .halfTime)
            match.resumeAfterHalfTime()
            for _ in 0..<120 where match.isTakingRestart { match.step(dt: tick) }
            XCTAssertEqual(match.matchHalf, 2)
        }
        return match
    }

    func testDifficultyChangesActualOppositionPaceButPreservesUserPace() {
        XCTAssertEqual(GameplayTuning.defaults.difficulty, .medium)
        var opponentDistances: [Double] = []
        var userDistances: [Double] = []
        for difficulty in GameDifficulty.allCases {
            var tuning = GameplayTuning.defaults
            tuning.difficulty = difficulty
            var match = FootballSimulation(tuning: tuning, mode: .passing)
            match.ball = BallState(position: Vector2(x: 25, y: -25), mode: .free, height: 100)
            match.movement = Vector2(x: -1, y: 0)
            let opponent = match.roster[3].state.position
            let user = match.player.position
            for _ in 0..<20 { match.step(dt: tick) }
            opponentDistances.append((match.roster[3].state.position - opponent).length)
            userDistances.append((match.player.position - user).length)
        }
        XCTAssertLessThan(opponentDistances[0], opponentDistances[1])
        XCTAssertLessThan(opponentDistances[1], opponentDistances[2])
        XCTAssertEqual(userDistances[0], userDistances[1], accuracy: 0.001)
        XCTAssertEqual(userDistances[1], userDistances[2], accuracy: 0.001)
    }

    func testHardOppositionRejectsBlockedPassAndUnavailableReceiver() {
        var match = liveMatch()
        match.tuning.difficulty = .hard
        for id in match.roster.indices { match.roster[id].state.position = Vector2(x: 30, y: 45) }
        match.roster[5].state.position = Vector2(x: 0, y: 10)
        match.roster[6].state.position = Vector2(x: 0, y: -10)
        match.roster[7].state.position = Vector2(x: -15, y: -10)
        match.roster[0].state.position = .zero // blocks the tempting central pass
        match.roster[1].state.position = Vector2(x: 25, y: -35)
        match.roster[4].state.position = Vector2(x: 0, y: -50)
        match.ball.position = Vector2(x: 0, y: 9)
        XCTAssertEqual(match.intelligentOpponentPassTarget(from: 5), 7)
        match.roster[7].isInjured = true
        XCTAssertNotEqual(match.intelligentOpponentPassTarget(from: 5), 7)
        XCTAssertGreaterThan(GameDifficulty.easy.decisionInterval, GameDifficulty.medium.decisionInterval)
        XCTAssertGreaterThan(GameDifficulty.medium.decisionInterval, GameDifficulty.hard.decisionInterval)
    }

    func testBothWhistlesWaitForShotAndCountLateGoal() {
        for secondHalf in [false, true] {
            for direction in [Vector2.up, -Vector2.up] {
                var match = liveMatch(secondHalf: secondHalf)
                for id in match.roster.indices { match.roster[id].state.position = Vector2(x: 25, y: 0) }
                match.ball = BallState(position: direction * 40, velocity: direction * 0.1, mode: .shot, height: 100)
                while match.periodTimeRemaining > tick * 1.1 { match.step(dt: tick) }
                match.ball = BallState(position: direction * 48, velocity: direction * 30, mode: .shot)
                match.step(dt: tick)
                XCTAssertEqual(match.phase, .playing)
                XCTAssertEqual(match.periodTimeRemaining, 0)
                for _ in 0..<30 where match.phase == .playing { match.step(dt: tick) }
                let scorer = match.ends.attackingTeam(atNorthGoal: direction.y > 0)
                XCTAssertEqual(scorer == .blue ? match.northGoals : match.southGoals, 1)
                XCTAssertEqual(match.phase, secondHalf ? .fullTime : .halfTime)
            }
        }
    }

    func testBothWhistlesWaitForCornerThenEndOnDefensiveRestart() {
        for secondHalf in [false, true] {
            var match = liveMatch(secondHalf: secondHalf)
            let attack = match.ends.attackSign(for: .blue)
            match.roster[5].state.position = Vector2(x: 20, y: 10 * attack)
            match.ball = BallState(position: Vector2(x: 20, y: 9 * attack), mode: .free)
            match.step(dt: tick)
            XCTAssertEqual(match.lastTouchTeam, .red)
            while match.periodTimeRemaining > tick * 1.1 { match.step(dt: tick) }
            match.ball = BallState(position: Vector2(x: 12, y: 52 * attack), velocity: .up * (120 * attack), mode: .free)
            match.step(dt: tick)
            XCTAssertEqual(match.matchRestart?.kind, .corner)
            XCTAssertTrue(match.hasGoalScoringOpportunity)
            for _ in 0..<90 { match.step(dt: tick) }
            XCTAssertTrue(match.isTakingRestart)
            XCTAssertEqual(match.matchRestart?.kind, .corner)
            match.pressAction()
            match.releaseAction(heldFor: 0.12)
            // A corner that runs straight out off the attacker ends the opportunity.
            match.ball = BallState(position: Vector2(x: 12, y: 52 * attack), velocity: .up * (120 * attack), mode: .free)
            match.step(dt: tick)
            XCTAssertEqual(match.phase, secondHalf ? .fullTime : .halfTime)
        }
    }

    func testHalfTimeFreezesAndSecondHalfResetsAddedTimeButKeepsCards() {
        var match = liveMatch()
        match.roster[0].yellowCards = 1
        match.roster[1].isSentOff = true
        for _ in 0..<120 where match.phase != .halfTime { match.step(dt: tick) }
        XCTAssertEqual(match.phase, .halfTime)
        let elapsed = match.periodElapsed
        match.step(dt: 30)
        XCTAssertEqual(match.periodElapsed, elapsed)
        match.resumeAfterHalfTime()
        XCTAssertEqual(match.matchRestart?.team, .red)
        XCTAssertEqual(match.stoppageTime, 0)
        XCTAssertEqual(match.roster[0].yellowCards, 1)
        XCTAssertTrue(match.roster[1].isSentOff)
    }

    @MainActor
    func testSavedDifficultyCarriesIntoNewSessionsAndRestoreDefaults() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "gameDifficulty")
        defer {
            if let original { defaults.set(original, forKey: "gameDifficulty") }
            else { defaults.removeObject(forKey: "gameDifficulty") }
        }
        defaults.removeObject(forKey: "gameDifficulty")
        let first = GameSession(startingMode: .match)
        XCTAssertEqual(first.tuning.difficulty, .medium)
        first.tuning.difficulty = .hard
        let next = GameSession(startingMode: .match)
        XCTAssertEqual(next.tuning.difficulty, .hard)
        XCTAssertEqual(next.scene.simulation.tuning.difficulty, .hard)
        next.restoreDefaults()
        XCTAssertEqual(defaults.string(forKey: "gameDifficulty"), "medium")
    }

    private func configuration(reserves: Bool = true) -> FriendlyMatchConfiguration {
        func team(_ name: String) -> ClubTeam {
            let roles = ["G", "D", "D", "D", "D", "M", "M", "M", "M", "F", "F"] + (reserves ? ["G", "D", "M", "F"] : [])
            return ClubTeam(id: name, name: name, primaryHex: "#AA0000", secondaryHex: "#FFFFFF",
                players: roles.enumerated().map { index, role in
                    ClubPlayer(id: "\(name)-\(index)", name: "\(name) player \(index)", position: role,
                        jerseyNumber: index + 1, rating: 78, appearance: .generated(for: "\(name)-\(index)"))
                })
        }
        return .init(home: .autoSelect(team: team("Home")), away: .autoSelect(team: team("Away")))
    }

    private func foulMatch(userVictim: Bool = true, reserves: Bool = true, chance: Double = 1) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.foulInjuryChance = chance
        var match = FootballSimulation(tuning: tuning, configuration: configuration(reserves: reserves))
        match.pressAction()
        match.releaseAction(heldFor: 0.12)
        match.cancelInput()
        for id in match.roster.indices {
            match.roster[id].state = PlayerState(position: Vector2(x: id.isMultiple(of: 2) ? -28 : 28,
                                                                 y: id < 11 ? -25 : 0))
        }
        match.roster[0].state.position = Vector2(x: 0, y: -50)
        match.roster[11].state.position = Vector2(x: 0, y: 50)
        let victim = userVictim ? 1 : 12
        let offender = userVictim ? 12 : 1
        let direction: Vector2 = userVictim ? .up : -.up
        let spot = direction * 20
        match.roster[victim].state = PlayerState(position: spot, facing: direction)
        match.ball = BallState(position: spot + direction * 0.9, mode: .free)
        match.step(dt: tick)
        if userVictim {
            match.roster[offender].state = PlayerState(position: spot - direction * 1.44, facing: direction)
            match.ball = BallState(position: spot + Vector2(x: 0.9, y: -direction.y * 0.9), mode: .controlled)
            match.step(dt: tick)
        } else {
            let tackler = match.selectedPlayerID
            match.roster[tackler].state = PlayerState(position: spot - direction * 2.6,
                velocity: direction * 16, facing: direction)
            match.ball = BallState(position: Vector2(x: 25, y: 0), mode: .free)
            match.pressAction()
            match.updateActionHold(heldFor: 0.3)
            for _ in 0..<15 where match.phase == .playing { match.step(dt: tick) }
        }
        XCTAssertEqual(match.phase, .foulContact(team: userVictim ? .blue : .red))
        return match
    }

    private func resolve(_ match: inout FootballSimulation) {
        for _ in 0..<300 where match.phase != .playing && match.pendingInjuryID == nil { match.step(dt: tick) }
    }

    func testFoulLostTimeIsAddedOnceAndSquadSelectionDoesNotRunClock() throws {
        var match = foulMatch()
        let liveElapsed = match.matchTimeElapsed
        resolve(&match)
        XCTAssertGreaterThanOrEqual(match.stoppageTime, 9.5) // foul aftermath + treatment
        XCTAssertEqual(match.matchTimeElapsed, liveElapsed)
        XCTAssertEqual(match.pendingInjuryID, 1)
        XCTAssertTrue(match.roster[1].isInjured)
        let clock = match.periodElapsed
        let added = match.stoppageTime
        match.step(dt: 600)
        XCTAssertEqual(match.periodElapsed, clock)
        XCTAssertEqual(match.stoppageTime, added)
        let outgoing = try XCTUnwrap(match.roster[1].clubPlayer)
        let replacement = try XCTUnwrap(match.injuryReplacements.last)
        XCTAssertFalse(match.injuryReplacements.contains(outgoing))
        XCTAssertFalse(match.substituteInjuredPlayer(with: outgoing.id))
        XCTAssertFalse(match.substituteInjuredPlayer(with: match.configuration!.away.team.players[0].id))
        XCTAssertTrue(match.substituteInjuredPlayer(with: replacement.id))
        XCTAssertEqual(match.roster[1].clubPlayer, replacement)
        XCTAssertEqual(match.substitutionsUsed[.blue], 1)
        XCTAssertTrue(match.liveHomeLineup?.players.contains(replacement) == true)
        XCTAssertFalse(match.roster[1].isUnavailable)
        XCTAssertEqual(match.roster[1].yellowCards, 0)
        XCTAssertNil(match.pendingInjuryID)
        XCTAssertEqual(match.matchRestart?.kind, .freeKick)
        XCTAssertEqual(match.matchRestart?.team, .blue)
        XCTAssertTrue(match.unavailableSquadIDs.contains(outgoing.id))
        XCTAssertFalse(match.substituteInjuredPlayer(with: replacement.id), "Repeated taps cannot substitute twice")
        match.roster[2].isSentOff = true
        match.startAdditionalPeriod(duration: 60)
        XCTAssertEqual(match.roster[1].clubPlayer, replacement)
        XCTAssertTrue(match.roster[2].isSentOff)
        XCTAssertEqual(match.substitutionsUsed[.blue], 1)
        XCTAssertTrue(match.unavailableSquadIDs.contains(outgoing.id))
        match.reset()
        XCTAssertEqual(match.roster[1].clubPlayer, outgoing)
        XCTAssertTrue(match.unavailableSquadIDs.isEmpty)
        XCTAssertFalse(match.roster[2].isSentOff)
    }

    func testOppositionSubstitutesAutomaticallyAndEmptyBenchContinuesShort() throws {
        var opponent = foulMatch(userVictim: false)
        let outgoing = opponent.roster[12].clubPlayer
        resolve(&opponent)
        XCTAssertNil(opponent.pendingInjuryID)
        XCTAssertNotEqual(opponent.roster[12].clubPlayer, outgoing)
        XCTAssertFalse(opponent.roster[12].isUnavailable)
        XCTAssertEqual(opponent.matchRestart?.team, .red)
        var user = foulMatch(reserves: false)
        resolve(&user)
        XCTAssertEqual(user.pendingInjuryID, 1)
        XCTAssertTrue(user.injuryReplacements.isEmpty)
        user.continueWithoutInjuryReplacement()
        XCTAssertNil(user.pendingInjuryID)
        XCTAssertTrue(user.roster[1].isInjured)
        XCTAssertNotEqual(user.selectedPlayerID, 1)
        XCTAssertEqual(user.roster.filter { $0.team == .blue && !$0.isUnavailable }.count, 10)
        var noInjury = foulMatch(chance: 0)
        resolve(&noInjury)
        XCTAssertNil(noInjury.pendingInjuryID)
        XCTAssertFalse(noInjury.roster.contains(where: \.isInjured))
        XCTAssertLessThan(noInjury.stoppageTime, 4)
    }
}
