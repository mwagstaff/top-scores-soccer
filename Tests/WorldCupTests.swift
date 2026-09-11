import XCTest
@testable import TopScoresSoccer

final class WorldCupTests: XCTestCase {
    private let win = WorldCupUserMatchOutcome(regulationUserGoals: 2, regulationOpponentGoals: 0,
        userGoals: 2, opponentGoals: 0, wentToExtraTime: false, userPenalties: nil, opponentPenalties: nil)

    func testCatalogueAndGroupScheduleContainTheComplete2026Shape() throws {
        let snapshot = NationalTeamCatalogue.snapshot()
        XCTAssertEqual(snapshot.teams.count, 48)
        XCTAssertEqual(Set(snapshot.teams.map(\.id)).count, 48)
        XCTAssertEqual(snapshot.groups.count, 12)
        XCTAssertTrue(snapshot.groups.allSatisfy { $0.count == 4 })

        let save = try WorldCupSave.new(snapshot: snapshot, selectedTeamID: "mex", seed: 7)
        let games = save.fixtures.filter { $0.stage == .group }
        XCTAssertEqual(games.count, 72)
        for matchday in 1...3 {
            let day = games.filter { $0.matchday == matchday }
            XCTAssertEqual(day.count, 24)
            XCTAssertEqual(Set(day.flatMap { [$0.homeTeamID, $0.awayTeamID] }).count, 48)
        }
        for groupIndex in snapshot.groups.indices {
            let name = String(UnicodeScalar(65 + groupIndex)!)
            let groupGames = games.filter { $0.group == name }
            XCTAssertEqual(groupGames.count, 6)
            let pairs = Set(groupGames.map { Set([$0.homeTeamID, $0.awayTeamID]) })
            XCTAssertEqual(pairs.count, 6)
        }
    }

    func testEveryNationalTeamHasItsOwnCountryFlag() {
        let teamIDs = NationalTeamCatalogue.snapshot().teams.map(\.id)
        let flags = teamIDs.map(NationalTeamCatalogue.flag(for:))
        XCTAssertEqual(flags.count, 48)
        XCTAssertFalse(flags.contains("🌐"))
        XCTAssertEqual(Set(flags).count, 48)
    }

    func testRankedSimulationFavoursStrongerTeamsButStillProducesUpsets() {
        var strongerWins = 0, upsets = 0, draws = 0, totalGoals = 0
        for seed in UInt64(1)...1_500 {
            let result = WorldCupResultSimulator.result(homeStrength: 90, awayStrength: 70,
                                                        knockout: false, seed: seed)
            totalGoals += result.homeGoals + result.awayGoals
            if result.homeGoals > result.awayGoals { strongerWins += 1 }
            else if result.homeGoals < result.awayGoals { upsets += 1 }
            else { draws += 1 }
        }
        XCTAssertGreaterThan(strongerWins, 900)
        XCTAssertGreaterThan(upsets, 5)
        XCTAssertGreaterThan(draws, 40)
        XCTAssertTrue((2_500...4_600).contains(totalGoals))
    }

    func testSimulatedKnockoutTiesCanFinishInExtraTimeOrOnPenalties() {
        var extraTimeFinishes = 0, shootouts = 0
        for seed in UInt64(1)...1_000 {
            let result = WorldCupResultSimulator.result(homeStrength: 82, awayStrength: 82,
                                                        knockout: true, seed: seed)
            XCTAssertNotNil(result.winnerIDSide)
            if result.wentToExtraTime && result.homePenalties == nil { extraTimeFinishes += 1 }
            if result.homePenalties != nil { shootouts += 1 }
        }
        XCTAssertGreaterThan(extraTimeFinishes, 20)
        XCTAssertGreaterThan(shootouts, 20)
    }

