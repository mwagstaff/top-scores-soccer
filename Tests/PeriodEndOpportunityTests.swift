import XCTest
@testable import TopScoresSoccer

final class PeriodEndOpportunityTests: XCTestCase {
    private let tick = 1.0 / 60

    private func liveMatch(north: Bool, secondHalf: Bool, elevenAside: Bool = false) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.foulInjuryChance = 0
        var match: FootballSimulation
        if elevenAside {
            func club(_ name: String) -> ClubTeam {
                let roles = ["G", "D", "D", "D", "D", "M", "M", "M", "M", "F", "F"]
                return ClubTeam(id: name, name: name, primaryHex: "#AA0000", secondaryHex: "#FFFFFF",
                    players: roles.enumerated().map { index, role in
                        ClubPlayer(id: "\(name)-\(index)", name: "Player \(index)", position: role,
                            jerseyNumber: index + 1, rating: 78, appearance: .generated(for: "\(name)-\(index)"))
                    })
            }
            let configuration = FriendlyMatchConfiguration(home: .autoSelect(team: club("Home")),
                                                           away: .autoSelect(team: club("Away")))
            match = FootballSimulation(tuning: tuning, configuration: configuration, chooseStartingEnds: { north })
            XCTAssertEqual(match.roster.count, 22)
        } else {
            match = FootballSimulation(tuning: tuning, mode: .match, chooseStartingEnds: { north })
        }
        match.pressAction()
        match.releaseAction(heldFor: 0.12)
        for _ in 0..<40 { match.step(dt: tick) }
        if secondHalf {
            match.tuning.matchDuration = 2
            for _ in 0..<180 where match.phase != .halfTime { match.step(dt: tick) }
            XCTAssertEqual(match.phase, .halfTime)
            match.resumeAfterHalfTime()
            for _ in 0..<120 where match.isTakingRestart { match.step(dt: tick) }
            match.tuning.matchDuration = 180
            for _ in 0..<40 { match.step(dt: tick) }
        }
        match.cancelInput()
        return match
    }

    private func clearPlayers(_ match: inout FootballSimulation) {
        for id in match.roster.indices {
            match.roster[id].state = PlayerState(position: Vector2(x: 25, y: Double(id) * 2 - 15))
        }
    }

    private func touch(_ team: Team, in match: inout FootballSimulation) {
        clearPlayers(&match)
        let actor = match.roster.first { $0.team == team && !$0.isGoalkeeper }!.id
        match.roster[actor].state = PlayerState(position: .zero)
        match.ball = BallState(position: .up, mode: .free)
        match.step(dt: tick)
        XCTAssertEqual(match.possessionTeam, team)
        XCTAssertEqual(match.lastTouchTeam, team)
    }

    private func expireOnNextTick(_ match: inout FootballSimulation) {
        match.tuning.matchDuration = 2 * (match.periodElapsed - match.stoppageTime + tick / 2)
    }

    func testLooseDefensiveReboundAllowsLateTapInAtBothEndsAndInBothHalves() {
        for north in [true, false] {
            for (secondHalf, elevenAside) in [(false, false), (true, false), (false, true), (true, true)] {
                var match = liveMatch(north: north, secondHalf: secondHalf, elevenAside: elevenAside)
                touch(.red, in: &match)
                clearPlayers(&match)
                let attack = match.ends.direction(for: .blue)
                let spot = attack * 50
                match.player = PlayerState(position: spot - attack * 3.2, facing: attack)
                match.ball = BallState(position: spot, velocity: -attack * 0.2, mode: .free)
                expireOnNextTick(&match)
                match.step(dt: tick)
                XCTAssertEqual(match.periodTimeRemaining, 0)
                XCTAssertEqual(match.phase, .playing, "A nearby rebound remains a scoring chance after a defensive touch.")
                XCTAssertTrue(match.hasGoalScoringOpportunity)
                // Let the user take a beat before moving within pickup reach and tapping.
                for _ in 0..<60 { match.step(dt: tick) }
                XCTAssertEqual(match.phase, .playing)
                match.player = PlayerState(position: match.ball.position - attack, facing: attack)
                match.movement = attack
                match.pressAction()
                match.releaseAction(heldFor: 0.08)
                XCTAssertEqual(match.lastKickKind, "shot")
                for _ in 0..<90 where match.phase == .playing { match.step(dt: tick) }
                XCTAssertEqual(match.northGoals, 1)
                XCTAssertEqual(match.phase, secondHalf ? .fullTime : .halfTime)
            }
        }
    }

    func testDefensivePossessionUnderClosePressureStillCountsAsDangerForEitherTeam() {
        for north in [true, false] {
            for team in [Team.blue, .red] {
                var match = liveMatch(north: north, secondHalf: false)
                let defender: Team = team == .blue ? .red : .blue
                touch(defender, in: &match)
                clearPlayers(&match)
                let owner = match.roster.first { $0.team == defender && !$0.isGoalkeeper }!.id
                let attacker = match.roster.first { $0.team == team && !$0.isGoalkeeper }!.id
                let direction = match.ends.direction(for: team)
                let spot = direction * 49
                match.roster[owner].state.position = spot
                match.ball = BallState(position: spot + direction, mode: .controlled)
                match.roster[attacker].state.position = match.ball.position + Vector2(x: 3, y: 0)
                XCTAssertEqual(match.possessionTeam, defender)
                XCTAssertTrue(match.hasGoalScoringOpportunity)
                match.roster[attacker].isSentOff = true
                XCTAssertFalse(match.hasGoalScoringOpportunity, "Unavailable attackers cannot prolong a half.")
            }
        }
    }

    func testBriefBreakInDangerDoesNotWhistleButSustainedClearanceDoes() {
        for secondHalf in [false, true] {
            var match = liveMatch(north: true, secondHalf: secondHalf)
            touch(.blue, in: &match)
            clearPlayers(&match)
            let attack = match.ends.direction(for: .blue)
            match.ball = BallState(position: attack * 40, mode: .free, height: 5)
            expireOnNextTick(&match)
            match.step(dt: tick)
            XCTAssertEqual(match.phase, .playing)
            // An attack crosses the old danger-area cutoff for a frame, then returns.
            match.ball = BallState(position: attack * 27, mode: .free, height: 5)
            match.step(dt: tick)
            XCTAssertEqual(match.phase, .playing)
            match.ball = BallState(position: attack * 40, mode: .free, height: 5)
            match.step(dt: tick)
            XCTAssertEqual(match.phase, .playing)
            match.ball = BallState(position: .zero, mode: .free, height: 5)
            for _ in 0..<90 where match.phase == .playing { match.step(dt: tick) }
            XCTAssertEqual(match.phase, secondHalf ? .fullTime : .halfTime)
        }
    }

    func testSafeMidfieldPlayStillEndsAtExpiry() {
        for secondHalf in [false, true] {
            var match = liveMatch(north: true, secondHalf: secondHalf)
            clearPlayers(&match)
            match.ball = BallState(position: .zero, mode: .free, height: 5)
            expireOnNextTick(&match)
            match.step(dt: tick)
            XCTAssertEqual(match.phase, secondHalf ? .fullTime : .halfTime)
        }
    }

    func testOnTargetShotOutsideDangerAreaIsAllowedToReachGoal() {
        for north in [true, false] {
            for secondHalf in [false, true] {
                var match = liveMatch(north: north, secondHalf: secondHalf)
                clearPlayers(&match)
                match.ball = BallState(position: .zero, mode: .free, height: 5)
                match.step(dt: tick) // Release the previous possession claim.
                let attack = match.ends.direction(for: .blue)
                match.ball = BallState(position: attack * 20, velocity: attack * 45, mode: .shot)
                expireOnNextTick(&match)
                match.step(dt: tick)
                XCTAssertEqual(match.phase, .playing)
                for _ in 0..<180 where match.phase == .playing { match.step(dt: tick) }
                XCTAssertEqual(match.northGoals, 1)
                XCTAssertEqual(match.phase, secondHalf ? .fullTime : .halfTime)
            }
        }
    }

    func testKeeperCatchEndsAttackWithoutWaitingForGracePeriod() {
        for secondHalf in [false, true] {
            var match = liveMatch(north: true, secondHalf: secondHalf)
            touch(.red, in: &match)
            clearPlayers(&match)
            let attack = match.ends.direction(for: .red)
            let keeper = match.roster.first { $0.team == .blue && $0.isGoalkeeper }!.id
            match.roster[keeper].state = PlayerState(position: attack * 47, facing: -attack)
            match.ball = BallState(position: attack * 45.9, velocity: attack * 4, mode: .free)
            expireOnNextTick(&match)
            for _ in 0..<30 where match.phase == .playing { match.step(dt: tick) }
            XCTAssertEqual(match.goalkeeperSaveCount, 1)
            XCTAssertEqual(match.phase, secondHalf ? .fullTime : .halfTime)
            XCTAssertEqual(match.northGoals + match.southGoals, 0)
        }
    }
}
