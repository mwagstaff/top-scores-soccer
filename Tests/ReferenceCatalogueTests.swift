import XCTest
@testable import TopScoresSoccer

@MainActor
final class ReferenceCatalogueTests: XCTestCase {
    func testBundledPremierLeagueHasTwentyPlayableClubsInEveryFormation() throws {
        let catalogue = try PremierLeagueCatalogue.bundled()
        XCTAssertEqual(catalogue.teams.count, 20)
        XCTAssertEqual(Set(catalogue.teams.map(\.id)).count, 20)
        for team in catalogue.teams {
            for formation in MatchFormation.allCases {
                let lineup = ClubLineup.autoSelect(team: team, formation: formation)
                XCTAssertTrue(lineup.isValid, "\(team.name) \(formation.title)")
                XCTAssertEqual(lineup.players.first?.role, "G")
                XCTAssertEqual(Set(lineup.players.map(\.id)).count, 11)
            }
        }
        let skins = Set(catalogue.teams.flatMap(\.players).map(\.appearance.skinHex))
        XCTAssertGreaterThanOrEqual(skins.count, 5)
    }

    func testDecoderPreservesMissingAndZeroRatingsAndSquadShirtNumber() throws {
        let data = try modifiedExport { export in
            var payload = export["data"] as! [String: Any]
            var teams = payload["teams"] as! [[String: Any]]
            var squad = teams[0]["squad"] as! [String: Any]
            var members = squad["players"] as! [[String: Any]]
            var first = members[0]["player"] as! [String: Any]
            first["rating"] = 0
            first["jersey_number"] = 99
            members[0]["player"] = first
            members[0]["jersey_number"] = 42
            var second = members[1]["player"] as! [String: Any]
            second["rating"] = NSNull()
            members[1]["player"] = second
            squad["players"] = members
            teams[0]["squad"] = squad
            payload["teams"] = teams
            export["data"] = payload
        }
        let catalogue = try PremierLeagueCatalogue.decode(data)
        let liverpool = try XCTUnwrap(catalogue.teams.first(where: { $0.id == "1" }))
        let zero = try XCTUnwrap(liverpool.players.first(where: { $0.id == "1077" }))
        XCTAssertEqual(zero.rating, 0)
        XCTAssertEqual(zero.effectiveRating, 0)
        XCTAssertEqual(zero.jerseyNumber, 42)
        let missing = try XCTUnwrap(liverpool.players.first(where: { $0.id == "2261" }))
        XCTAssertNil(missing.rating)
        XCTAssertTrue(missing.isRatingEstimated)
        XCTAssertTrue((65...82).contains(missing.effectiveRating))
    }

    func testRejectsPartialExportRatherThanRemovingClubsFromActiveCatalogue() throws {
        let data = try modifiedExport { export in
            var payload = export["data"] as! [String: Any]
            var teams = payload["teams"] as! [[String: Any]]
            teams.removeLast()
            payload["teams"] = teams
            export["data"] = payload
        }
        XCTAssertThrowsError(try PremierLeagueCatalogue.decode(data))
    }

