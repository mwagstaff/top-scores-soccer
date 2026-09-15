import XCTest
@testable import TopScoresSoccer

final class TeamManagementTests: XCTestCase {
    private func team(_ id: String) -> ClubTeam {
        let roles = ["G", "D", "D", "D", "D", "M", "M", "M", "M", "F", "F", "F", "M", "D", "D", "M", "F", "G", "M", "D"]
        return ClubTeam(id: id, name: id, primaryHex: "#AA0000", secondaryHex: "#FFFFFF",
            players: roles.enumerated().map { index, role in
                let playerID = "\(id)-\(index)"
                return ClubPlayer(id: playerID, name: "Player \(index)", position: role,
                    jerseyNumber: index + 1, rating: Double(90 - index), appearance: .generated(for: playerID))
            })
    }
    private func configuration() -> FriendlyMatchConfiguration {
        .init(home: .autoSelect(team: team("home")), away: .autoSelect(team: team("away")))
    }
    private func start(_ simulation: inout FootballSimulation) {
        simulation.movement = .up
        simulation.pressAction(); simulation.releaseAction(heldFor: 0.12)
        simulation.movement = .zero
    }
    private func stop(_ simulation: inout FootballSimulation) {
        simulation.ball.position = Vector2(x: 33, y: 0)
        simulation.ball.velocity = Vector2(x: 30, y: 0)
        simulation.ball.mode = .shot
        for _ in 0..<20 { simulation.step(dt: 1.0 / 60) }
    }

    func testMidfielderToStrikerAutomaticallyMakes433AndRetainsOthers() throws {
        let lineup = configuration().home
        let removed = lineup.players[5].id
        let striker = lineup.team.players[11]
        let updated = try XCTUnwrap(lineup.replacingPlayer(at: 5, with: striker))
        XCTAssertEqual(updated.formation, .fourThreeThree)
        XCTAssertTrue(updated.isValid)
        XCTAssertEqual(Set(updated.players.map(\.id)), Set(lineup.players.map(\.id)).subtracting([removed]).union([striker.id]))
        XCTAssertTrue(zip(updated.players, updated.formation.slots).allSatisfy { $0.role == $1.role })
    }

    func testManualShapeRetainsXIAndAutomaticModeCanRecoverIt() {
        var lineup = configuration().home
        let identities = Set(lineup.players.map(\.id))
        lineup = lineup.arranged(in: .threeFiveTwo)
        XCTAssertEqual(Set(lineup.players.map(\.id)), identities)
        XCTAssertEqual(lineup.formation, .threeFiveTwo)
        XCTAssertEqual(lineup.balanced().formation, .fourFourTwo)
        for formation in MatchFormation.allCases {
            let next = lineup.arranged(in: formation)
            XCTAssertTrue(next.isValid)
            XCTAssertEqual(next.formation.slots.count, 11)
            XCTAssertEqual(Set(next.players.map(\.id)), identities)
        }
    }

    func testRatingScaleIsFixedClampedAndAllowsHalfStars() {
        var player = team("a").players[0]
        for (rating, expected) in [(0.0, 1.0), (55, 1), (60, 1.5), (75, 3), (90, 4.5), (95, 5), (200, 5)] {
            player.rating = rating
            XCTAssertEqual(player.stars, expected)
        }
        player.rating = nil; player.estimatedRating = 80
        XCTAssertEqual(player.stars, 3.5)
        player.rating = .nan
        XCTAssertEqual(player.stars, 2.5)
    }

    func testTacticsChangeTargetsInBothDirectionsWithoutMovingPlayers() throws {
        for north in [true, false] {
            var simulation = FootballSimulation(configuration: configuration(), chooseStartingEnds: { north })
            let positions = simulation.roster.map(\.state.position)
            let sign = simulation.ends.attackSign(for: .blue)
            let normalForward = simulation.matchFormationTarget(for: 9, inPossession: false).y * sign
            let normalDefender = simulation.matchFormationTarget(for: 1, inPossession: true).y * sign
            var lineup = try XCTUnwrap(simulation.liveHomeLineup)
            lineup.style = .defensive
            XCTAssertTrue(simulation.updateTeamManagement(lineup, substitutions: []))
            XCTAssertLessThan(simulation.matchFormationTarget(for: 9, inPossession: false).y * sign, normalForward)
            lineup.style = .attacking
            XCTAssertTrue(simulation.updateTeamManagement(lineup, substitutions: []))
            XCTAssertGreaterThan(simulation.matchFormationTarget(for: 1, inPossession: true).y * sign, normalDefender)
            XCTAssertEqual(simulation.roster.map(\.state.position), positions)
        }
    }