    func testCompletingAGroupMatchdayCreatesTheCompanionResultForTheResultsLozenge() throws {
        var save = try WorldCupSave.new(selectedTeamID: "eng", seed: 2026)
        let ticket = try save.prepareMatch()
        try save.completeFixture(ticketID: ticket.id, outcome: win)
        let completed = save.fixtures.filter { $0.stage == .group && $0.result != nil }
        let companion = completed.filter {
            $0.group == save.selectedGroupName
                && $0.homeTeamID != save.selectedTeamID && $0.awayTeamID != save.selectedTeamID
        }
        XCTAssertEqual(completed.count, 24)
        XCTAssertEqual(companion.count, 1)
    }

    func testThreeGroupWinsCreateAUniqueRoundOf32AndKeepUserAlive() throws {
        var save = try WorldCupSave.new(selectedTeamID: "mex", seed: 12)
        for matchday in 1...3 {
            let ticket = try save.prepareMatch()
            XCTAssertEqual(ticket.fixture.matchday, matchday)
            try save.completeFixture(ticketID: ticket.id, outcome: win)
        }
        XCTAssertTrue(save.groupStageComplete)
        let round = save.fixtures.filter { $0.stage == .roundOf32 }
        XCTAssertEqual(round.count, 16)
        XCTAssertEqual(Set(round.flatMap { [$0.homeTeamID, $0.awayTeamID] }).count, 32)
        XCTAssertEqual(save.nextFixture?.stage, .roundOf32)
        XCTAssertEqual(save.standings(forGroup: 0).first?.teamID, "mex")
        try save.validate()
    }

    func testUserCanWinEightMatchesAndCelebrationIsSetOnlyAfterFinal() throws {
        var save = try WorldCupSave.new(selectedTeamID: "mex", seed: 33)
        var played = 0
        while let ticket = try? save.prepareMatch() {
            try save.completeFixture(ticketID: ticket.id, outcome: win)
            played += 1
            XCTAssertLessThanOrEqual(played, 8)
        }
        XCTAssertEqual(played, 8)
        XCTAssertTrue(save.tournamentComplete)
        XCTAssertEqual(save.championTeamID, "mex")
        XCTAssertTrue(save.celebrationPending)
        XCTAssertTrue(save.userIsChampion)
        save.acknowledgeCelebration()
        XCTAssertFalse(save.celebrationPending)
        XCTAssertTrue(save.celebrationAcknowledged)
        try save.validate()
    }

    func testKnockoutExtraTimeAndPenaltyResultRoundTripsInActualFixtureOrder() throws {
        var save = try WorldCupSave.new(selectedTeamID: "mex", seed: 44)
        for _ in 0..<3 {
            let ticket = try save.prepareMatch()
            try save.completeFixture(ticketID: ticket.id, outcome: win)
        }
        let ticket = try save.prepareMatch()
        let shootout = WorldCupUserMatchOutcome(regulationUserGoals: 1, regulationOpponentGoals: 1,
            userGoals: 1, opponentGoals: 1, wentToExtraTime: true, userPenalties: 5, opponentPenalties: 4)
        try save.completeFixture(ticketID: ticket.id, outcome: shootout)
        let stored = try XCTUnwrap(save.fixtures.first { $0.id == ticket.id }?.result)
        XCTAssertTrue(stored.wentToExtraTime)
        XCTAssertEqual(stored.winnerIDSide, ticket.userIsAway ? 1 : 0)
        XCTAssertEqual([stored.homePenalties, stored.awayPenalties].compactMap { $0 }.sorted(), [4, 5])
        XCTAssertEqual(save.nextFixture?.stage, .roundOf16)
        let otherRoundOf32Results = save.fixtures.filter {
            $0.stage == .roundOf32 && $0.result != nil
                && $0.homeTeamID != save.selectedTeamID && $0.awayTeamID != save.selectedTeamID
        }
        XCTAssertEqual(otherRoundOf32Results.count, 15)
        XCTAssertTrue(otherRoundOf32Results.allSatisfy { $0.result?.winnerIDSide != nil })
    }

