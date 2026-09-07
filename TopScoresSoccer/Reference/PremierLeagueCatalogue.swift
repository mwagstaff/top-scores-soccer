import Foundation

struct PremierLeagueCatalogue: Sendable {
    var teams: [ClubTeam]
    var seasonName: String
    var snapshotID: String
    var publishedAt: String?
    var isStale: Bool

    static func bundled(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "PremierLeagueSnapshot", withExtension: "json") else {
            throw CatalogueError.missingBundle
        }
        return try decode(Data(contentsOf: url), appearanceOverrides: appearanceOverrides(bundle: bundle))
    }

    static func appearanceOverrides(bundle: Bundle = .main) -> [String: PlayerAppearance] {
        if let overridesURL = bundle.url(forResource: "PlayerAppearanceOverrides", withExtension: "json"),
           let data = try? Data(contentsOf: overridesURL),
           let decoded = try? JSONDecoder().decode([String: PlayerAppearance].self, from: data) {
            return decoded
        }
        return [:]
    }

    static func decode(_ data: Data, appearanceOverrides: [String: PlayerAppearance] = [:]) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let export = try decoder.decode(ReferenceExport.self, from: data)
        guard export.data.competition.id == "1",
              export.data.teams.count == 20,
              !export.meta.snapshotId.isEmpty,
              Set(export.data.teams.map(\.team.id)).count == export.data.teams.count else {
            throw CatalogueError.invalidSnapshot
        }
        let teams = try export.data.teams.map { entry -> ClubTeam in
            guard !entry.team.id.isEmpty, !entry.team.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.team.isPlaceholder != true, entry.squad.teamId == entry.team.id else {
                throw CatalogueError.invalidSnapshot
            }
            let knownRatings = entry.squad.players.compactMap(\.player.rating).filter { $0.isFinite }
            let average = knownRatings.isEmpty ? 72 : knownRatings.reduce(0, +) / Double(knownRatings.count)
            let estimate = min(82, max(65, average - 2))
            var seen = Set<String>()
            let players = try entry.squad.players.compactMap { member -> ClubPlayer? in
                let player = member.player
                guard !player.id.isEmpty, player.id == member.playerId,
                      !player.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      player.rating?.isFinite != false else { throw CatalogueError.invalidSnapshot }
                guard seen.insert(player.id).inserted else { return nil }
                return ClubPlayer(id: player.id, name: player.name, shortName: player.shortName,
                                  position: player.position, jerseyNumber: member.jerseyNumber,
                                  rating: player.rating, appearance: appearanceOverrides[player.id] ?? .generated(for: player.id),
                                  estimatedRating: estimate)
            }
            return ClubTeam(id: entry.team.id, name: entry.team.name, shortName: entry.team.shortName,
                            primaryHex: validHex(entry.team.colours?.primary) ?? "#215EA8",
                            secondaryHex: validHex(entry.team.colours?.secondary) ?? "#FFFFFF",
                            players: players).withPlayableSquad()
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return Self(teams: teams, seasonName: export.data.competition.currentSeason?.name ?? "Premier League",
                    snapshotID: export.meta.snapshotId, publishedAt: export.meta.updatedAt, isStale: export.meta.stale ?? false)
    }

    private static func validHex(_ value: String?) -> String? {
        guard let value, value.count == 7, value.first == "#",
              value.dropFirst().allSatisfy({ $0.isHexDigit }) else { return nil }
        return value.uppercased()
    }
}

enum CatalogueError: LocalizedError {
    case missingBundle, invalidSnapshot, invalidResponse, rateLimited, unavailable, http(Int)
    var errorDescription: String? {
        switch self {
        case .missingBundle: "The included Premier League data could not be found."
        case .invalidSnapshot: "The downloaded league data was incomplete."
        case .invalidResponse: "The data service returned an unexpected response."
        case .rateLimited: "The data service is busy. Please refresh again later."
        case .unavailable: "The data service is temporarily unavailable."
        case .http(let status): "The data service returned an error (\(status))."
        }
    }
}

private struct ReferenceExport: Decodable {
    let data: Payload
    let meta: Metadata
    struct Payload: Decodable { let competition: Competition; let teams: [Entry] }
    struct Competition: Decodable { let id: String; let currentSeason: Season? }
    struct Season: Decodable { let name: String }
    struct Metadata: Decodable { let snapshotId: String; let updatedAt: String?; let stale: Bool? }
    struct Entry: Decodable { let team: TeamRecord; let squad: Squad }
    struct TeamRecord: Decodable {
        let id: String
        let name: String
        let shortName: String?
        let isPlaceholder: Bool?
        let colours: Colours?
    }
    struct Colours: Decodable { let primary: String?; let secondary: String? }
    struct Squad: Decodable { let teamId: String; let players: [Member] }
    struct Member: Decodable { let playerId: String; let jerseyNumber: Int?; let player: Player }
    struct Player: Decodable {
        let id: String
        let name: String
        let shortName: String?
        let position: String?
        let rating: Double?
    }
}