    func testSubstitutionWaitsForStoppageAndKeepsRuntimeIdentityAndOtherCards() throws {
        var simulation = FootballSimulation(configuration: configuration())
        start(&simulation)
        let current = try XCTUnwrap(simulation.liveHomeLineup)
        let outgoing = current.players[5]
        let incoming = current.team.players[11]
        let runtimeID = try XCTUnwrap(simulation.roster.first { $0.clubPlayer?.id == outgoing.id }?.id)
        simulation.roster[1].yellowCards = 1
        simulation.roster[runtimeID].yellowCards = 1
        let draft = try XCTUnwrap(current.replacingPlayer(at: 5, with: incoming))
        XCTAssertTrue(simulation.updateTeamManagement(draft, substitutions: [.init(outgoingID: outgoing.id, incomingID: incoming.id)]))
        XCTAssertEqual(simulation.roster[runtimeID].clubPlayer?.id, outgoing.id)
        XCTAssertEqual(simulation.pendingSubstitutions.count, 1)
        stop(&simulation)
        XCTAssertEqual(simulation.roster[runtimeID].clubPlayer?.id, incoming.id)
        XCTAssertEqual(simulation.roster[runtimeID].yellowCards, 0)
        XCTAssertEqual(simulation.roster[1].yellowCards, 1)
        XCTAssertEqual(simulation.liveHomeLineup?.formation, .fourThreeThree)
        XCTAssertEqual(simulation.substitutionsUsed[.blue], 1)
        XCTAssertTrue(simulation.unavailableSquadIDs.contains(outgoing.id))
        XCTAssertTrue(simulation.pendingSubstitutions.isEmpty)
        XCTAssertEqual(simulation.configuration?.home, current)
    }

    func testCancelPendingSubstitutionDoesNotUseAllowance() throws {
        var simulation = FootballSimulation(configuration: configuration())
        start(&simulation)
        let current = try XCTUnwrap(simulation.liveHomeLineup)
        let draft = try XCTUnwrap(current.replacingPlayer(at: 5, with: current.team.players[11]))
        XCTAssertTrue(simulation.updateTeamManagement(draft, substitutions: [.init(outgoingID: current.players[5].id, incomingID: current.team.players[11].id)]))
        XCTAssertTrue(simulation.updateTeamManagement(current, substitutions: []))
        stop(&simulation)
        XCTAssertEqual(simulation.liveHomeLineup?.players, current.players)
        XCTAssertEqual(simulation.substitutionsUsed[.blue] ?? 0, 0)
    }

    func testFiveSubstitutionsNoReturnsAndExtraTimeRetainsLiveTeam() throws {
        var simulation = FootballSimulation(configuration: configuration())
        let initial = try XCTUnwrap(simulation.liveHomeLineup)
        for incomingIndex in [11, 12, 13, 14, 15] {
            let current = try XCTUnwrap(simulation.liveHomeLineup)
            let outgoing = current.players[5]
            let incoming = current.team.players[incomingIndex]
            let draft = try XCTUnwrap(current.replacingPlayer(at: 5, with: incoming))
            XCTAssertTrue(simulation.updateTeamManagement(draft, substitutions: [.init(outgoingID: outgoing.id, incomingID: incoming.id)]))
        }
        XCTAssertEqual(simulation.substitutionsUsed[.blue], 5)
        let current = try XCTUnwrap(simulation.liveHomeLineup)
        let sixth = try XCTUnwrap(current.replacingPlayer(at: 5, with: current.team.players[16]))
        XCTAssertFalse(simulation.updateTeamManagement(sixth, substitutions: [.init(outgoingID: current.players[5].id, incomingID: current.team.players[16].id)]))
        simulation.startAdditionalPeriod(duration: 60)
        XCTAssertEqual(simulation.substitutionsUsed[.blue], 5)
        XCTAssertEqual(simulation.liveHomeLineup, current)
        XCTAssertEqual(Set(simulation.roster.prefix(11).compactMap(\.clubPlayer?.id)), Set(current.players.map(\.id)))
        simulation.reset()
        XCTAssertEqual(simulation.liveHomeLineup, initial)
        XCTAssertTrue(simulation.substitutionsUsed.isEmpty)
    }

    func testSentOffPlayerCannotBeReplacedAndReturningPlayerIsRejected() throws {
        var simulation = FootballSimulation(configuration: configuration())
        let current = try XCTUnwrap(simulation.liveHomeLineup)
        let incoming = current.team.players[11]
        let draft = try XCTUnwrap(current.replacingPlayer(at: 5, with: incoming))
        let change = PendingSubstitution(outgoingID: current.players[5].id, incomingID: incoming.id)
        simulation.roster[5].isSentOff = true
        XCTAssertFalse(simulation.updateTeamManagement(draft, substitutions: [change]))
        simulation.roster[5].isSentOff = false
        XCTAssertTrue(simulation.updateTeamManagement(draft, substitutions: [change]))
        let live = try XCTUnwrap(simulation.liveHomeLineup)
        let slot = try XCTUnwrap(live.players.firstIndex { $0.id == incoming.id })
        let returning = try XCTUnwrap(live.replacingPlayer(at: slot, with: current.players[5]))
        XCTAssertFalse(simulation.updateTeamManagement(returning, substitutions: [.init(outgoingID: incoming.id, incomingID: current.players[5].id)]))
    }

