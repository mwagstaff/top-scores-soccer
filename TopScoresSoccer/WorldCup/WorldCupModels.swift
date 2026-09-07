import Foundation

enum WorldCupError: LocalizedError, Equatable {
    case invalidSave, unsupportedVersion, noTournament, tournamentComplete, teamEliminated
    case invalidLineup, invalidResult, staleMatch, resultAlreadyRecorded, unreadableSave, saveTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidSave: "This World Cup save is incomplete or inconsistent. Your existing save has been kept."
        case .unsupportedVersion: "This World Cup was saved by a different version of the game. Your existing save has been kept."
        case .noTournament: "Choose a national team to start a World Cup."
        case .tournamentComplete: "This World Cup is complete."
        case .teamEliminated: "Your team has been eliminated. You can finish the tournament or start again."
        case .invalidLineup: "Choose eleven different players from your national squad, with one goalkeeper."
        case .invalidResult: "This match result could not be saved. Please try again."
        case .staleMatch: "This match is no longer your next World Cup fixture."
        case .resultAlreadyRecorded: "This fixture already has a different saved result."
        case .unreadableSave: "Your World Cup could not be opened. Its saved file has been kept."
        case .saveTooLarge: "This World Cup is too large to save. Your existing progress has been kept."
        }
    }
}

enum WorldCupStage: String, Codable, CaseIterable, Hashable, Sendable {
    case group, roundOf32, roundOf16, quarterfinal, semifinal, thirdPlace, final

    var title: String {
        switch self {
        case .group: "Group stage"
        case .roundOf32: "Round of 32"
        case .roundOf16: "Round of 16"
        case .quarterfinal: "Quarter-final"
        case .semifinal: "Semi-final"
        case .thirdPlace: "Third-place match"
        case .final: "Final"
        }
    }

    var order: Int {
        switch self {
        case .group: 0
        case .roundOf32: 1
        case .roundOf16: 2
        case .quarterfinal: 3
        case .semifinal: 4
        case .thirdPlace: 5
        case .final: 6
        }
    }

    var isKnockout: Bool { self != .group }
}

struct WorldCupResult: Codable, Hashable, Sendable {
    var homeGoals: Int
    var awayGoals: Int
    var wentToExtraTime = false
    var homePenalties: Int?
    var awayPenalties: Int?
    var homeForfeited = false
    var awayForfeited = false

    var winnerIDSide: Int? {
        if homeGoals != awayGoals { return homeGoals > awayGoals ? 0 : 1 }
        guard let homePenalties, let awayPenalties, homePenalties != awayPenalties else { return nil }
        return homePenalties > awayPenalties ? 0 : 1
    }

    var suffix: String {
        if homePenalties != nil { return "PENS" }
        if wentToExtraTime { return "AET" }
        return ""
    }
}

struct WorldCupFixture: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var matchNumber: Int
    var stage: WorldCupStage
    var matchday: Int?
    var group: String?
    var homeTeamID: String
    var awayTeamID: String
    var result: WorldCupResult?
}

struct WorldCupStanding: Hashable, Identifiable, Sendable {
    let teamID: String
    let teamName: String
    var played = 0
    var won = 0
    var drawn = 0
    var lost = 0
    var goalsFor = 0
    var goalsAgainst = 0
    var id: String { teamID }
    var goalDifference: Int { goalsFor - goalsAgainst }
    var points: Int { won * 3 + drawn }
}

struct WorldCupLineupSelection: Codable, Hashable, Sendable {
    var formation: MatchFormation
    var playerIDs: [String]
}

struct WorldCupUserMatchOutcome: Equatable, Sendable {
    var regulationUserGoals: Int
    var regulationOpponentGoals: Int
    var userGoals: Int
    var opponentGoals: Int
    var wentToExtraTime: Bool
    var userPenalties: Int?
    var opponentPenalties: Int?
    var userForfeited = false
    var opponentForfeited = false
}

struct WorldCupMatchTicket: Identifiable, Hashable, Sendable {
    var id: String { fixture.id }
    let fixture: WorldCupFixture
    let configuration: FriendlyMatchConfiguration
    let userIsAway: Bool
    let seed: UInt64
}

