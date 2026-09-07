import Foundation

/// Sprite palette choices are cosmetic game data, never inferred ethnicity or player ability.
struct PlayerAppearance: Codable, Hashable, Sendable {
    var skinHex: String
    var hairHex: String
    var hairStyle: Int

    /// FNV-1a is deliberately stable between app launches (Swift's Hasher is not).
    static func generated(for playerID: String) -> Self {
        var seed: UInt64 = 14_695_981_039_346_656_037
        for byte in playerID.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        let skins = ["#F0C7A5", "#DCAA7D", "#C58C60", "#A76F46", "#805236", "#573928"]
        let hair = ["#201B19", "#493026", "#71513A", "#BC945B", "#A75330"]
        return Self(skinHex: skins[Int(seed % UInt64(skins.count))],
                    hairHex: hair[Int((seed >> 8) % UInt64(hair.count))],
                    hairStyle: Int((seed >> 16) % 4))
    }
}

struct ClubPlayer: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var shortName: String?
    var position: String?
    var jerseyNumber: Int?
    /// Unmodified source value. A missing value remains nil, and zero remains zero.
    var rating: Double?
    var isGenerated: Bool = false
    var appearance: PlayerAppearance
    var estimatedRating: Double = 70

    var effectiveRating: Double { rating ?? estimatedRating }
    var displayName: String { shortName ?? name }
    var isRatingEstimated: Bool { rating == nil }
    var role: String {
        switch position?.uppercased() {
        case "G", "GK", "GOALKEEPER": "G"
        case "D", "DEF", "CB", "LB", "RB", "LWB", "RWB": "D"
        case "F", "FW", "ST", "CF", "LW", "RW": "F"
        default: "M"
        }
    }
}

struct ClubTeam: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var shortName: String?
    var primaryHex: String
    var secondaryHex: String
    var players: [ClubPlayer]

    var displayName: String { shortName ?? name }
    var generatedPlayerCount: Int { players.filter(\.isGenerated).count }

    /// Only fills actual squad gaps; a non-specialist may play an outfield formation slot.
    func withPlayableSquad() -> Self {
        var result = self
        var seen = Set<String>()
        result.players = players.filter { seen.insert($0.id).inserted }
        let known = result.players.compactMap(\.rating).filter { $0.isFinite }
        let estimate = min(78, max(60, (known.isEmpty ? 74 : known.reduce(0, +) / Double(known.count)) - 4))
        func addStandIn(role: String, index: Int) {
            let playerID = "stand-in:\(id):\(role):\(index)"
            guard !result.players.contains(where: { $0.id == playerID }) else { return }
            let label = role == "G" ? "Goalkeeper" : "Player"
            result.players.append(ClubPlayer(id: playerID, name: "Stand-in \(label) \(index)",
                                             shortName: "Stand-in \(index)", position: role,
                                             jerseyNumber: nil, rating: nil, isGenerated: true,
                                             appearance: .generated(for: playerID), estimatedRating: estimate))
        }
        if !result.players.contains(where: { $0.role == "G" }) { addStandIn(role: "G", index: 1) }
        let roles = ["D", "D", "D", "D", "M", "M", "M", "M", "F", "F"]
        var index = 0
        while result.players.filter({ $0.role != "G" }).count < 10 {
            addStandIn(role: roles[index % roles.count], index: index + 2)
            index += 1
        }
        return result
    }
}

struct FormationSlot: Sendable {
    var role: String
    /// Metres from the centre spot; home attacks north (+y).
    var position: Vector2
}

enum MatchFormation: String, CaseIterable, Codable, Identifiable, Sendable {
    case fourFourTwo, fourThreeThree, fourTwoThreeOne
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fourFourTwo: "4–4–2"
        case .fourThreeThree: "4–3–3"
        case .fourTwoThreeOne: "4–2–3–1"
        }
    }

    var slots: [FormationSlot] {
        let goalkeeper = FormationSlot(role: "G", position: Vector2(x: 0, y: -46))
        let defenders = [-24.0, -8, 8, 24].map { FormationSlot(role: "D", position: Vector2(x: $0, y: -28)) }
        let outfield: [FormationSlot]
        switch self {
        case .fourFourTwo:
            outfield = [-23.0, -8, 8, 23].map { FormationSlot(role: "M", position: Vector2(x: $0, y: -10)) }
                + [-9.0, 9].map { FormationSlot(role: "F", position: Vector2(x: $0, y: 12)) }
        case .fourThreeThree:
            outfield = [-16.0, 0, 16].map { FormationSlot(role: "M", position: Vector2(x: $0, y: -12)) }
                + [-23.0, 0, 23].map { FormationSlot(role: "F", position: Vector2(x: $0, y: 12)) }
        case .fourTwoThreeOne:
            outfield = [-10.0, 10].map { FormationSlot(role: "M", position: Vector2(x: $0, y: -17)) }
                + [-22.0, 0, 22].map { FormationSlot(role: "M", position: Vector2(x: $0, y: 2)) }
                + [FormationSlot(role: "F", position: Vector2(x: 0, y: 17))]
        }
        return [goalkeeper] + defenders + outfield
    }
}

struct ClubLineup: Hashable, Sendable {
    var team: ClubTeam
    var formation: MatchFormation
    /// Player order matches formation.slots, with the goalkeeper first.
    var players: [ClubPlayer]

    var isValid: Bool {
        players.count == 11 && Set(players.map(\.id)).count == 11
            && players.first?.role == "G"
            && players.dropFirst().allSatisfy { $0.role != "G" }
            && players.allSatisfy { player in team.players.contains(where: { $0.id == player.id }) }
    }

    static func autoSelect(team: ClubTeam, formation: MatchFormation = .fourFourTwo) -> Self {
        let ready = team.withPlayableSquad()
        var remaining = ready.players.sorted {
            $0.effectiveRating == $1.effectiveRating ? $0.id < $1.id : $0.effectiveRating > $1.effectiveRating
        }
        var selected = Array<ClubPlayer?>(repeating: nil, count: formation.slots.count)
        // Fill specialists first so an earlier vacant slot cannot consume the only striker.
        for (slotIndex, slot) in formation.slots.enumerated() {
            if let index = remaining.firstIndex(where: { $0.role == slot.role }) {
                selected[slotIndex] = remaining.remove(at: index)
            }
        }
        for slotIndex in selected.indices where selected[slotIndex] == nil {
            if let index = remaining.firstIndex(where: { $0.role != "G" }) {
                selected[slotIndex] = remaining.remove(at: index)
            }
        }
        return Self(team: ready, formation: formation, players: selected.compactMap { $0 })
    }

    /// Swaps an existing starter, or replaces a starter with a squad member.
    func replacingPlayer(at slot: Int, with player: ClubPlayer) -> Self? {
        guard players.indices.contains(slot), let replacement = team.players.first(where: { $0.id == player.id }) else { return nil }
        var result = self
        if let existingSlot = players.firstIndex(where: { $0.id == replacement.id }) {
            result.players.swapAt(slot, existingSlot)
        } else {
            result.players[slot] = replacement
        }
        return result.isValid ? result : nil
    }
}

struct FriendlyMatchConfiguration: Hashable, Sendable {
    var home: ClubLineup
    var away: ClubLineup
    var isValid: Bool { home.team.id != away.team.id && home.isValid && away.isValid }
}