    func testPenaltyShootoutAlwaysResolvesAfterFiveKicksOrSuddenDeath() {
        var shootout = PenaltyShootout(seed: 2026)
        var choices = 0
        while !shootout.isFinished && choices < 40 {
            shootout.choose(PenaltyDirection.allCases[choices % 3])
            choices += 1
        }
        XCTAssertTrue(shootout.isFinished)
        XCTAssertNotEqual(shootout.userGoals, shootout.opponentGoals)
        XCTAssertLessThan(choices, 40)
    }

    @MainActor
    func testTiedKnockoutMatchMovesFromNinetyMinutesToExtraTimeThenPenalties() throws {
        let snapshot = NationalTeamCatalogue.snapshot()
        let home = ClubLineup.autoSelect(team: snapshot.teams[0])
        let away = ClubLineup.autoSelect(team: snapshot.teams[1])
        var savedOutcome: WorldCupUserMatchOutcome?
        let session = GameSession(configuration: .init(home: home, away: away),
            worldCupContext: .init(fixtureTitle: "Final", userIsAway: false,
                                   isKnockout: true, shootoutSeed: 9)) { savedOutcome = $0 }
        session.scene.simulation.tuning.matchDuration = 0.05
        session.scene.simulation.pressAction()
        session.scene.simulation.releaseAction(heldFor: 0.1)
        for _ in 0..<180 where session.scene.simulation.phase != .fullTime {
            if session.scene.simulation.phase == .halfTime { session.resumeAfterHalfTime() }
            session.scene.simulation.step(dt: 1.0 / 60)
        }
        session.scene.refreshHUD()
        XCTAssertTrue(session.needsExtraTime)
        XCTAssertNil(savedOutcome)

        session.startExtraTime()
        session.scene.simulation.tuning.matchDuration = 0.05
        session.scene.simulation.pressAction()
        session.scene.simulation.releaseAction(heldFor: 0.1)
        for _ in 0..<180 where session.scene.simulation.phase != .fullTime {
            if session.scene.simulation.phase == .halfTime { session.resumeAfterHalfTime() }
            session.scene.simulation.step(dt: 1.0 / 60)
        }
        session.scene.refreshHUD()
        XCTAssertNotNil(session.penaltyShootout)
        XCTAssertNil(savedOutcome)

        var choices = 0
        while session.penaltyShootout?.isFinished == false && choices < 40 {
            session.choosePenalty(PenaltyDirection.allCases[choices % 3])
            choices += 1
        }
        XCTAssertTrue(session.worldCupResultSaved)
        XCTAssertEqual(savedOutcome?.wentToExtraTime, true)
        XCTAssertNotNil(savedOutcome?.userPenalties)
        XCTAssertNotEqual(savedOutcome?.userPenalties, savedOutcome?.opponentPenalties)
    }

#if DEBUG
    @MainActor
    func testDebugGroupShortcutsSaveWinDrawAndDefeatThroughTheRealCallback() throws {
        let snapshot = NationalTeamCatalogue.snapshot()
        let configuration = FriendlyMatchConfiguration(home: ClubLineup.autoSelect(team: snapshot.teams[0]),
                                                       away: ClubLineup.autoSelect(team: snapshot.teams[1]))
        let cases: [(WorldCupDebugMatchAction, Int, Int)] = [
            (.win, 1, 0), (.draw, 0, 0), (.defeat, 0, 1)
        ]

        for (action, userGoals, opponentGoals) in cases {
            var savedOutcome: WorldCupUserMatchOutcome?
            let session = GameSession(configuration: configuration,
                worldCupContext: .init(fixtureTitle: "Group A · Matchday 1", userIsAway: false,
                                       isKnockout: false, shootoutSeed: 1)) { savedOutcome = $0 }
            session.debugAdvanceWorldCupMatch(action)
            XCTAssertTrue(session.worldCupResultSaved)
            XCTAssertEqual(savedOutcome?.userGoals, userGoals)
            XCTAssertEqual(savedOutcome?.opponentGoals, opponentGoals)
            XCTAssertEqual(savedOutcome?.wentToExtraTime, false)
        }
    }