struct WorldCupSave: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1
    static let currentRulesVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var rulesVersion = Self.currentRulesVersion
    var id: String
    var snapshotID: String
    var startedAt: Date
    var seed: UInt64
    var teams: [ClubTeam]
    var groups: [[String]]
    var selectedTeamID: String
    var lineupSelection: WorldCupLineupSelection
    var fixtures: [WorldCupFixture]
    var championTeamID: String?
    var celebrationPending = false
    var celebrationAcknowledged = false

    var selectedTeam: ClubTeam { teams.first { $0.id == selectedTeamID }! }
    var lineup: ClubLineup {
        let byID = Dictionary(uniqueKeysWithValues: selectedTeam.players.map { ($0.id, $0) })
        return ClubLineup(team: selectedTeam, formation: lineupSelection.formation,
                          players: lineupSelection.playerIDs.compactMap { byID[$0] })
    }
    var selectedGroupIndex: Int { groups.firstIndex { $0.contains(selectedTeamID) }! }
    var selectedGroupName: String { Self.groupName(selectedGroupIndex) }
    var groupStageComplete: Bool { fixtures.filter { $0.stage == .group }.allSatisfy { $0.result != nil } }
    var tournamentComplete: Bool { fixtures.first { $0.stage == .final }?.result != nil }
    var userIsChampion: Bool { championTeamID == selectedTeamID }

    var nextFixture: WorldCupFixture? {
        fixtures.filter { $0.result == nil && ($0.homeTeamID == selectedTeamID || $0.awayTeamID == selectedTeamID) }
            .sorted(by: Self.fixtureOrder).first
    }

    var selectedTeamEliminated: Bool {
        guard nextFixture == nil, !userIsChampion else { return false }
        if !groupStageComplete { return false }
        if fixtures.contains(where: { $0.stage == .thirdPlace && ($0.homeTeamID == selectedTeamID || $0.awayTeamID == selectedTeamID) && $0.result != nil }) { return true }
        guard let last = fixtures.filter({ ($0.homeTeamID == selectedTeamID || $0.awayTeamID == selectedTeamID) && $0.result != nil })
            .max(by: { Self.fixtureOrder($0, $1) }) else { return false }
        return winner(of: last) != selectedTeamID
    }

    var currentStage: WorldCupStage {
        if let nextFixture { return nextFixture.stage }
        if tournamentComplete { return .final }
        if !groupStageComplete { return .group }
        return fixtures.map(\.stage).max(by: { $0.order < $1.order }) ?? .group
    }

    var currentGroupMatchday: Int {
        nextFixture?.matchday ?? min(3, (fixtures.filter { $0.stage == .group && $0.result != nil }.count / 24) + 1)
    }

    static func new(snapshot: NationalTeamSnapshot = NationalTeamCatalogue.snapshot(), selectedTeamID: String,
                    date: Date = Date(), seed: UInt64? = nil) throws -> Self {
        let frozen = snapshot.teams.map { $0.withPlayableSquad() }
        guard frozen.count == 48, snapshot.groups.count == 12,
              frozen.contains(where: { $0.id == selectedTeamID }) else { throw WorldCupError.invalidSave }
        let tournamentID = UUID().uuidString
        let tournamentSeed = seed ?? stableHash(tournamentID + snapshot.id)
        let team = frozen.first { $0.id == selectedTeamID }!
        let lineup = ClubLineup.autoSelect(team: team)
        let save = Self(id: tournamentID, snapshotID: snapshot.id, startedAt: date, seed: tournamentSeed,
                        teams: frozen, groups: snapshot.groups, selectedTeamID: selectedTeamID,
                        lineupSelection: .init(formation: lineup.formation, playerIDs: lineup.players.map(\.id)),
                        fixtures: groupFixtures(groups: snapshot.groups, tournamentID: tournamentID))
        try save.validate()
        return save
    }

    func prepareMatch() throws -> WorldCupMatchTicket {
        try validate()
        guard !tournamentComplete else { throw WorldCupError.tournamentComplete }
        guard let fixture = nextFixture else { throw WorldCupError.teamEliminated }
        let opponentID = fixture.homeTeamID == selectedTeamID ? fixture.awayTeamID : fixture.homeTeamID
        guard let opponent = teams.first(where: { $0.id == opponentID }) else { throw WorldCupError.invalidSave }
        return WorldCupMatchTicket(fixture: fixture,
            configuration: .init(home: lineup, away: .autoSelect(team: opponent)),
            userIsAway: fixture.awayTeamID == selectedTeamID,
            seed: seed ^ Self.stableHash(fixture.id))
    }

    mutating func updateLineup(_ selection: ClubLineup) throws {
        guard selection.team == selectedTeam, selection.isValid,
              selection.players.allSatisfy({ selectedTeam.players.contains($0) }) else { throw WorldCupError.invalidLineup }
        lineupSelection = .init(formation: selection.formation, playerIDs: selection.players.map(\.id))
    }

    @discardableResult
    mutating func completeFixture(ticketID: String, outcome: WorldCupUserMatchOutcome) throws -> Bool {
        guard (0...999).contains(outcome.userGoals), (0...999).contains(outcome.opponentGoals),
              (0...999).contains(outcome.regulationUserGoals), (0...999).contains(outcome.regulationOpponentGoals) else {
            throw WorldCupError.invalidResult
        }
        if let existing = fixtures.first(where: { $0.id == ticketID && $0.result != nil }) {
            let expected = actualResult(fixture: existing, outcome: outcome)
            guard existing.result == expected else { throw WorldCupError.resultAlreadyRecorded }
            return false
        }
        guard let fixture = nextFixture, fixture.id == ticketID,
              let fixtureIndex = fixtures.firstIndex(where: { $0.id == ticketID }) else { throw WorldCupError.staleMatch }
        let actual = actualResult(fixture: fixture, outcome: outcome)
        guard fixture.stage == .group || actual.winnerIDSide != nil else { throw WorldCupError.invalidResult }

        var staged = self
        staged.fixtures[fixtureIndex].result = actual
        if fixture.stage == .group {
            try staged.finishGroupMatchday(fixture.matchday ?? 0)
            if staged.groupStageComplete { try staged.createRoundOf32() }
        } else if fixture.stage == .final || fixture.stage == .thirdPlace {
            try staged.finishFinalWeekend()
        } else {
            try staged.finishKnockoutStage(fixture.stage)
        }
        staged.refreshChampionAndCelebration()
        try staged.validate()
        self = staged
        return true
    }

    mutating func finishTournament() throws {
        var staged = self
        while !staged.tournamentComplete {
            guard let stage = staged.fixtures.filter({ $0.stage != .group && $0.result == nil })
                .map(\.stage).min(by: { $0.order < $1.order }) else { throw WorldCupError.invalidSave }
            if stage == .final || stage == .thirdPlace { try staged.finishFinalWeekend() }
            else { try staged.finishKnockoutStage(stage) }
        }
        staged.refreshChampionAndCelebration()
        try staged.validate()
        self = staged
    }

    mutating func acknowledgeCelebration() {
        celebrationPending = false
        celebrationAcknowledged = true
    }

    func standings(forGroup index: Int) -> [WorldCupStanding] {
        guard groups.indices.contains(index) else { return [] }
        let ids = groups[index]
        var rows = Dictionary(uniqueKeysWithValues: ids.map { id in
            let name = teams.first { $0.id == id }?.name ?? id.uppercased()
            return (id, WorldCupStanding(teamID: id, teamName: name))
        })
        let games = fixtures.filter { $0.group == Self.groupName(index) }
        for game in games {
            guard let result = game.result, var home = rows[game.homeTeamID], var away = rows[game.awayTeamID] else { continue }
            home.played += 1; away.played += 1
            home.goalsFor += result.homeGoals; home.goalsAgainst += result.awayGoals
            away.goalsFor += result.awayGoals; away.goalsAgainst += result.homeGoals
            if result.homeGoals > result.awayGoals { home.won += 1; away.lost += 1 }
            else if result.homeGoals < result.awayGoals { away.won += 1; home.lost += 1 }
            else { home.drawn += 1; away.drawn += 1 }
            rows[home.teamID] = home; rows[away.teamID] = away
        }
        return rows.values.sorted { compareStandings($0, $1) }
    }

    func winner(of fixture: WorldCupFixture) -> String? {
        guard let side = fixture.result?.winnerIDSide else { return nil }
        return side == 0 ? fixture.homeTeamID : fixture.awayTeamID
    }

    func loser(of fixture: WorldCupFixture) -> String? {
        guard let winner = winner(of: fixture) else { return nil }
        return winner == fixture.homeTeamID ? fixture.awayTeamID : fixture.homeTeamID
    }

    func teamName(_ id: String) -> String { teams.first { $0.id == id }?.name ?? "Unknown team" }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion, rulesVersion == Self.currentRulesVersion else { throw WorldCupError.unsupportedVersion }
        let teamIDs = teams.map(\.id)
        guard !id.isEmpty, !snapshotID.isEmpty, startedAt.timeIntervalSince1970.isFinite,
              teams.count == 48, Set(teamIDs).count == 48, groups.count == 12,
              groups.allSatisfy({ $0.count == 4 && Set($0).count == 4 }),
              Set(groups.flatMap { $0 }) == Set(teamIDs), teams.contains(where: { $0.id == selectedTeamID }) else {
            throw WorldCupError.invalidSave
        }
        guard teams.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && ClubLineup.autoSelect(team: $0).isValid }) else {
            throw WorldCupError.invalidSave
        }
        guard lineup.isValid, lineup.team == selectedTeam else { throw WorldCupError.invalidLineup }
        let groupGames = fixtures.filter { $0.stage == .group }
        let expected = Self.groupFixtures(groups: groups, tournamentID: id)
        guard groupGames.count == 72, zip(groupGames, expected).allSatisfy({ left, right in
            left.id == right.id && left.matchNumber == right.matchNumber && left.matchday == right.matchday
                && left.group == right.group && left.homeTeamID == right.homeTeamID && left.awayTeamID == right.awayTeamID
        }), Set(fixtures.map(\.id)).count == fixtures.count else { throw WorldCupError.invalidSave }
        for fixture in fixtures {
            guard teamIDs.contains(fixture.homeTeamID), teamIDs.contains(fixture.awayTeamID),
                  fixture.homeTeamID != fixture.awayTeamID else { throw WorldCupError.invalidSave }
            if let result = fixture.result {
                guard (0...999).contains(result.homeGoals), (0...999).contains(result.awayGoals),
                      fixture.stage == .group || result.winnerIDSide != nil else { throw WorldCupError.invalidResult }
            }
        }
        for matchday in 1...3 {
            let completed = groupGames.filter { $0.matchday == matchday && $0.result != nil }.count
            guard completed == 0 || completed == 24 else { throw WorldCupError.invalidSave }
        }
        if let championTeamID {
            guard teamIDs.contains(championTeamID), let final = fixtures.first(where: { $0.stage == .final }),
                  final.result != nil, winner(of: final) == championTeamID else { throw WorldCupError.invalidSave }
        }
        guard !celebrationPending || championTeamID == selectedTeamID else { throw WorldCupError.invalidSave }
    }

    private mutating func finishGroupMatchday(_ matchday: Int) throws {
        guard (1...3).contains(matchday) else { throw WorldCupError.invalidSave }
        for index in fixtures.indices where fixtures[index].stage == .group && fixtures[index].matchday == matchday
            && fixtures[index].result == nil {
            fixtures[index].result = simulatedResult(for: fixtures[index], knockout: false)
        }
    }

    private mutating func createRoundOf32() throws {
        guard !fixtures.contains(where: { $0.stage == .roundOf32 }) else { return }
        let ranked = Dictionary(uniqueKeysWithValues: groups.indices.map { (Self.groupName($0), standings(forGroup: $0)) })
        let thirds = ranked.values.compactMap { $0.count >= 3 ? $0[2] : nil }.sorted(by: compareStandings).prefix(8)
        let thirdByGroup = Dictionary(uniqueKeysWithValues: thirds.compactMap { row in
            groups.firstIndex(where: { $0.contains(row.teamID) }).map { (Self.groupName($0), row.teamID) }
        })
        guard thirdByGroup.count == 8 else { throw WorldCupError.invalidSave }
        let thirdSlots: [(Int, String, Set<String>)] = [
            (74, "E", Set(["A", "B", "C", "D", "F"])), (77, "I", Set(["C", "D", "F", "G", "H"])),
            (79, "A", Set(["C", "E", "F", "H", "I"])), (80, "L", Set(["E", "H", "I", "J", "K"])),
            (81, "D", Set(["B", "E", "F", "I", "J"])), (82, "G", Set(["A", "E", "H", "I", "J"])),
            (85, "B", Set(["E", "F", "G", "I", "J"])), (87, "K", Set(["D", "E", "I", "J", "L"])),
        ]
        guard let assignment = Self.assignThirds(slots: thirdSlots, available: Set(thirdByGroup.keys)) else {
            throw WorldCupError.invalidSave
        }
        func rank(_ group: String, _ position: Int) throws -> String {
            guard let id = ranked[group]?[safe: position - 1]?.teamID else { throw WorldCupError.invalidSave }
            return id
        }
        func third(_ match: Int) throws -> String {
            guard let group = assignment[match], let id = thirdByGroup[group] else { throw WorldCupError.invalidSave }
            return id
        }
        let pairings: [(Int, String, String)] = [
            (73, try rank("A", 2), try rank("B", 2)), (74, try rank("E", 1), try third(74)),
            (75, try rank("F", 1), try rank("C", 2)), (76, try rank("C", 1), try rank("F", 2)),
            (77, try rank("I", 1), try third(77)), (78, try rank("E", 2), try rank("I", 2)),
            (79, try rank("A", 1), try third(79)), (80, try rank("L", 1), try third(80)),
            (81, try rank("D", 1), try third(81)), (82, try rank("G", 1), try third(82)),
            (83, try rank("K", 2), try rank("L", 2)), (84, try rank("H", 1), try rank("J", 2)),
            (85, try rank("B", 1), try third(85)), (86, try rank("J", 1), try rank("H", 2)),
            (87, try rank("K", 1), try third(87)), (88, try rank("D", 2), try rank("G", 2)),
        ]
        fixtures += pairings.map { fixture(number: $0.0, stage: .roundOf32, home: $0.1, away: $0.2) }
    }

    private mutating func finishKnockoutStage(_ stage: WorldCupStage) throws {
        for index in fixtures.indices where fixtures[index].stage == stage && fixtures[index].result == nil {
            fixtures[index].result = simulatedResult(for: fixtures[index], knockout: true)
        }
        switch stage {
        case .roundOf32:
            try appendStage(.roundOf16, numbers: Array(89...96), parents: [(74,77),(73,75),(76,78),(79,80),(83,84),(81,82),(86,88),(85,87)])
        case .roundOf16:
            try appendStage(.quarterfinal, numbers: Array(97...100), parents: [(89,90),(93,94),(91,92),(95,96)])
        case .quarterfinal:
            try appendStage(.semifinal, numbers: [101,102], parents: [(97,98),(99,100)])
        case .semifinal:
            guard !fixtures.contains(where: { $0.stage == .final }) else { return }
            let first = try fixtureWithNumber(101), second = try fixtureWithNumber(102)
            guard let firstWinner = winner(of: first), let secondWinner = winner(of: second),
                  let firstLoser = loser(of: first), let secondLoser = loser(of: second) else { throw WorldCupError.invalidSave }
            fixtures.append(fixture(number: 103, stage: .thirdPlace, home: firstLoser, away: secondLoser))
            fixtures.append(fixture(number: 104, stage: .final, home: firstWinner, away: secondWinner))
        default: throw WorldCupError.invalidSave
        }
    }

    private mutating func finishFinalWeekend() throws {
        for index in fixtures.indices where (fixtures[index].stage == .thirdPlace || fixtures[index].stage == .final)
            && fixtures[index].result == nil {
            fixtures[index].result = simulatedResult(for: fixtures[index], knockout: true)
        }
    }

    private mutating func appendStage(_ stage: WorldCupStage, numbers: [Int], parents: [(Int, Int)]) throws {
        guard !fixtures.contains(where: { $0.stage == stage }), numbers.count == parents.count else { return }
        for (number, parent) in zip(numbers, parents) {
            let first = try fixtureWithNumber(parent.0), second = try fixtureWithNumber(parent.1)
            guard let home = winner(of: first), let away = winner(of: second) else { throw WorldCupError.invalidSave }
            fixtures.append(fixture(number: number, stage: stage, home: home, away: away))
        }
    }

    private mutating func refreshChampionAndCelebration() {
        guard let final = fixtures.first(where: { $0.stage == .final }), let champion = winner(of: final) else { return }
        championTeamID = champion
        if champion == selectedTeamID, !celebrationAcknowledged { celebrationPending = true }
    }

    private func actualResult(fixture: WorldCupFixture, outcome: WorldCupUserMatchOutcome) -> WorldCupResult {
        let userHome = fixture.homeTeamID == selectedTeamID
        return WorldCupResult(homeGoals: userHome ? outcome.userGoals : outcome.opponentGoals,
                              awayGoals: userHome ? outcome.opponentGoals : outcome.userGoals,
                              wentToExtraTime: outcome.wentToExtraTime,
                              homePenalties: userHome ? outcome.userPenalties : outcome.opponentPenalties,
                              awayPenalties: userHome ? outcome.opponentPenalties : outcome.userPenalties,
                              homeForfeited: userHome ? outcome.userForfeited : outcome.opponentForfeited,
                              awayForfeited: userHome ? outcome.opponentForfeited : outcome.userForfeited)
    }

    private func simulatedResult(for fixture: WorldCupFixture, knockout: Bool) -> WorldCupResult {
        let homeStrength = strength(fixture.homeTeamID), awayStrength = strength(fixture.awayTeamID)
        return WorldCupResultSimulator.result(homeStrength: homeStrength, awayStrength: awayStrength,
                                              knockout: knockout,
                                              seed: seed ^ Self.stableHash(fixture.id))
    }

    private func strength(_ teamID: String) -> Double {
        guard let team = teams.first(where: { $0.id == teamID }) else { return 74 }
        let players = ClubLineup.autoSelect(team: team).players
        return players.map(\.effectiveRating).reduce(0, +) / Double(players.count)
    }

    private func compareStandings(_ lhs: WorldCupStanding, _ rhs: WorldCupStanding) -> Bool {
        if lhs.points != rhs.points { return lhs.points > rhs.points }
        if lhs.goalDifference != rhs.goalDifference { return lhs.goalDifference > rhs.goalDifference }
        if lhs.goalsFor != rhs.goalsFor { return lhs.goalsFor > rhs.goalsFor }
        return (seed ^ Self.stableHash(lhs.teamID)) < (seed ^ Self.stableHash(rhs.teamID))
    }

    private static func assignThirds(slots: [(Int, String, Set<String>)], available: Set<String>,
                                     index: Int = 0, result: [Int: String] = [:]) -> [Int: String]? {
        guard index < slots.count else { return available.isEmpty ? result : nil }
        let slot = slots[index]
        for group in available.intersection(slot.2).sorted() {
            var next = result; next[slot.0] = group
            if let solved = assignThirds(slots: slots, available: available.subtracting([group]), index: index + 1, result: next) {
                return solved
            }
        }
        return nil
    }

    private static func groupFixtures(groups: [[String]], tournamentID: String) -> [WorldCupFixture] {
        let pairings = [[(0,1),(2,3)], [(0,2),(3,1)], [(3,0),(1,2)]]
        var fixtures: [WorldCupFixture] = []
        var number = 1
        for matchday in 1...3 {
            for (groupIndex, teams) in groups.enumerated() where teams.count == 4 {
                for pairing in pairings[matchday - 1] {
                    fixtures.append(WorldCupFixture(id: "\(tournamentID):m\(number)", matchNumber: number,
                        stage: .group, matchday: matchday, group: groupName(groupIndex),
                        homeTeamID: teams[pairing.0], awayTeamID: teams[pairing.1]))
                    number += 1
                }
            }
        }
        return fixtures
    }

    private func fixture(number: Int, stage: WorldCupStage, home: String, away: String) -> WorldCupFixture {
        WorldCupFixture(id: "\(id):m\(number)", matchNumber: number, stage: stage,
                        homeTeamID: home, awayTeamID: away)
    }

    private func fixtureWithNumber(_ number: Int) throws -> WorldCupFixture {
        guard let fixture = fixtures.first(where: { $0.matchNumber == number }) else { throw WorldCupError.invalidSave }
        return fixture
    }

    private static func fixtureOrder(_ lhs: WorldCupFixture, _ rhs: WorldCupFixture) -> Bool {
        lhs.matchNumber < rhs.matchNumber
    }

    private static func groupName(_ index: Int) -> String {
        String(UnicodeScalar(65 + index)!)
    }

    static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

