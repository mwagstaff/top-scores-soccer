import XCTest
@testable import TopScoresSoccer

final class CareerTests: XCTestCase {
    private func teams() -> [ClubTeam] {
        (1...20).map { index in
            let id = String(index)
            let roles = ["G", "D", "D", "D", "D", "M", "M", "M", "M", "F", "F", "G", "D", "F"]
            let players = roles.enumerated().map { slot, role in
                let playerID = "\(id)-\(slot)"
                return ClubPlayer(id: playerID, name: "Player \(playerID)", position: role,
                                  jerseyNumber: slot + 1, rating: Double(66 + index),
                                  appearance: .generated(for: playerID))
            }
            return ClubTeam(id: id, name: String(format: "Club %02d", index),
                            primaryHex: "#B02030", secondaryHex: "#FFFFFF", players: players)
        }
    }

    private func career(clubID: String = "1") throws -> CareerSave {
        try .new(teams: teams(), clubID: clubID, snapshotID: "frozen-snapshot",
                 date: Date(timeIntervalSince1970: 1_000), seed: 17)
    }

    private func finishSeason(_ career: inout CareerSave) throws {
        while let fixture = career.nextFixture {
            try career.completeFixture(ticketID: fixture.id, userGoals: 2, opponentGoals: 1)
        }
    }

    func testScheduleHasEveryOpponentAtBothVenuesAndOnlyOneGamePerRound() throws {
        let save = try career()
        XCTAssertEqual(save.fixtures.count, 380)
        XCTAssertEqual(Set(save.fixtures.map(\.id)).count, 380)
        for round in 1...38 {
            let games = save.fixtures.filter { $0.round == round }
            XCTAssertEqual(games.count, 10)
            XCTAssertEqual(Set(games.flatMap { [$0.homeClubID, $0.awayClubID] }).count, 20)
        }
        for team in save.teams {
            let home = save.fixtures.filter { $0.homeClubID == team.id }
            let away = save.fixtures.filter { $0.awayClubID == team.id }
            XCTAssertEqual(home.count, 19)
            XCTAssertEqual(away.count, 19)
            XCTAssertEqual(Set(home.map(\.awayClubID)), Set(save.teams.map(\.id)).subtracting([team.id]))
            XCTAssertEqual(Set(away.map(\.homeClubID)), Set(save.teams.map(\.id)).subtracting([team.id]))
            let venues = save.fixtures.filter { $0.homeClubID == team.id || $0.awayClubID == team.id }.map { $0.homeClubID == team.id }
            var streak = 1
            for index in 1..<venues.count {
                streak = venues[index] == venues[index - 1] ? streak + 1 : 1
                XCTAssertLessThanOrEqual(streak, 3, "Avoid long runs of only home or only away games.")
            }
        }
    }

    func testAwayTicketKeepsControlWithSelectedClubAndMapsActualVenueResult() throws {
        var save = try career(clubID: "9") // Lexical final ID plays away to the pivot club in round one.
        let ticket = try save.prepareMatch()
        XCTAssertTrue(ticket.userIsAway)
        XCTAssertEqual(ticket.configuration.home.team.id, "9")
        XCTAssertEqual(ticket.configuration.away.team.id, "1")
        XCTAssertEqual(ticket.fixture.homeClubID, "1")
        XCTAssertTrue(try save.completeFixture(ticketID: ticket.id, userGoals: 3, opponentGoals: 1))
        XCTAssertEqual(save.fixtures.first { $0.id == ticket.id }?.result, .init(homeGoals: 1, awayGoals: 3))
        let selected = try XCTUnwrap(save.standings.first { $0.clubID == "9" })
        XCTAssertEqual(selected.points, 3)
        XCTAssertEqual(selected.goalsFor, 3)
        XCTAssertEqual(selected.goalsAgainst, 1)
        XCTAssertEqual(save.currentRound, 2)
        XCTAssertEqual(save.fixtures.filter { $0.result != nil }.count, 10)
        XCTAssertTrue(save.standings.allSatisfy { $0.played == 1 })
    }

