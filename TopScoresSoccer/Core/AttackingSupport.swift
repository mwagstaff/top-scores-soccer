import Foundation

/// A single snapshot of attacking movement, shared by all teammates during a simulation tick.
/// Targets request ordinary running; they never move players or grant a pass/offside exemption.
enum AttackingSupport {
    struct ReleasedPass: Sendable {
        let receiverID: Int
        let destination: Vector2
    }

    struct Configuration: Sendable {
        var runnerCount = 2
        var overlappingDefenderID: Int?
        var shortDistance = 10.0
        var runDistance = 15.0
        var onsideMargin = 1.2
        var teammateSpacing = 5.0
        var opponentClearance = 6.0
        var laneClearance = 3.2
        var pitchInset = 4.0
        static let defaults = Configuration()
    }

    /// `carrierID` is the current carrier, or the passer while `releasedPass` is travelling.
    /// `offsideLine`, when supplied, is progress in the team's attacking direction, as returned
    /// by OffsideRules.line. Only an already released pass lets its receiver cross that line.
    static func targets(roster: [Footballer], team: Team, carrierID: Int?, ball: BallState,
                        baseTargets: [Int: Vector2], releasedPass: ReleasedPass? = nil,
                        offsideLine: Double? = nil,
                        configuration: Configuration = .defaults, ends: MatchEnds = MatchEnds()) -> [Int: Vector2] {
        let attack = ends.attackSign(for: team)
        func local(_ point: Vector2) -> Vector2 { point * attack }
        func eligible(_ player: Footballer) -> Bool {
            player.team == team && !player.isGoalkeeper && !player.isUnavailable
                && !player.isTackling && !player.isSliding
                && player.fallProgress <= 0.001 && player.recoveryProgress <= 0.001
        }
        let teammates = roster.filter(eligible).sorted { $0.id < $1.id }
        guard !teammates.isEmpty else { return [:] }
        let opponents = roster.filter { $0.team != team && !$0.isUnavailable }.map { local($0.state.position) }
        let line = offsideLine ?? OffsideRules.line(team: team, ball: ball.position, roster: roster, ends: ends)
        let safeProgress = line - max(0, configuration.onsideMargin)
        let inset = min(12, max(Pitch.playerRadius, configuration.pitchInset))
        let width = Pitch.width / 2 - inset
        let depth = Pitch.length / 2 - inset
        func bounded(_ point: Vector2, stayOnside: Bool = true) -> Vector2 {
            Vector2(x: min(width, max(-width, point.x)),
                    y: min(depth, max(-depth, stayOnside ? min(safeProgress, point.y) : point.y)))
        }
        func base(_ player: Footballer) -> Vector2 {
            local(baseTargets[player.id] ?? player.state.position)
        }
        let receiver = releasedPass.flatMap { pass in teammates.first { $0.id == pass.receiverID } }
        // Supporting players move towards the receiving area without all chasing the ball's
        // projected landing point. The passer remains available for a short return.
        let anchor: Vector2
        if let receiver, let pass = releasedPass {
            let position = local(receiver.state.position)
            anchor = position + (local(pass.destination) - position).clampedLength(6)
        } else {
            anchor = local(ball.position)
        }
        let available = teammates.filter {
            $0.id != receiver?.id && (releasedPass != nil || $0.id != carrierID)
        }
        var result: [Int: Vector2] = [:]
        for player in available { result[player.id] = bounded(base(player)) }
        if let receiver, let pass = releasedPass {
            result[receiver.id] = bounded(local(pass.destination), stayOnside: false)
        }
        guard !available.isEmpty else { return result.mapValues { $0 * attack } }

        // Formation progress gives forwards stable run duties, rather than reassigning roles
        // every time two nearby players exchange their distance ranking to the ball.
        let runnerCount = min(teammates.count >= 7 ? configuration.runnerCount : 1, max(0, available.count - 1))
        var runners: [Footballer] = []
        var remainder = available
        while runners.count < runnerCount {
            let next = remainder.min { first, second in
                func cost(_ player: Footballer) -> Double {
                    let home = base(player)
                    let previousLane = runners.first.map { base($0).x }
                    let sameLane = previousLane.map { max(0, 12 - abs(home.x - $0)) * 0.8 } ?? 0
                    let returnPenalty = releasedPass != nil && player.id == carrierID ? 30.0 : 0
                    let overlapBonus = player.id == configuration.overlappingDefenderID ? -100.0 : 0
                    return -home.y + sameLane + returnPenalty + overlapBonus
                        + max(0, (local(player.state.position) - anchor).length - 32) * 0.4
                }
                let a = cost(first), b = cost(second)
                return abs(a - b) < 0.000001 ? first.id < second.id : a < b
            }!
            runners.append(next)
            remainder.removeAll { $0.id == next.id }
        }
        let shortCount = min(teammates.count >= 7 ? 2 : 1, remainder.count)
        let supporters = remainder.sorted { first, second in
            func cost(_ player: Footballer) -> Double {
                // Small distance buckets stop sub-metre movement changing a short-support role.
                let distance = (local(player.state.position) - anchor).length
                return floor(distance / 2) * 2 + (base(player) - anchor).length * 0.15
                    - (releasedPass != nil && player.id == carrierID ? 15 : 0)
            }
            let a = cost(first), b = cost(second)
            return abs(a - b) < 0.000001 ? first.id < second.id : a < b
        }.prefix(shortCount)
        var occupied = [anchor]
        if let receiver, let destination = result[receiver.id] { occupied.append(destination) }

        func segmentDistance(_ point: Vector2, start: Vector2, end: Vector2) -> Double {
            let offset = end - start
            let fraction = (point - start).dot(offset) / max(0.001, offset.lengthSquared)
            // Pressure directly on the carrier should not make every outgoing lane unusable.
            guard fraction >= 0.15 && fraction <= 1.1 else { return .infinity }
            return (point - (start + offset * min(1, fraction))).length
        }
        func bestTarget(for player: Footballer, candidates: [Vector2], nominal: Vector2,
                        checkPassLane: Bool) -> Vector2 {
            let position = local(player.state.position)
            var best = bounded(nominal)
            var bestCost = Double.infinity
            for proposed in candidates {
                let point = bounded(proposed)
                var cost = (point - nominal).length * 0.32 + (point - position).length * 0.12
                for opponent in opponents {
                    let gap = (point - opponent).length
                    cost += pow(max(0, configuration.opponentClearance - gap), 2) * 1.8
                    if checkPassLane {
                        let laneGap = segmentDistance(opponent, start: anchor, end: point)
                        cost += pow(max(0, configuration.laneClearance - laneGap), 2) * 2.4
                    }
                }
                for other in occupied {
                    cost += pow(max(0, configuration.teammateSpacing - (point - other).length), 2) * 4
                }
                for other in teammates where other.id != player.id && other.id != carrierID {
                    cost += pow(max(0, 2.5 - (point - local(other.state.position)).length), 2)
                }
                if cost < bestCost - 0.000001 { best = point; bestCost = cost }
            }
            return best
        }

        for (index, player) in supporters.enumerated() {
            let home = base(player)
            let naturalSide = abs(home.x - anchor.x) > 1 ? (home.x > anchor.x ? 1.0 : -1.0)
                : (index.isMultiple(of: 2) ? -1.0 : 1.0)
            let distance = max(6, configuration.shortDistance)
            let nominal = anchor + Vector2(x: naturalSide * distance, y: -3)
            var candidates: [Vector2] = []
            for side in [naturalSide, -naturalSide] {
                for lateral in [distance, distance * 0.75, distance * 1.3] {
                    for forward in [-3.0, 4.0, -7.0, 7.0] {
                        candidates.append(anchor + Vector2(x: side * lateral, y: forward))
                    }
                }
            }
            let target = bestTarget(for: player, candidates: candidates, nominal: nominal, checkPassLane: true)
            result[player.id] = target
            occupied.append(target)
        }
        for player in runners {
            let home = base(player)
            let progress = max(home.y, anchor.y + max(8, configuration.runDistance))
            let nominal = Vector2(x: home.x, y: progress)
            var candidates: [Vector2] = []
            for lateral in [0.0, -5.0, 5.0, -10.0, 10.0] {
                for retreat in [0.0, -4.0] {
                    candidates.append(Vector2(x: home.x + lateral, y: progress + retreat))
                }
            }
            let target = bestTarget(for: player, candidates: candidates, nominal: nominal, checkPassLane: true)
            result[player.id] = target
            occupied.append(target)
        }
        return result.mapValues { $0 * attack }
    }
}