    @MainActor
    func testDebugKnockoutShortcutsReachDrawExtraTimeAndShootoutStates() throws {
        let snapshot = NationalTeamCatalogue.snapshot()
        let configuration = FriendlyMatchConfiguration(home: ClubLineup.autoSelect(team: snapshot.teams[0]),
                                                       away: ClubLineup.autoSelect(team: snapshot.teams[1]))
        func session(onSave: @escaping (WorldCupUserMatchOutcome) -> Void = { _ in }) -> GameSession {
            GameSession(configuration: configuration,
                worldCupContext: .init(fixtureTitle: "Final", userIsAway: false,
                                       isKnockout: true, shootoutSeed: 2026),
                onWorldCupComplete: onSave)
        }

        let drawn = session()
        drawn.debugAdvanceWorldCupMatch(.draw)
        XCTAssertTrue(drawn.needsExtraTime)
        XCTAssertFalse(drawn.worldCupResultSaved)

        let extraTime = session()
        extraTime.debugAdvanceWorldCupMatch(.extraTime)
        XCTAssertEqual(extraTime.tournamentPeriod, .extraTime)
        XCTAssertEqual(extraTime.hud.phase, .playing)
        XCTAssertFalse(extraTime.needsExtraTime)

        var savedOutcome: WorldCupUserMatchOutcome?
        let shootout = session { savedOutcome = $0 }
        shootout.debugAdvanceWorldCupMatch(.penaltyShootout)
        XCTAssertNotNil(shootout.penaltyShootout)
        XCTAssertEqual(shootout.tournamentPeriod, .extraTime)
        var choices = 0
        while shootout.penaltyShootout?.isFinished == false && choices < 40 {
            shootout.choosePenalty(PenaltyDirection.allCases[choices % 3])
            choices += 1
        }
        XCTAssertTrue(shootout.worldCupResultSaved)
        XCTAssertEqual(savedOutcome?.wentToExtraTime, true)
        XCTAssertNotEqual(savedOutcome?.userPenalties, savedOutcome?.opponentPenalties)
    }

    @MainActor
    func testEightDebugWinsCompleteThePersistedTournamentEndToEnd() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorldCupStore(saveURL: directory.appendingPathComponent("world.json"))
        try store.start(teamID: "mex")
        var matches = 0

        while let ticket = try? store.prepareMatch() {
            let session = GameSession(configuration: ticket.configuration,
                worldCupContext: .init(fixtureTitle: ticket.fixture.stage.title,
                                       userIsAway: ticket.userIsAway,
                                       isKnockout: ticket.fixture.stage.isKnockout,
                                       shootoutSeed: ticket.seed)) { outcome in
                    _ = try store.completeFixture(ticketID: ticket.id, outcome: outcome)
                }
            session.debugAdvanceWorldCupMatch(.win)
            XCTAssertTrue(session.worldCupResultSaved)
            matches += 1
            XCTAssertLessThanOrEqual(matches, 8)
        }

        XCTAssertEqual(matches, 8)
        XCTAssertTrue(store.save?.userIsChampion == true)
        XCTAssertTrue(store.save?.celebrationPending == true)
        XCTAssertNil(store.save?.nextFixture)
        let reloaded = WorldCupStore(saveURL: directory.appendingPathComponent("world.json"))
        XCTAssertTrue(reloaded.save?.userIsChampion == true)
        XCTAssertTrue(reloaded.save?.celebrationPending == true)
    }
#endif

    @MainActor
    func testWorldCupStorePersistsIndependentlyFromCareerPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let worldURL = directory.appendingPathComponent("world.json")
        let careerURL = directory.appendingPathComponent("career.json")
        let store = WorldCupStore(saveURL: worldURL)
        try store.start(teamID: "eng")
        XCTAssertTrue(FileManager.default.fileExists(atPath: worldURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: careerURL.path))
        let reloaded = WorldCupStore(saveURL: worldURL)
        XCTAssertEqual(reloaded.save?.selectedTeamID, "eng")
        XCTAssertEqual(reloaded.save?.nextFixture?.matchday, 1)
    }
}