enum WorldCupResultSimulator {
    static func result(homeStrength: Double, awayStrength: Double, knockout: Bool,
                       seed: UInt64) -> WorldCupResult {
        var random = WorldCupRandom(state: seed)
        // The catalogue's 70–90 scale is converted to an Elo-shaped expectation. A bounded
        // match-day swing leaves room for form and genuine upsets without erasing team quality.
        let formSwing = (random.unit() - random.unit()) * 5.0
        let difference = min(24, max(-24, homeStrength - awayStrength + formSwing))
        let expectation = 1 / (1 + pow(10, -difference / 20))
        let totalMean = 2.45 + (random.unit() - 0.5) * 0.30
        let homeMean = 0.28 + expectation * (totalMean - 0.56)
        let awayMean = 0.28 + (1 - expectation) * (totalMean - 0.56)
        let home = random.goals(mean: homeMean)
        let away = random.goals(mean: awayMean)
        guard knockout, home == away else { return WorldCupResult(homeGoals: home, awayGoals: away) }

        let extraHome = random.goals(mean: max(0.16, homeMean / 3))
        let extraAway = random.goals(mean: max(0.16, awayMean / 3))
        if extraHome != extraAway {
            return WorldCupResult(homeGoals: home + extraHome, awayGoals: away + extraAway,
                                  wentToExtraTime: true)
        }
        let penalties = shootout(homeStrength: homeStrength, awayStrength: awayStrength, random: &random)
        return WorldCupResult(homeGoals: home + extraHome, awayGoals: away + extraAway,
                              wentToExtraTime: true, homePenalties: penalties.home,
                              awayPenalties: penalties.away)
    }

    private static func shootout(homeStrength: Double, awayStrength: Double,
                                 random: inout WorldCupRandom) -> (home: Int, away: Int) {
        let difference = min(12, max(-12, homeStrength - awayStrength))
        let homeChance = min(0.82, max(0.68, 0.75 + difference * 0.0025))
        let awayChance = min(0.82, max(0.68, 0.75 - difference * 0.0025))
        var home = 0, away = 0
        for kick in 0..<5 {
            if random.unit() < homeChance { home += 1 }
            if home > away + (5 - kick) { return (home, away) }
            if random.unit() < awayChance { away += 1 }
            if away > home + (4 - kick) { return (home, away) }
        }
        var suddenDeathPairs = 0
        while home == away && suddenDeathPairs < 12 {
            if random.unit() < homeChance { home += 1 }
            if random.unit() < awayChance { away += 1 }
            suddenDeathPairs += 1
        }
        if home == away {
            if random.unit() < 0.5 { home += 1 } else { away += 1 }
        }
        return (home, away)
    }
}

private struct WorldCupRandom {
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
        var product = 1.0, count = 0
        repeat { product *= max(unit(), .leastNonzeroMagnitude); count += 1 } while product > threshold && count <= 8
        return min(7, count - 1)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
