import Foundation

enum CareerError: LocalizedError, Equatable {
    case invalidSave, unsupportedVersion, noCareer, seasonComplete, seasonInProgress
    case invalidLineup, invalidScore, staleMatch, resultAlreadyRecorded, unreadableSave, saveTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidSave: "This career's saved data is incomplete or inconsistent. Your existing save has been kept."
        case .unsupportedVersion: "This career was saved by a different version of the game. Your existing save has been kept."
        case .noCareer: "Choose a club to start a career."
        case .seasonComplete: "This season is finished. Start the next season to play again."
        case .seasonInProgress: "Finish all 38 league matches before starting the next season."
        case .invalidLineup: "Choose eleven different players from your career squad, with one goalkeeper."
        case .invalidScore: "This match result could not be saved. Please try again."
        case .staleMatch: "This match no longer belongs to the next fixture in your career."
        case .resultAlreadyRecorded: "This fixture already has a saved result."
        case .unreadableSave: "Your career could not be opened. Its saved file has been kept."
        case .saveTooLarge: "This career is too large to save. Your existing progress has been kept."
        }
    }
}

struct CareerResult: Codable, Hashable, Sendable {
    var homeGoals: Int
    var awayGoals: Int
}

struct CareerFixture: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var round: Int
    var homeClubID: String
    var awayClubID: String
    var result: CareerResult?
}

struct CareerStanding: Codable, Hashable, Identifiable, Sendable {
    var clubID: String
    var clubName: String
    var played = 0
    var won = 0
    var drawn = 0
    var lost = 0
    var goalsFor = 0
    var goalsAgainst = 0
    var id: String { clubID }
    var goalDifference: Int { goalsFor - goalsAgainst }
    var points: Int { won * 3 + drawn }
}

struct CareerSeasonArchive: Codable, Hashable, Identifiable, Sendable {
    var seasonNumber: Int
    var fixtures: [CareerFixture]
    var standings: [CareerStanding]
    var finishedAt: Date
    var id: Int { seasonNumber }
}

struct CareerLineupSelection: Codable, Hashable, Sendable {
    var formation: MatchFormation
    var playerIDs: [String]
}

/// Configuration uses the controlled club as "home" because the arcade engine controls blue.
/// Fixture venue and the persisted result always retain the actual home and away clubs.
struct CareerMatchTicket: Identifiable, Hashable, Sendable {
    var id: String { fixture.id }
    var fixture: CareerFixture
    var configuration: FriendlyMatchConfiguration
    var userIsAway: Bool
}

