import XCTest
@testable import TopScoresSoccer

@MainActor
final class CareerMatchSessionTests: XCTestCase {
    private func configuration() throws -> FriendlyMatchConfiguration {
        let teams = try PremierLeagueCatalogue.bundled().teams
        return FriendlyMatchConfiguration(home: .autoSelect(team: teams[0]), away: .autoSelect(team: teams[1]))
    }

    private func finish(_ session: GameSession) {
        session.scene.simulation.tuning.matchDuration = 0.5
        session.scene.pressAction()
        session.scene.releaseAction(heldFor: 0.12)
        for frame in 0..<240 {
            if session.scene.simulation.phase == .halfTime {
                XCTAssertFalse(session.careerResultSaved)
                session.resumeAfterHalfTime()
            }
            session.scene.update(Double(frame) / 60)
        }
        session.scene.refreshHUD()
        XCTAssertEqual(session.hud.phase, .fullTime)
    }

    func testFullTimeAutomaticallySavesOnceAndCareerCannotReset() throws {
        var writes = 0
        var result: [Int] = []
        let session = GameSession(configuration: try configuration(),
                                  careerContext: .init(fixtureTitle: "Matchweek 1 · Home", userIsAway: false)) { user, opponent in
            writes += 1
            result = [user, opponent]
        }
        XCTAssertFalse(session.careerResultSaved)
        session.saveCareerResult()
        XCTAssertEqual(writes, 0, "An unfinished match cannot be recorded")
        finish(session)
        XCTAssertTrue(session.careerResultSaved)
        XCTAssertEqual(result, [0, 0])
        session.scene.refreshHUD()
        session.saveCareerResult()
        session.reset()
        session.resetScore()
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(session.scene.simulation.phase, .fullTime)
    }

    func testFailedSavePreservesFinishedResultAndAllowsExplicitRetry() throws {
        enum SaveFailure: Error { case diskUnavailable }
        var writes = 0
        let session = GameSession(configuration: try configuration(),
                                  careerContext: .init(fixtureTitle: "Matchweek 1 · Away", userIsAway: true)) { _, _ in
            writes += 1
            if writes == 1 { throw SaveFailure.diskUnavailable }
        }
        finish(session)
        XCTAssertFalse(session.careerResultSaved)
        XCTAssertNotNil(session.careerSaveError)
        for _ in 0..<20 { session.scene.refreshHUD() }
        XCTAssertEqual(writes, 1, "An unavailable disk must not be retried every frame")
        session.saveCareerResult()
        XCTAssertEqual(writes, 2)
        XCTAssertTrue(session.careerResultSaved)
        XCTAssertNil(session.careerSaveError)
        XCTAssertEqual(session.scene.simulation.phase, .fullTime)
    }

    func testAwayVenuePreservesControlledPlayersAndMapsScoreboard() throws {
        let match = try configuration()
        let session = GameSession(configuration: match,
                                  careerContext: .init(fixtureTitle: "Matchweek 1 · Away", userIsAway: true)) { _, _ in }
        XCTAssertEqual(session.hud.homeName, match.home.team.displayName)
        XCTAssertEqual(session.hud.scoreboardHomeName, match.away.team.displayName)
        XCTAssertEqual(session.hud.scoreboardAwayName, match.home.team.displayName)
        let selected = try XCTUnwrap(session.scene.simulation.roster[session.hud.selectedPlayerID].clubPlayer)
        XCTAssertTrue(match.home.players.contains(where: { $0.id == selected.id }))
        XCTAssertTrue(session.hud.status.hasPrefix(match.home.team.displayName.uppercased()))
        var hud = session.hud
        hud.northGoals = 2
        hud.southGoals = 1
        XCTAssertEqual(hud.scoreboardHomeGoals, 1)
        XCTAssertEqual(hud.scoreboardAwayGoals, 2)
        XCTAssertEqual(hud.matchResult, "\(match.home.team.displayName) win")
    }

    func testAwayUserReceivesClashKitAndActualHomeKeepsColours() throws {
        var match = try configuration()
        match.home.team.primaryHex = "#DD0000"
        match.away.team.primaryHex = "#DD0000"
        let kits = MatchKits.resolveForPlay(configuration: match, userIsAway: true)
        XCTAssertEqual(kits.away.shirtHex, "#DD0000")
        XCTAssertNotEqual(kits.home.shirtHex, kits.away.shirtHex)
        let venue = MatchKits.resolve(configuration: .init(home: match.away, away: match.home))
        XCTAssertEqual(kits.home, venue.away)
        XCTAssertEqual(kits.away, venue.home)
    }

    func testForfeitRecordsAwardedScoreInUserOrderForEitherVenue() throws {
        for userIsAway in [false, true] {
            for loser in [Team.blue, .red] {
                var result: [Int] = []
                let session = GameSession(configuration: try configuration(),
                                          careerContext: .init(fixtureTitle: "Matchweek 1", userIsAway: userIsAway)) { user, opponent in
                    result = [user, opponent]
                }
                session.hud.phase = .practiceEnded(losingTeam: loser)
                session.hud.northGoals = 4
                session.hud.southGoals = 5
                session.saveCareerResult()
                XCTAssertEqual(result, loser == .blue ? [0, 3] : [3, 0])
                XCTAssertEqual(session.resultScore.home, userIsAway ? result[1] : result[0])
                XCTAssertEqual(session.resultScore.away, userIsAway ? result[0] : result[1])
                XCTAssertTrue(session.careerResultSaved)
            }
        }
    }
}