    func testInjuryAfterFiveSubstitutionsContinuesWithTenPlayers() throws {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0; tuning.foulInjuryChance = 1
        var simulation = FootballSimulation(tuning: tuning, configuration: configuration())
        for incomingIndex in [11, 12, 13, 14, 15] {
            let current = try XCTUnwrap(simulation.liveHomeLineup)
            let incoming = current.team.players[incomingIndex]
            let draft = try XCTUnwrap(current.replacingPlayer(at: 5, with: incoming))
            XCTAssertTrue(simulation.updateTeamManagement(draft, substitutions: [
                .init(outgoingID: current.players[5].id, incomingID: incoming.id)
            ]))
        }
        start(&simulation)
        simulation.cancelInput()
        for id in simulation.roster.indices {
            simulation.roster[id].state = PlayerState(position: Vector2(x: id.isMultiple(of: 2) ? -28 : 28,
                y: id < 11 ? -25 : 0))
        }
        simulation.roster[0].state.position = Vector2(x: 0, y: -50)
        simulation.roster[11].state.position = Vector2(x: 0, y: 50)
        let spot = Vector2(x: 0, y: 20)
        simulation.roster[1].state = PlayerState(position: spot, facing: .up)
        simulation.ball = BallState(position: spot + Vector2.up * 0.9, mode: .free)
        simulation.step(dt: 1.0 / 60)
        simulation.roster[12].state = PlayerState(position: spot - Vector2.up * 1.44, facing: .up)
        simulation.ball = BallState(position: spot + Vector2(x: 0.9, y: -0.9), mode: .controlled)
        simulation.step(dt: 1.0 / 60)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        for _ in 0..<300 where simulation.pendingInjuryID == nil { simulation.step(dt: 1.0 / 60) }
        XCTAssertEqual(simulation.pendingInjuryID, 1)
        XCTAssertTrue(simulation.injuryReplacements.isEmpty)
        simulation.continueWithoutInjuryReplacement()
        XCTAssertNil(simulation.pendingInjuryID)
        XCTAssertEqual(simulation.roster.filter { $0.team == .blue && !$0.isUnavailable }.count, 10)
        XCTAssertEqual(simulation.substitutionsUsed[.blue], 5)
    }

    func testPendingSubstitutionCannotReplaceAPlayerSentOffBeforeStoppage() throws {
        var simulation = FootballSimulation(configuration: configuration())
        start(&simulation)
        let current = try XCTUnwrap(simulation.liveHomeLineup)
        let outgoing = current.players[5]
        let incoming = current.team.players[11]
        let draft = try XCTUnwrap(current.replacingPlayer(at: 5, with: incoming))
        XCTAssertTrue(simulation.updateTeamManagement(draft, substitutions: [.init(outgoingID: outgoing.id, incomingID: incoming.id)]))
        simulation.roster[5].isSentOff = true
        stop(&simulation)
        XCTAssertEqual(simulation.roster[5].clubPlayer?.id, outgoing.id)
        XCTAssertTrue(simulation.roster[5].isSentOff)
        XCTAssertEqual(simulation.substitutionsUsed[.blue] ?? 0, 0)
        XCTAssertTrue(simulation.pendingSubstitutions.isEmpty)
    }

    @MainActor
    func testManagementPausesAndNewMatchReturnsToPreparation() {
        let session = GameSession(configuration: configuration())
        session.showingTeamManagement = true
        XCTAssertTrue(session.scene.gameplayPaused)
        session.userPaused = true
        session.showingTeamManagement = false
        XCTAssertTrue(session.scene.gameplayPaused, "Closing management preserves an existing pause")
        session.userPaused = false
        XCTAssertFalse(session.scene.gameplayPaused)
        var requests = 0
        session.onPrepareMatch = { requests += 1 }
        session.showingSettings = true
        session.reset()
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(session.showingSettings)
    }

    func testLegacySavedSelectionsDecodeAndNewPreferencesRoundTrip() throws {
        let legacy = Data("{\"formation\":\"fourFourTwo\",\"playerIDs\":[\"a\"]}".utf8)
        XCTAssertNil(try JSONDecoder().decode(CareerLineupSelection.self, from: legacy).style)
        XCTAssertNil(try JSONDecoder().decode(WorldCupLineupSelection.self, from: legacy).style)
        var lineup = configuration().home
        lineup.style = .attacking; lineup.automaticFormation = false
        let saved = try JSONDecoder().decode(SavedTeamSelection.self, from: JSONEncoder().encode(SavedTeamSelection(lineup)))
        XCTAssertEqual(saved.restored(for: lineup.team), lineup)
    }
}
