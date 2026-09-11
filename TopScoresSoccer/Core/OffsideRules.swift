import Foundation

/// Arcade Law 11: sample body centres at a teammate's touch, then wait for involvement.
/// Level players have a small numerical tolerance; arms and sprite artwork never affect a call.
enum OffsideRules {
    struct Snapshot: Equatable, Sendable {
        let team: Team
        let candidates: Set<Int>
    }

    static func line(team: Team, ball: Vector2, roster: [Footballer], positions: [Vector2]? = nil, ends: MatchEnds = MatchEnds()) -> Double {
        let attack = ends.attackSign(for: team)
        let defenders = roster.filter { $0.team != team && !$0.isUnavailable }.map {
            let position = positions?.indices.contains($0.id) == true ? positions![$0.id] : $0.state.position
            return position.y * attack
        }.sorted(by: >)
        let secondLast = defenders.count >= 2 ? defenders[1] : -Pitch.length / 2
        return max(0, ball.y * attack, secondLast)
    }

    static func snapshot(actor: Int, ball: Vector2, roster: [Footballer],
                         positions: [Vector2]? = nil, restart: MatchRestartKind? = nil, ends: MatchEnds = MatchEnds()) -> Snapshot? {
        guard roster.indices.contains(actor), !roster[actor].isUnavailable else { return nil }
        if restart == .throwIn || restart == .goalKick || restart == .corner { return nil }
        let team = roster[actor].team
        let attack = ends.attackSign(for: team)
        let limit = line(team: team, ball: ball, roster: roster, positions: positions, ends: ends)
        let candidates = roster.filter {
            guard $0.id != actor, $0.team == team, !$0.isUnavailable else { return false }
            let position = positions?.indices.contains($0.id) == true ? positions![$0.id] : $0.state.position
            return position.y * attack > limit + 0.05
        }.map(\.id)
        return Snapshot(team: team, candidates: Set(candidates))
    }
}