    func testRoundSimulationIsDeterministicAcrossResumeAndHasBoundedScores() throws {
        var first = try career()
        var resumed = try JSONDecoder().decode(CareerSave.self, from: JSONEncoder().encode(first))
        let ticket = try first.prepareMatch()
        try first.completeFixture(ticketID: ticket.id, userGoals: 1, opponentGoals: 1)
        try resumed.completeFixture(ticketID: ticket.id, userGoals: 1, opponentGoals: 1)
        XCTAssertEqual(first, resumed)
        let aiResults = first.fixtures.filter { $0.round == 1 && $0.id != ticket.id }.compactMap(\.result)
        XCTAssertEqual(aiResults.count, 9)
        XCTAssertTrue(aiResults.allSatisfy { (0...8).contains($0.homeGoals) && (0...8).contains($0.awayGoals) })
    }

    func testAIRoundUsesOverallStartingXIQualityWithTheSameRandomDraws() throws {
        let baseline = try career()
        let userFixture = try XCTUnwrap(baseline.nextFixture)
        let otherFixture = try XCTUnwrap(baseline.fixtures.first { $0.round == 1 && $0.id != userFixture.id })
        let teamIndex = try XCTUnwrap(baseline.teams.firstIndex { $0.id == otherFixture.homeClubID })
        var lowTotal = 0
        var highTotal = 0
        for seed in 1...32 {
            var lower = baseline
            var higher = baseline
            lower.seed = UInt64(seed)
            higher.seed = UInt64(seed)
            for index in lower.teams[teamIndex].players.indices {
                lower.teams[teamIndex].players[index].rating = 55
                higher.teams[teamIndex].players[index].rating = 95
            }
            try lower.completeFixture(ticketID: userFixture.id, userGoals: 0, opponentGoals: 0)
            try higher.completeFixture(ticketID: userFixture.id, userGoals: 0, opponentGoals: 0)
            let lowGoals = try XCTUnwrap(lower.fixtures.first { $0.id == otherFixture.id }?.result?.homeGoals)
            let highGoals = try XCTUnwrap(higher.fixtures.first { $0.id == otherFixture.id }?.result?.homeGoals)
            XCTAssertGreaterThanOrEqual(highGoals, lowGoals)
            lowTotal += lowGoals
            highTotal += highGoals
        }
        XCTAssertGreaterThan(highTotal, lowTotal)
    }

    func testExactlyOneRoundAdvancesAndDuplicateResultCannotAwardMorePoints() throws {
        var save = try career()
        let ticket = try save.prepareMatch()
        try save.completeFixture(ticketID: ticket.id, userGoals: 4, opponentGoals: 0)
        let committed = save
        XCTAssertFalse(try save.completeFixture(ticketID: ticket.id, userGoals: 4, opponentGoals: 0))
        XCTAssertEqual(save, committed)
        XCTAssertThrowsError(try save.completeFixture(ticketID: ticket.id, userGoals: 0, opponentGoals: 4)) {
            XCTAssertEqual($0 as? CareerError, .resultAlreadyRecorded)
        }
        XCTAssertThrowsError(try save.completeFixture(ticketID: "different-career", userGoals: 4, opponentGoals: 0))
        XCTAssertThrowsError(try save.completeFixture(ticketID: save.nextFixture!.id, userGoals: -1, opponentGoals: 0))
        XCTAssertEqual(save, committed)
    }