/// An entire career is a value snapshot. Live catalogue refreshes never modify its clubs or players.
struct CareerSave: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1
    var schemaVersion: Int = Self.currentSchemaVersion
    var id: String
    var teams: [ClubTeam]
    var selectedClubID: String
    var snapshotID: String
    var startedAt: Date
    var seed: UInt64
    var seasonNumber: Int
    var fixtures: [CareerFixture]
    var lineupSelection: CareerLineupSelection
    var archives: [CareerSeasonArchive]

    // All decoded values are validated before publication by CareerStore.
    var selectedClub: ClubTeam { teams.first { $0.id == selectedClubID }! }
    var lineup: ClubLineup {
        let team = selectedClub
        let byID = Dictionary(uniqueKeysWithValues: team.players.map { ($0.id, $0) })
        return ClubLineup(team: team, formation: lineupSelection.formation,
                          players: lineupSelection.playerIDs.compactMap { byID[$0] })
    }
    var nextFixture: CareerFixture? {
        fixtures.first { $0.result == nil && ($0.homeClubID == selectedClubID || $0.awayClubID == selectedClubID) }
    }
    var currentRound: Int { nextFixture?.round ?? 38 }
    var completedRounds: Int { fixtures.filter { $0.result != nil }.count / 10 }
    var isSeasonComplete: Bool { fixtures.count == 380 && fixtures.allSatisfy { $0.result != nil } }
    var standings: [CareerStanding] { Self.table(teams: teams, fixtures: fixtures) }

    static func new(teams: [ClubTeam], clubID: String, snapshotID: String,
                    date: Date = Date(), seed: UInt64? = nil) throws -> Self {
        let frozen = teams.map { $0.withPlayableSquad() }
        guard let club = frozen.first(where: { $0.id == clubID }) else { throw CareerError.invalidSave }
        let lineup = ClubLineup.autoSelect(team: club)
        let careerID = UUID().uuidString
        let career = Self(id: careerID, teams: frozen, selectedClubID: clubID,
                          snapshotID: snapshotID, startedAt: date,
                          seed: seed ?? stableHash(careerID + snapshotID), seasonNumber: 1,
                          fixtures: schedule(teams: frozen, careerID: careerID, season: 1),
                          lineupSelection: .init(formation: lineup.formation, playerIDs: lineup.players.map(\.id)),
                          archives: [])
        try career.validate()
        return career
    }

    func prepareMatch() throws -> CareerMatchTicket {
        try validate()
        guard let fixture = nextFixture else { throw CareerError.seasonComplete }
        let opponentID = fixture.homeClubID == selectedClubID ? fixture.awayClubID : fixture.homeClubID
        guard let opponent = teams.first(where: { $0.id == opponentID }) else { throw CareerError.invalidSave }
        return CareerMatchTicket(fixture: fixture,
                                 configuration: .init(home: lineup, away: .autoSelect(team: opponent)),
                                 userIsAway: fixture.awayClubID == selectedClubID)
    }

    mutating func updateLineup(_ selection: ClubLineup) throws {
        // Compare full player values as well as IDs: live profiles must not leak into a frozen career.
        guard selection.team == selectedClub, selection.isValid,
              selection.players.allSatisfy({ selectedClub.players.contains($0) }) else { throw CareerError.invalidLineup }
        lineupSelection = .init(formation: selection.formation, playerIDs: selection.players.map(\.id))
    }

    /// Commits all ten games in a round together. Identical repeat callbacks are harmless.
    @discardableResult
    mutating func completeFixture(ticketID: String, userGoals: Int, opponentGoals: Int) throws -> Bool {
        guard (0...999).contains(userGoals), (0...999).contains(opponentGoals) else { throw CareerError.invalidScore }
        if let recorded = (fixtures + archives.flatMap(\.fixtures)).first(where: { $0.id == ticketID && $0.result != nil }) {
            guard recorded.homeClubID == selectedClubID || recorded.awayClubID == selectedClubID else { throw CareerError.staleMatch }
            let actual = Self.actualResult(fixture: recorded, selectedClubID: selectedClubID,
                                           userGoals: userGoals, opponentGoals: opponentGoals)
            guard actual == recorded.result else { throw CareerError.resultAlreadyRecorded }
            return false
        }
        guard let fixture = nextFixture, fixture.id == ticketID else { throw CareerError.staleMatch }
        var staged = self
        for index in staged.fixtures.indices where staged.fixtures[index].round == fixture.round {
            let game = staged.fixtures[index]
            if game.id == ticketID {
                staged.fixtures[index].result = Self.actualResult(fixture: game, selectedClubID: selectedClubID,
                                                                  userGoals: userGoals, opponentGoals: opponentGoals)
            } else {
                staged.fixtures[index].result = simulatedResult(for: game)
            }
        }
        try staged.validate()
        self = staged
        return true
    }

    mutating func startNextSeason(date: Date = Date()) throws {
        guard isSeasonComplete else { throw CareerError.seasonInProgress }
        var staged = self
        staged.archives.append(.init(seasonNumber: seasonNumber, fixtures: fixtures,
                                     standings: standings, finishedAt: date))
        staged.seasonNumber += 1
        staged.fixtures = Self.schedule(teams: teams, careerID: id, season: staged.seasonNumber)
        try staged.validate()
        self = staged
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw CareerError.unsupportedVersion }
        guard !id.isEmpty, !snapshotID.isEmpty, startedAt.timeIntervalSince1970.isFinite,
              teams.count == 20, Set(teams.map(\.id)).count == 20,
              teams.contains(where: { $0.id == selectedClubID }), seasonNumber >= 1,
              archives.count == seasonNumber - 1 else { throw CareerError.invalidSave }
        for team in teams {
            guard !team.id.isEmpty, !team.name.isEmpty, team.players.count >= 11,
                  Set(team.players.map(\.id)).count == team.players.count,
                  team.players.contains(where: { $0.role == "G" }),
                  team.players.filter({ $0.role != "G" }).count >= 10,
                  team.players.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.estimatedRating.isFinite && ($0.rating?.isFinite ?? true) }),
                  ClubLineup.autoSelect(team: team).isValid else { throw CareerError.invalidSave }
        }
        guard lineupSelection.playerIDs.count == 11, Set(lineupSelection.playerIDs).count == 11,
              lineupSelection.playerIDs.allSatisfy({ id in selectedClub.players.contains { $0.id == id } }),
              lineup.isValid else { throw CareerError.invalidLineup }
        try validateFixtures(fixtures, season: seasonNumber, requireComplete: false)
        for (index, archive) in archives.enumerated() {
            guard archive.seasonNumber == index + 1, archive.finishedAt.timeIntervalSince1970.isFinite else { throw CareerError.invalidSave }
            try validateFixtures(archive.fixtures, season: archive.seasonNumber, requireComplete: true)
            guard archive.standings == Self.table(teams: teams, fixtures: archive.fixtures) else { throw CareerError.invalidSave }
        }
    }

    private func validateFixtures(_ games: [CareerFixture], season: Int, requireComplete: Bool) throws {
        let expected = Self.schedule(teams: teams, careerID: id, season: season)
        guard games.count == 380, games.count == expected.count else { throw CareerError.invalidSave }
        var encounteredUnplayed = false
        // Recreating the schedule verifies IDs, every ordered club pairing and every round's membership.
        for (game, scheduled) in zip(games, expected) {
            guard game.id == scheduled.id, game.round == scheduled.round,
                  game.homeClubID == scheduled.homeClubID, game.awayClubID == scheduled.awayClubID else { throw CareerError.invalidSave }
            if let result = game.result {
                guard !encounteredUnplayed, (0...999).contains(result.homeGoals), (0...999).contains(result.awayGoals) else { throw CareerError.invalidSave }
            } else { encounteredUnplayed = true }
        }
        for round in 1...38 {
            let count = games.filter { $0.round == round && $0.result != nil }.count
            guard count == 0 || count == 10 else { throw CareerError.invalidSave }
        }
        guard !requireComplete || !encounteredUnplayed else { throw CareerError.invalidSave }
    }

    private static func actualResult(fixture: CareerFixture, selectedClubID: String,
                                     userGoals: Int, opponentGoals: Int) -> CareerResult {
        fixture.homeClubID == selectedClubID
            ? CareerResult(homeGoals: userGoals, awayGoals: opponentGoals)
            : CareerResult(homeGoals: opponentGoals, awayGoals: userGoals)
    }

    private func simulatedResult(for fixture: CareerFixture) -> CareerResult {
        func strength(_ id: String) -> Double {
            guard let team = teams.first(where: { $0.id == id }) else { return 78 }
            let players = ClubLineup.autoSelect(team: team).players
            return players.map { min(95, max(55, $0.effectiveRating)) }.reduce(0, +) / Double(players.count)
        }
        let quality = min(0.35, max(-0.35, (strength(fixture.homeClubID) - strength(fixture.awayClubID)) * 0.012))
        var random = CareerRandom(state: seed ^ Self.stableHash(fixture.id))
        // Modest quality and home advantages retain upset chances for every club.
        return CareerResult(homeGoals: random.goals(mean: 1.45 + quality),
                            awayGoals: random.goals(mean: 1.25 - quality))
    }

    private static func schedule(teams: [ClubTeam], careerID: String, season: Int) -> [CareerFixture] {
        guard teams.count == 20 else { return [] }
        var rotation = teams.map(\.id).sorted()
        var firstLeg: [CareerFixture] = []
        for round in 0..<19 {
            for pair in 0..<10 {
                let left = rotation[pair]
                let right = rotation[19 - pair]
                let leftHome = pair == 0 ? round.isMultiple(of: 2) : pair.isMultiple(of: 2)
                firstLeg.append(.init(id: "\(careerID):s\(season):r\(round + 1):m\(pair + 1)", round: round + 1,
                                      homeClubID: leftHome ? left : right,
                                      awayClubID: leftHome ? right : left))
            }
            rotation.insert(rotation.removeLast(), at: 1)
        }
        let secondLeg = firstLeg.enumerated().map { offset, game in
            CareerFixture(id: "\(careerID):s\(season):r\(game.round + 19):m\(offset % 10 + 1)",
                          round: game.round + 19, homeClubID: game.awayClubID, awayClubID: game.homeClubID)
        }
        return firstLeg + secondLeg
    }

    private static func table(teams: [ClubTeam], fixtures: [CareerFixture]) -> [CareerStanding] {
        var rows = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, CareerStanding(clubID: $0.id, clubName: $0.name)) })
        for fixture in fixtures {
            guard let result = fixture.result, var home = rows[fixture.homeClubID], var away = rows[fixture.awayClubID] else { continue }
            home.played += 1; away.played += 1
            home.goalsFor += result.homeGoals; home.goalsAgainst += result.awayGoals
            away.goalsFor += result.awayGoals; away.goalsAgainst += result.homeGoals
            if result.homeGoals > result.awayGoals { home.won += 1; away.lost += 1 }
            else if result.homeGoals < result.awayGoals { away.won += 1; home.lost += 1 }
            else { home.drawn += 1; away.drawn += 1 }
            rows[home.clubID] = home; rows[away.clubID] = away
        }
        return rows.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.goalDifference != $1.goalDifference { return $0.goalDifference > $1.goalDifference }
            if $0.goalsFor != $1.goalsFor { return $0.goalsFor > $1.goalsFor }
            if $0.clubName.lowercased() != $1.clubName.lowercased() { return $0.clubName.lowercased() < $1.clubName.lowercased() }
            return $0.clubID < $1.clubID
        }
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

private struct CareerRandom {
    var state: UInt64
    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / 9_007_199_254_740_992
    }
    mutating func goals(mean: Double) -> Int {
        let threshold = exp(-mean)
        var product = 1.0
        var count = 0
        repeat { product *= max(unit(), .leastNonzeroMagnitude); count += 1 } while product > threshold && count <= 8
        return min(8, count - 1)
    }
}
