import Foundation

enum PlayStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case defensive, normal, attacking
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var description: String {
        switch self {
        case .defensive: "Midfielders and forwards drop back more often to help defend."
        case .normal: "A balanced shape, with support in defence and attack."
        case .attacking: "Defenders and midfielders push forward more often to support attacks."
        }
    }

    func depthAdjustment(role: String, inPossession: Bool) -> Double {
        switch (self, role) {
        case (.defensive, "M"): inPossession ? -5 : -9
        case (.defensive, "F"): inPossession ? -7 : -13
        case (.attacking, "D"): inPossession ? 10 : 4
        case (.attacking, "M"): inPossession ? 8 : 3
        default: 0
        }
    }
}

extension ClubPlayer {
    /// Fixed 55–95 scale, matching the range used for arcade abilities.
    var stars: Double {
        let value = effectiveRating.isFinite ? effectiveRating : 70
        return (min(5, max(1, 1 + (value - 55) / 10)) * 2).rounded() / 2
    }
    var positionTitle: String {
        switch role { case "G": "GK"; case "D": "DEF"; case "F": "ST"; default: "MID" }
    }
}

extension ClubLineup {
    /// Choose the best role fit, retaining the present formation on ties.
    func balanced() -> Self {
        let choices = [formation] + MatchFormation.allCases.filter { $0 != formation }
        let best = choices.min { mismatchCount(for: $0) < mismatchCount(for: $1) } ?? formation
        return arranged(in: best)
    }

    private func mismatchCount(for shape: MatchFormation) -> Int {
        ["D", "M", "F"].reduce(0) { result, role in
            result + abs(players.filter { $0.role == role }.count - shape.slots.filter { $0.role == role }.count)
        }
    }

    /// Globally minimise role mismatches first, then movement from previous slots.
    /// At eleven players a bit-mask assignment is small, deterministic and predictable.
    func arranged(in shape: MatchFormation) -> Self {
        guard isValid else { return self }
        let size = 1 << players.count
        var costs = Array(repeating: Double.infinity, count: size)
        var previous = Array(repeating: -1, count: size)
        costs[0] = 0
        for mask in 0..<size where costs[mask].isFinite {
            let slot = mask.nonzeroBitCount
            guard slot < players.count else { continue }
            for index in players.indices where mask & (1 << index) == 0 {
                let player = players[index]
                guard (player.role == "G") == (shape.slots[slot].role == "G") else { continue }
                let mismatch = player.role == shape.slots[slot].role ? 0.0 : 10_000.0
                let movement = (formation.slots[index].position - shape.slots[slot].position).length
                let cost = costs[mask] + mismatch + movement
                let next = mask | (1 << index)
                if cost < costs[next] { costs[next] = cost; previous[next] = index }
            }
        }
        var mask = size - 1
        var ordered: [ClubPlayer] = []
        while mask != 0 {
            let index = previous[mask]
            guard index >= 0 else { return self }
            ordered.append(players[index]); mask ^= 1 << index
        }
        var result = self
        result.formation = shape
        result.players = ordered.reversed()
        return result
    }
}

struct PendingSubstitution: Equatable, Identifiable, Sendable {
    let outgoingID: String
    let incomingID: String
    var id: String { outgoingID }
}

/// Only pre-match choices are persisted. Match substitutions never write this selection.
struct SavedTeamSelection: Codable {
    var formation: MatchFormation
    var playerIDs: [String]
    var style: PlayStyle
    var automaticFormation: Bool

    init(_ lineup: ClubLineup) {
        formation = lineup.formation; playerIDs = lineup.players.map(\.id)
        style = lineup.style; automaticFormation = lineup.automaticFormation
    }

    func restored(for team: ClubTeam) -> ClubLineup? {
        let ready = team.withPlayableSquad()
        let players = playerIDs.compactMap { id in ready.players.first { $0.id == id } }
        let lineup = ClubLineup(team: ready, formation: formation, players: players,
                               style: style, automaticFormation: automaticFormation)
        return lineup.isValid ? lineup : nil
    }
}
