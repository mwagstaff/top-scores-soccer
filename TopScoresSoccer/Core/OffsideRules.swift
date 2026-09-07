import Foundation

/// Arcade Law 11: sample body centres at a teammate's touch, then wait for involvement.
/// Level players have a small numerical tolerance; arms and sprite artwork never affect a call.
enum OffsideRules {
    struct Snapshot: Equatable, Sendable {
        let team: Team
        let candidates: Set<Int>
    }

    static func line(team: Team, ball: Vector2, roster: [Footballer], positions: [Vector2]? = nil) -> Double {
        let attack = team == .blue ? 1.0 : -1.0
        let defenders = roster.filter { $0.team != team && !$0.isSentOff }.map {
            let position = positions?.indices.contains($0.id) == true ? positions![$0.id] : $0.state.position
            return position.y * attack
        }.sorted(by: >)
        let secondLast = defenders.count >= 2 ? defenders[1] : -Pitch.length / 2
        return max(0, ball.y * attack, secondLast)
    }

    static func snapshot(actor: Int, ball: Vector2, roster: [Footballer],
                         positions: [Vector2]? = nil, restart: MatchRestartKind? = nil) -> Snapshot? {
        guard roster.indices.contains(actor), !roster[actor].isSentOff else { return nil }
        if restart == .throwIn || restart == .goalKick || restart == .corner { return nil }
        let team = roster[actor].team
        let attack = team == .blue ? 1.0 : -1.0
        let limit = line(team: team, ball: ball, roster: roster, positions: positions)
        let candidates = roster.filter {
            guard $0.id != actor, $0.team == team, !$0.isSentOff else { return false }
            let position = positions?.indices.contains($0.id) == true ? positions![$0.id] : $0.state.position
            return position.y * attack > limit + 0.05
        }.map(\.id)
        return Snapshot(team: team, candidates: Set(candidates))
    }
}