    func testEmptySquadUsesStableLabelledStandInsAndARealGoalkeeperRole() {
        let empty = ClubTeam(id: "empty", name: "Empty Club", primaryHex: "#FFFFFF", secondaryHex: "#111111", players: [])
        let first = ClubLineup.autoSelect(team: empty)
        let second = ClubLineup.autoSelect(team: empty)
        XCTAssertTrue(first.isValid)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.players.allSatisfy(\.isGenerated))
        XCTAssertTrue(first.players.allSatisfy { $0.name.contains("Stand-in") && $0.rating == nil })
        XCTAssertEqual(first.players.first?.role, "G")
    }

    func testSelectionReservesScarceSpecialistsBeforeFillingOtherSlots() {
        var players = [player("keeper", role: "G", rating: 70), player("striker", role: "F", rating: 95)]
        players += (0..<12).map { player("mid-\($0)", role: "M", rating: Double(70 + $0)) }
        let team = ClubTeam(id: "sparse", name: "Sparse", primaryHex: "#FFFFFF", secondaryHex: "#111111", players: players)
        let lineup = ClubLineup.autoSelect(team: team, formation: .fourTwoThreeOne)
        XCTAssertTrue(lineup.isValid)
        XCTAssertEqual(lineup.players.last?.id, "striker")
    }

    func testManualSelectionSwapsStartersAndRejectsKeeperOrForeignPlayer() throws {
        let catalogue = try PremierLeagueCatalogue.bundled()
        let lineup = ClubLineup.autoSelect(team: catalogue.teams[0])
        let swapped = try XCTUnwrap(lineup.replacingPlayer(at: 1, with: lineup.players[2]))
        XCTAssertEqual(swapped.players[1].id, lineup.players[2].id)
        XCTAssertEqual(swapped.players[2].id, lineup.players[1].id)
        XCTAssertTrue(swapped.isValid)
        XCTAssertNil(lineup.replacingPlayer(at: 0, with: lineup.players[1]))
        XCTAssertNil(lineup.replacingPlayer(at: 1, with: player("foreign", role: "D", rating: 99)))
    }

    func testAppearanceOverrideSurvivesImportAndFallbackIsStable() throws {
        let override = PlayerAppearance(skinHex: "#123456", hairHex: "#654321", hairStyle: 2)
        let catalogue = try PremierLeagueCatalogue.decode(bundledData(), appearanceOverrides: ["1077": override])
        let player = try XCTUnwrap(catalogue.teams.flatMap(\.players).first(where: { $0.id == "1077" }))
        XCTAssertEqual(player.appearance, override)
        XCTAssertEqual(PlayerAppearance.generated(for: "363"), PlayerAppearance.generated(for: "363"))
    }

    func testETagAnd304PreserveRosterAndPersistAcrossRepositoryInstances() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = ReferenceTestTransport(steps: [.init(status: 200, data: try bundledData(), headers: ["ETag": "test-snapshot"]),
                                                      .init(status: 304, data: Data())])
        let repository = PremierLeagueRepository(cacheDirectory: directory, fetch: { try await transport.fetch($0) })
        let first = try await repository.refresh(force: true, now: Date(timeIntervalSince1970: 100))
        let second = try await repository.refresh(force: true, now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(first.catalogue.teams, second.catalogue.teams)
        let requests = await transport.requests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "If-None-Match"), "test-snapshot")
        let reloaded = PremierLeagueRepository(cacheDirectory: directory)
        let cached = await reloaded.cached()
        XCTAssertEqual(cached?.catalogue.teams, first.catalogue.teams)
        XCTAssertEqual(cached?.checkedAt, Date(timeIntervalSince1970: 200))
    }

    func testMalformedRefreshDoesNotReplaceLastValidCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = ReferenceTestTransport(steps: [.init(status: 200, data: try bundledData()),
                                                      .init(status: 200, data: Data("{}".utf8))])
        let repository = PremierLeagueRepository(cacheDirectory: directory, fetch: { try await transport.fetch($0) })
        let first = try await repository.refresh(force: true)
        do {
            _ = try await repository.refresh(force: true)
            XCTFail("An invalid export must fail validation.")
        } catch {}
        let cached = await repository.cached()
        XCTAssertEqual(cached?.catalogue.teams, first.catalogue.teams)
    }

    func testDailyGateAndRetryAfterAvoidRepeatedDownloads() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = ReferenceTestTransport(steps: [.init(status: 200, data: try bundledData()),
                                                      .init(status: 429, data: Data(), headers: ["Retry-After": "120"])])
        let repository = PremierLeagueRepository(cacheDirectory: directory, fetch: { try await transport.fetch($0) })
        _ = try await repository.refresh(now: Date(timeIntervalSince1970: 100))
        _ = try await repository.refresh(now: Date(timeIntervalSince1970: 200))
        let firstCount = await transport.requests.count
        XCTAssertEqual(firstCount, 1)
        for now in [300.0, 350] {
            do {
                _ = try await repository.refresh(force: true, now: Date(timeIntervalSince1970: now))
                XCTFail("Rate limit should be reported.")
            } catch {}
        }
        let finalCount = await transport.requests.count
        XCTAssertEqual(finalCount, 2)
    }

    func testCancelledFetchCannotOverwriteSavedCatalogue() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PremierLeagueRepository(cacheDirectory: directory, fetch: { _ in throw CancellationError() })
        do {
            _ = try await repository.refresh(force: true)
            XCTFail("Cancelled refresh should throw.")
        } catch is CancellationError {} catch { XCTFail("Expected cancellation, received \(error)") }
        let cached = await repository.cached()
        XCTAssertNil(cached)
    }

    private func player(_ id: String, role: String, rating: Double) -> ClubPlayer {
        ClubPlayer(id: id, name: id, position: role, rating: rating, appearance: .generated(for: id))
    }

    private func bundledData() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "PremierLeagueSnapshot", withExtension: "json")))
    }

    private func modifiedExport(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var export = try XCTUnwrap(JSONSerialization.jsonObject(with: bundledData()) as? [String: Any])
        mutate(&export)
        return try JSONSerialization.data(withJSONObject: export)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ReferenceTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor ReferenceTestTransport {
    struct Step: Sendable {
        var status: Int
        var data: Data
        var headers: [String: String] = [:]
    }
    var requests: [URLRequest] = []
    private var steps: [Step]
    init(steps: [Step]) { self.steps = steps }
    func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        let step = steps.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: step.headers)!
        return (step.data, response)
    }
}
