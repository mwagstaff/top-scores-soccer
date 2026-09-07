import XCTest
@testable import TopScoresSoccer

final class ClubMatchTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func team(_ id: String, rating: Double = 78) -> ClubTeam {
        let roles = ["G", "D", "D", "D", "D", "M", "M", "M", "M", "F", "F", "F", "M"]
        let players = roles.enumerated().map { index, role in
            let playerID = "\(id)-\(index)"
            return ClubPlayer(id: playerID, name: "Player \(index)", shortName: nil,
                              position: role, jerseyNumber: index + 1, rating: rating,
                              appearance: .generated(for: playerID))
        }
        return ClubTeam(id: id, name: "Club \(id)", shortName: nil,
                        primaryHex: "#AA0000", secondaryHex: "#FFFFFF", players: players)
    }

    private func configuration(rating: Double = 78,
                               formation: MatchFormation = .fourFourTwo) -> FriendlyMatchConfiguration {
        FriendlyMatchConfiguration(home: .autoSelect(team: team("home", rating: rating), formation: formation),
                                   away: .autoSelect(team: team("away", rating: rating), formation: formation))
    }

    private func start(_ simulation: inout FootballSimulation) {
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.movement = .zero
    }

    func testClubConfigurationBuildsTwoDistinctStartingElevensWithDenseRuntimeIDs() {
        let match = configuration()
        let simulation = FootballSimulation(configuration: match)
        XCTAssertEqual(simulation.mode, .match)
        XCTAssertEqual(simulation.footballers.count, 22)
        XCTAssertEqual(simulation.footballers.map(\.id), Array(0..<22))
        XCTAssertEqual(simulation.roster.prefix(11).compactMap(\.clubPlayer?.id), match.home.players.map(\.id))
        XCTAssertEqual(simulation.roster.suffix(11).compactMap(\.clubPlayer?.id), match.away.players.map(\.id))
        XCTAssertEqual(simulation.roster.filter(\.isGoalkeeper).map(\.id), [0, 11])
        XCTAssertTrue(simulation.roster.prefix(11).allSatisfy { $0.team == .blue && $0.state.position.y <= 0 })
        XCTAssertTrue(simulation.roster.suffix(11).allSatisfy { $0.team == .red && $0.state.position.y >= 0 })
        XCTAssertTrue(simulation.hasControl)
        XCTAssertFalse(simulation.roster[simulation.selectedPlayerID].isGoalkeeper)
    }

    func testEachFormationKeepsAValidXIAndDistinctMidfieldOrForwardShape() {
        for formation in MatchFormation.allCases {
            let match = configuration(formation: formation)
            let simulation = FootballSimulation(configuration: match)
            XCTAssertEqual(match.home.players.count, 11)
            XCTAssertEqual(simulation.footballers.count, 22)
            XCTAssertEqual(Set(simulation.roster.prefix(11).map { $0.state.position.x }).count >= 5, true)
            XCTAssertTrue(simulation.roster.allSatisfy {
                abs($0.state.position.x) < Pitch.width / 2 && abs($0.state.position.y) < Pitch.length / 2
            })
        }
        let compact = FootballSimulation(configuration: configuration(formation: .fourFourTwo))
        let staggered = FootballSimulation(configuration: configuration(formation: .fourTwoThreeOne))
        XCTAssertNotEqual(compact.roster[5].state.position, staggered.roster[5].state.position)
        XCTAssertNotEqual(staggered.roster[5].state.position.y, staggered.roster[7].state.position.y)
    }

    func testSingleRatingProducesSmallPaceAndLargerTechnicalDifferences() {
        let low = ArcadePlayerAbilities(player: team("low", rating: 55).players[5])
        let high = ArcadePlayerAbilities(player: team("high", rating: 95).players[5])
        XCTAssertGreaterThan(high.speed, low.speed)
        XCTAssertLessThan(high.speed / low.speed, 1.18)
        XCTAssertGreaterThan(high.control / low.control, high.speed / low.speed)
        XCTAssertGreaterThan(high.passPower, low.passPower)
        XCTAssertGreaterThan(high.shotPower, low.shotPower)
        XCTAssertLessThan(high.passErrorRadians, low.passErrorRadians)
        XCTAssertLessThan(high.shotErrorRadians, low.shotErrorRadians)
        XCTAssertGreaterThan(high.defending, low.defending)
        XCTAssertGreaterThan(high.goalkeeping, low.goalkeeping)
    }

    func testRatingChangesActualShotPowerWithoutChangingActionTiming() {
        var lower = FootballSimulation(configuration: configuration(rating: 55))
        var higher = FootballSimulation(configuration: configuration(rating: 95))
        for _ in 0..<2 {
            // The same actor, formation, aim and hold duration isolate player quality.
            lower.movement = .up
            higher.movement = .up
            lower.pressAction()
            higher.pressAction()
            lower.releaseAction(heldFor: 0.65)
            higher.releaseAction(heldFor: 0.65)
            XCTAssertEqual(lower.lastKick, .shot)
            XCTAssertEqual(higher.lastKick, .shot)
            XCTAssertGreaterThan(higher.ball.velocity.length, lower.ball.velocity.length * 1.2)
            XCTAssertLessThan(abs(higher.ball.velocity.normalized.x), abs(lower.ball.velocity.normalized.x))
            lower.reset()
            higher.reset()
        }
    }

    func testRatingChangesActualPassPowerAndAccuracy() {
        var lower = FootballSimulation(configuration: configuration(rating: 55))
        var higher = FootballSimulation(configuration: configuration(rating: 95))
        let aim = (lower.roster[10].state.position - lower.ball.position).normalized
        lower.movement = aim
        higher.movement = aim
        lower.pressAction()
        higher.pressAction()
        lower.releaseAction(heldFor: 0.12)
        higher.releaseAction(heldFor: 0.12)
        XCTAssertEqual(lower.lastKick, .pass)
        XCTAssertEqual(higher.lastKick, .pass)
        XCTAssertGreaterThan(higher.ball.velocity.length, lower.ball.velocity.length)
        let lowError = abs(lower.ball.velocity.normalized.dot(aim.perpendicular))
        let highError = abs(higher.ball.velocity.normalized.dot(aim.perpendicular))
        XCTAssertLessThan(highError, lowError)
    }

    func testRatingsRemainBoundedAndMissingRatingsUseTheSuppliedEstimate() {
        var player = team("home").players[5]
        player.rating = 200
        let aboveRange = ArcadePlayerAbilities(player: player)
        player.rating = 95
        XCTAssertEqual(aboveRange, ArcadePlayerAbilities(player: player))
        player.rating = nil
        player.estimatedRating = 70
        let missing = ArcadePlayerAbilities(player: player)
        player.rating = 70
        XCTAssertEqual(missing, ArcadePlayerAbilities(player: player))
        player.rating = .nan
        XCTAssertTrue(ArcadePlayerAbilities(player: player).speed.isFinite)
    }

    func testPracticeAndGenericMatchKeepNeutralProfilesAndExistingRosters() {
        let neutral = ArcadePlayerAbilities(player: nil)
        XCTAssertEqual(neutral.speed, 1)
        XCTAssertEqual(neutral.acceleration, 1)
        XCTAssertEqual(neutral.control, 1)
        XCTAssertEqual(neutral.passPower, 1)
        XCTAssertEqual(neutral.shotPower, 1)
        XCTAssertEqual(neutral.defending, 1)
        XCTAssertEqual(neutral.goalkeeping, 1)
        XCTAssertEqual(neutral.passErrorRadians, 0)
        XCTAssertEqual(neutral.shotErrorRadians, 0)
        for (mode, count) in [(ExerciseMode.solo, 1), (.passing, 6), (.match, 10)] {
            let simulation = FootballSimulation(mode: mode)
            XCTAssertEqual(simulation.roster.count, count)
            XCTAssertTrue(simulation.roster.allSatisfy { $0.clubPlayer == nil && $0.abilities == neutral })
        }
    }

    func testClubGoalAndThrowInRestartsKeepIdentityAndValidTakers() {
        var simulation = FootballSimulation(configuration: configuration())
        start(&simulation)
        let identities = simulation.roster.compactMap(\.clubPlayer?.id)
        simulation.roster[11].state.position = Vector2(x: 20, y: 45)
        simulation.ball.position = Vector2(x: 0, y: 52)
        simulation.ball.velocity = .up * 120
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .goal(north: true))
        for _ in 0..<100 where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        XCTAssertTrue(simulation.matchRestart?.takerID.map { (12..<22).contains($0) } == true)
        XCTAssertEqual(simulation.roster.compactMap(\.clubPlayer?.id), identities)
        for _ in 0..<45 { simulation.step(dt: tick) }
        XCTAssertNil(simulation.matchRestart)
        simulation.ball.position = Vector2(x: Pitch.width / 2 + 0.2, y: 7)
        simulation.ball.velocity = Vector2(x: 100, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.matchRestart?.kind, .throwIn)
        for _ in 0..<100 where simulation.phase != .playing { simulation.step(dt: tick) }
        let taker = simulation.matchRestart?.takerID
        XCTAssertNotNil(taker)
        if let taker {
            XCTAssertTrue(simulation.roster.indices.contains(taker))
            XCTAssertEqual(simulation.roster[taker].team, simulation.matchRestart?.team)
            XCTAssertFalse(simulation.roster[taker].isGoalkeeper)
        }
        simulation.reset()
        XCTAssertEqual(simulation.roster.compactMap(\.clubPlayer?.id), identities)
        XCTAssertEqual(simulation.matchTimeElapsed, 0)
        XCTAssertEqual(simulation.northGoals + simulation.southGoals, 0)
        XCTAssertTrue(simulation.hasControl)
    }

    func testFullElevenAsideMatchCompletesWithFiniteStateAndLiveRestarts() {
        var simulation = FootballSimulation(configuration: configuration(formation: .fourThreeThree))
        var ticks = 0
        while simulation.phase != .fullTime && ticks < 40_000 {
            if simulation.phase == .playing {
                if simulation.hasControl {
                    simulation.movement = (Vector2(x: 0, y: Pitch.length / 2) - simulation.ball.position).normalized
                    if simulation.isTakingRestart || ticks.isMultiple(of: 35) {
                        simulation.pressAction()
                        simulation.releaseAction(heldFor: simulation.isTakingRestart ? 0.12 : 0.6)
                    }
                } else {
                    simulation.movement = (simulation.ball.position - simulation.player.position).normalized
                }
            }
            simulation.step(dt: tick)
            if !simulation.ball.position.x.isFinite || !simulation.ball.position.y.isFinite { XCTFail("Ball became invalid"); break }
            if !simulation.roster.allSatisfy({ $0.state.position.x.isFinite && $0.state.position.y.isFinite }) {
                XCTFail("Player became invalid"); break
            }
            ticks += 1
            if case .practiceEnded = simulation.phase { break }
        }
        XCTAssertEqual(simulation.phase, .fullTime)
        XCTAssertEqual(simulation.matchTimeRemaining, 0)
        XCTAssertGreaterThan(simulation.kickCount, 10)
        XCTAssertLessThan(ticks, 40_000, "An 11-a-side restart must not strand the match.")
        XCTAssertEqual(simulation.roster.count, 22)
    }
}