    func testFullSeasonBalancesTableAndArchivesBeforeStartingFreshSeason() throws {
        var save = try career()
        let firstTicket = try save.prepareMatch()
        let frozen = save.teams
        let startingLineup = save.lineupSelection
        XCTAssertThrowsError(try save.startNextSeason())
        try finishSeason(&save)
        XCTAssertTrue(save.isSeasonComplete)
        XCTAssertNil(save.nextFixture)
        XCTAssertEqual(save.completedRounds, 38)
        XCTAssertEqual(save.standings.map(\.played), Array(repeating: 38, count: 20))
        let champion = try XCTUnwrap(save.standings.first)
        XCTAssertEqual(champion.clubID, "1")
        XCTAssertEqual(champion.won, 38)
        XCTAssertEqual(champion.points, 114)
        XCTAssertEqual(save.standings.reduce(0) { $0 + $1.goalsFor }, save.standings.reduce(0) { $0 + $1.goalsAgainst })
        XCTAssertEqual(save.standings.reduce(0) { $0 + $1.won }, save.standings.reduce(0) { $0 + $1.lost })
        let finalTable = save.standings
        try save.startNextSeason(date: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(save.seasonNumber, 2)
        XCTAssertEqual(save.archives.count, 1)
        XCTAssertEqual(save.archives.first?.standings, finalTable)
        XCTAssertEqual(save.archives.first?.fixtures.count, 380)
        XCTAssertEqual(save.currentRound, 1)
        XCTAssertEqual(save.completedRounds, 0)
        XCTAssertEqual(save.teams, frozen)
        XCTAssertEqual(save.lineupSelection, startingLineup)
        XCTAssertTrue(save.standings.allSatisfy { $0.played == 0 && $0.points == 0 })
        XCTAssertNotEqual(save.nextFixture?.id, firstTicket.id)
        XCTAssertFalse(try save.completeFixture(ticketID: firstTicket.id, userGoals: 2, opponentGoals: 1))
        XCTAssertEqual(save.completedRounds, 0)
    }

    func testTableBreaksTiesByGoalDifferenceThenGoalsScoredThenClubName() throws {
        var save = try career()
        XCTAssertEqual(save.standings.map(\.clubName), save.teams.map(\.name).sorted())
        // Give all home clubs a win: differing margins first, then a shared margin with more goals.
        for index in 0..<10 {
            let result: CareerResult
            switch index {
            case 0: result = .init(homeGoals: 1, awayGoals: 0)
            case 1: result = .init(homeGoals: 2, awayGoals: 0)
            case 2: result = .init(homeGoals: 3, awayGoals: 1)
            default: result = .init(homeGoals: 0, awayGoals: 0)
            }
            save.fixtures[index].result = result
        }
        try save.validate()
        XCTAssertEqual(save.standings.prefix(3).map(\.clubID), [save.fixtures[2].homeClubID, save.fixtures[1].homeClubID, save.fixtures[0].homeClubID])
        XCTAssertTrue(save.standings.filter { $0.drawn == 1 }.allSatisfy { $0.points == 1 })
    }

    func testCareerSquadAndAppearanceRemainFrozenWhenLiveTeamValuesChange() throws {
        var liveTeams = teams()
        var save = try CareerSave.new(teams: liveTeams, clubID: "1", snapshotID: "snapshot-one")
        let frozen = save.teams
        liveTeams[0].players[0].rating = 99
        liveTeams[0].players[0].appearance.skinHex = "#FFFFFF"
        liveTeams[0].players.removeLast()
        XCTAssertEqual(save.teams, frozen)
        XCTAssertThrowsError(try save.updateLineup(.autoSelect(team: liveTeams[0])))
        var selection = ClubLineup.autoSelect(team: save.selectedClub, formation: .fourThreeThree)
        selection = try XCTUnwrap(selection.replacingPlayer(at: 8, with: save.selectedClub.players.last!))
        try save.updateLineup(selection)
        let restored = try JSONDecoder().decode(CareerSave.self, from: JSONEncoder().encode(save))
        try restored.validate()
        XCTAssertEqual(restored.lineup, selection)
        XCTAssertEqual(restored.snapshotID, "snapshot-one")
    }

    func testValidationRejectsDuplicateClubsPlayersFixturesAndPartialRounds() throws {
        let valid = try career()
        var duplicateClub = valid
        duplicateClub.teams[1] = duplicateClub.teams[0]
        XCTAssertThrowsError(try duplicateClub.validate())
        var duplicatePlayer = valid
        duplicatePlayer.teams[0].players[1] = duplicatePlayer.teams[0].players[0]
        XCTAssertThrowsError(try duplicatePlayer.validate())
        var duplicateFixture = valid
        duplicateFixture.fixtures[1] = duplicateFixture.fixtures[0]
        XCTAssertThrowsError(try duplicateFixture.validate())
        var partial = valid
        partial.fixtures[0].result = .init(homeGoals: 0, awayGoals: 0)
        XCTAssertThrowsError(try partial.validate())
        var wrongClub = valid
        wrongClub.selectedClubID = "unknown"
        XCTAssertThrowsError(try wrongClub.validate())
        var future = valid
        future.schemaVersion = 99
        XCTAssertThrowsError(try future.validate()) { XCTAssertEqual($0 as? CareerError, .unsupportedVersion) }
        var missingPlayer = valid
        missingPlayer.lineupSelection.playerIDs[0] = "unknown"
        XCTAssertThrowsError(try missingPlayer.validate())
        var extraPlayer = valid
        extraPlayer.lineupSelection.playerIDs.append("unknown")
        XCTAssertThrowsError(try extraPlayer.validate())
        var noKeeper = valid
        noKeeper.teams[1].players.removeAll { $0.role == "G" }
        XCTAssertThrowsError(try noKeeper.validate())
    }

    @MainActor
    func testStoreResumesFrozenSquadSelectionAndEntireCompletedRound() throws {
        let url = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CareerStore(saveURL: url)
        XCTAssertNil(store.save)
        try store.start(teams: teams(), clubID: "1", snapshotID: "original")
        let selection = ClubLineup.autoSelect(team: try XCTUnwrap(store.save?.selectedClub), formation: .fourTwoThreeOne)
        try store.updateLineup(selection)
        let ticket = try store.prepareMatch()
        try store.completeFixture(ticketID: ticket.id, userGoals: 1, opponentGoals: 0)
        let resumed = CareerStore(saveURL: url)
        XCTAssertNil(resumed.loadError)
        XCTAssertEqual(resumed.save, store.save)
        XCTAssertEqual(resumed.save?.completedRounds, 1)
        XCTAssertEqual(resumed.save?.lineup, selection)
    }

    @MainActor
    func testFailedWriteKeepsPublishedProgressAndLastUsableFile() throws {
        let url = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let initial = CareerStore(saveURL: url)
        try initial.start(teams: teams(), clubID: "1", snapshotID: "original")
        let previousData = try Data(contentsOf: url)
        let store = CareerStore(saveURL: url, write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let before = store.save
        let ticket = try store.prepareMatch()
        XCTAssertThrowsError(try store.completeFixture(ticketID: ticket.id, userGoals: 3, opponentGoals: 0))
        XCTAssertEqual(store.save, before)
        XCTAssertEqual(try Data(contentsOf: url), previousData)
        XCTAssertNotNil(store.actionError)
    }

    @MainActor
    func testUnreadableAndUnsupportedSavesAreRetainedUntilExplicitReplacement() throws {
        let url = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data("{ interrupted save".utf8)
        try broken.write(to: url)
        let unreadable = CareerStore(saveURL: url)
        XCTAssertNil(unreadable.save)
        XCTAssertNotNil(unreadable.loadError)
        XCTAssertEqual(try Data(contentsOf: url), broken)
        var future = try career()
        future.schemaVersion = 100
        let unsupported = try JSONEncoder().encode(future)
        try unsupported.write(to: url)
        let store = CareerStore(saveURL: url)
        XCTAssertNil(store.save)
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(try Data(contentsOf: url), unsupported)
        // Mirrors the UI's explicit confirmation to replace the kept file.
        try store.start(teams: teams(), clubID: "9", snapshotID: "new")
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.save?.selectedClubID, "9")
        XCTAssertNotEqual(try Data(contentsOf: url), unsupported)
    }

    @MainActor
    func testRepeatedStoreCallbackAvoidsASecondDiskWriteAndDeleteClearsSave() throws {
        let url = temporarySaveURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var writes = 0
        let store = CareerStore(saveURL: url, write: { data, path in
            writes += 1
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: path, options: .atomic)
        })
        try store.start(teams: teams(), clubID: "1", snapshotID: "original")
        let ticket = try store.prepareMatch()
        XCTAssertTrue(try store.completeFixture(ticketID: ticket.id, userGoals: 0, opponentGoals: 0))
        XCTAssertFalse(try store.completeFixture(ticketID: ticket.id, userGoals: 0, opponentGoals: 0))
        XCTAssertEqual(writes, 2)
        try store.deleteCareer()
        XCTAssertNil(store.save)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func temporarySaveURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CareerCoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("career.json")
    }
}
