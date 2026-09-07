import Foundation

/// Restart-only destinations. The caller moves players normally, keeps the taker/ball still,
/// and discards this layout when the ball is released. No positions or possession are mutated.
/// Distances/exceptions: https://www.theifab.com/laws/latest/free-kicks/ (13.2),
/// https://www.theifab.com/laws/latest/the-throw-in/ (15.1).
enum RestartSupport {
    struct Layout: Sendable {
        var outletIDs: [Int] = []
        var outletTargets: [Int: Vector2] = [:]
        var opponentTargets: [Int: Vector2] = [:]
    }

    static let freeKickDistance = 9.15
    static let throwInDistance = 2.0
    static let outletSpacing = 4.5
    static let goalAreaHalfWidth = 9.16
    static let goalAreaDepth = 5.5
    private static let bodySpacing = Pitch.playerRadius * 2 + 0.2
    // Match the visible 40.32m penalty-area width, rather than the keeper AI's save region.
    private static let boxHalfWidth = PenaltyRules.boxHalfWidth
    private static let boxDepth = PenaltyRules.boxDepth

    static func layout(for restart: MatchRestart?, roster: [Footballer],
                       unavailableIDs: Set<Int> = [], previousOutletIDs: [Int] = [],
                       freeKickStandBack: Double = freeKickDistance) -> Layout {
        guard let restart, supported(restart.kind), let taker = restart.takerID,
              roster.contains(where: { $0.id == taker && $0.team == restart.team && !$0.isSentOff }) else {
            return Layout()
        }
        let origin = restartOrigin(restart)
        let eligible = roster.filter {
            $0.team == restart.team && $0.id != taker && !$0.isGoalkeeper && !$0.isSentOff
                && !$0.isTackling && !$0.isSliding && $0.fallProgress <= 0.001
                && $0.recoveryProgress <= 0.001 && !unavailableIDs.contains($0.id)
        }.sorted {
            let first = ($0.state.position - origin).lengthSquared
            let second = ($1.state.position - origin).lengthSquared
            return abs(first - second) < 0.000001 ? $0.id < $1.id : first < second
        }
        if restart.kind == .goalKick {
            return goalKickLayout(restart: restart, eligible: eligible, roster: roster,
                previousOutletIDs: previousOutletIDs, freeKickStandBack: freeKickStandBack)
        }
        var selected: [Footballer] = []
        for id in previousOutletIDs {
            if selected.count < 2, !selected.contains(where: { $0.id == id }),
               let player = eligible.first(where: { $0.id == id }) { selected.append(player) }
        }
        selected += eligible.filter { candidate in !selected.contains(where: { $0.id == candidate.id }) }
            .prefix(max(0, 2 - selected.count))
        var result = Layout()
        let options = outletCandidates(restart: restart)
        let goal = Vector2(x: 0, y: restart.team == .blue ? Pitch.length / 2 : -Pitch.length / 2)
        let towardGoal = (goal - origin).normalized
        for player in selected {
            var best: Vector2?
            var bestCost = Double.infinity
            for target in options {
                guard result.outletTargets.values.allSatisfy({ ($0 - target).length >= outletSpacing }) else { continue }
                if result.outletIDs.isEmpty, selected.count > 1,
                   !options.contains(where: { ($0 - target).length >= outletSpacing }) { continue }
                let offset = target - origin
                var cost = (target - player.state.position).length * 0.10 + abs(offset.length - 6.5) * 0.3
                if restart.kind != .throwIn {
                    // Keep the immediate goalward shooting lane open; boundaries can require
                    // an inside diagonal instead of a strictly backwards supporting run.
                    cost += max(0, offset.dot(towardGoal)) * 2
                    if offset.dot(towardGoal) > 0, abs(offset.dot(towardGoal.perpendicular)) < 2.5 { cost += 30 }
                }
                for other in roster where other.id != player.id && other.id != taker && !other.isSentOff {
                    let clearance = other.team == restart.team ? 2.2 : 3.0
                    cost += pow(max(0, clearance - (other.state.position - target).length), 2) * 4
                }
                if cost < bestCost - 0.000001 { best = target; bestCost = cost }
            }
            if let best {
                result.outletIDs.append(player.id)
                result.outletTargets[player.id] = best
            }
        }
        var occupied = result.outletIDs.compactMap { result.outletTargets[$0] }
        for opponent in roster.filter({ $0.team != restart.team && !$0.isSentOff }).sorted(by: { $0.id < $1.id }) {
            let target = legalOpponentTarget(from: opponent.state.position, team: opponent.team,
                restart: restart, occupied: occupied, freeKickStandBack: freeKickStandBack)
            result.opponentTargets[opponent.id] = target
            occupied.append(target)
        }
        return result
    }

    /// Used after ordinary separation/movement to retain the restart restriction. An exceptional
    /// goal-line destination has y == ±Pitch.length/2; callers must allow that line instead of
    /// applying the usual whole-body pitch inset to it.
    static func legalOpponentTarget(from position: Vector2, team: Team, restart: MatchRestart,
                                    occupied: [Vector2] = [],
                                    freeKickStandBack: Double = freeKickDistance) -> Vector2 {
        guard supported(restart.kind), team != restart.team else { return bounded(position) }
        func legal(_ point: Vector2) -> Bool {
            isLegalOpponentPosition(point, team: team, restart: restart, freeKickStandBack: freeKickStandBack)
        }
        func separated(_ point: Vector2) -> Bool {
            occupied.allSatisfy { ($0 - point).length >= bodySpacing - 0.000001 }
        }
        if legal(position), separated(position) { return position }
        let origin = restartOrigin(restart)
        let clearance = requiredDistance(restart.kind, freeKickStandBack: freeKickStandBack)
        let start = bounded(position)
        let away = (start - origin).length > 0.000001 ? (start - origin).normalized : (team == .blue ? -Vector2.up : .up)
        var candidates = [start, bounded(origin + away * clearance)]
        // Nearby spacing alternatives stop coincident players being sent to a distant wall.
        for radius in [bodySpacing, bodySpacing * 2, bodySpacing * 3] {
            for index in 0..<36 {
                let angle = Double(index) * .pi / 18
                candidates.append(bounded(start + Vector2(x: cos(angle), y: sin(angle)) * radius))
            }
        }
        for radius in [clearance, clearance + bodySpacing, clearance + bodySpacing * 2] {
            for index in 0..<72 {
                let angle = Double(index) * .pi / 36
                candidates.append(bounded(origin + Vector2(x: cos(angle), y: sin(angle)) * radius))
            }
        }
        if restart.kind != .throwIn {
            let ownGoalY = team == .blue ? -Pitch.length / 2 : Pitch.length / 2
            let goalHalf = Pitch.goalWidth / 2 - Pitch.playerRadius - Pitch.postRadius
            candidates.append(Vector2(x: min(goalHalf, max(-goalHalf, start.x)), y: ownGoalY))
            for index in -2...2 { candidates.append(Vector2(x: Double(index) * bodySpacing, y: ownGoalY)) }
            if insideTakingPenaltyArea(origin, team: restart.team) {
                let attack = restart.team == .blue ? 1.0 : -1.0
                let front = (-Pitch.length / 2 + boxDepth + Pitch.playerRadius + 0.05) * attack
                let side = boxHalfWidth + Pitch.playerRadius + 0.05
                candidates.append(bounded(Vector2(x: start.x, y: front)))
                candidates.append(bounded(Vector2(x: side, y: start.y)))
                candidates.append(bounded(Vector2(x: -side, y: start.y)))
            }
        }
        for x in [-Pitch.width / 2, Pitch.width / 2] {
            for y in [-Pitch.length / 2, Pitch.length / 2] { candidates.append(bounded(Vector2(x: x, y: y))) }
        }
        let valid = candidates.filter(legal)
        let spaced = valid.filter(separated)
        let choices = spaced.isEmpty ? valid : spaced
        return choices.min { ($0 - start).lengthSquared < ($1 - start).lengthSquared } ?? start
    }

    static func isLegalOpponentPosition(_ position: Vector2, team: Team, restart: MatchRestart,
                                        freeKickStandBack: Double = freeKickDistance) -> Bool {
        guard position.x.isFinite, position.y.isFinite else { return false }
        guard supported(restart.kind), team != restart.team else { return true }
        let goalLine = restart.kind != .throwIn && isOnOwnGoalLine(position, team: team)
        let inset = Pitch.playerRadius
        let inside = abs(position.x) <= Pitch.width / 2 - inset + 0.000001
            && abs(position.y) <= Pitch.length / 2 - inset + 0.000001
        guard inside || goalLine else { return false }
        let origin = restartOrigin(restart)
        if restart.kind != .throwIn, insideTakingPenaltyArea(origin, team: restart.team),
           insideTakingPenaltyArea(position, team: restart.team, margin: Pitch.playerRadius) { return false }
        return goalLine || (position - origin).length >= requiredDistance(restart.kind,
            freeKickStandBack: freeKickStandBack) - 0.000001
    }

    private static func supported(_ kind: MatchRestartKind) -> Bool {
        kind == .throwIn || kind == .goalKick || kind == .freeKick || kind == .offside || kind == .indirectFreeKick
    }

    private static func requiredDistance(_ kind: MatchRestartKind, freeKickStandBack: Double) -> Double {
        kind == .throwIn ? throwInDistance
            : min(15, max(freeKickDistance, freeKickStandBack.isFinite ? freeKickStandBack : freeKickDistance))
    }

    private static func restartOrigin(_ restart: MatchRestart) -> Vector2 {
        guard restart.kind == .throwIn else { return restart.position }
        // Law 15 measures two metres from the touchline point, not a thrower's infield inset.
        return Vector2(x: restart.position.x < 0 ? -Pitch.width / 2 : Pitch.width / 2, y: restart.position.y)
    }

    private static func bounded(_ point: Vector2, inset: Double = Pitch.playerRadius) -> Vector2 {
        Vector2(x: min(Pitch.width / 2 - inset, max(-Pitch.width / 2 + inset, point.x.isFinite ? point.x : 0)),
                y: min(Pitch.length / 2 - inset, max(-Pitch.length / 2 + inset, point.y.isFinite ? point.y : 0)))
    }

    private static func insideTakingPenaltyArea(_ point: Vector2, team: Team, margin: Double = 0) -> Bool {
        let depth = team == .blue ? point.y + Pitch.length / 2 : Pitch.length / 2 - point.y
        return abs(point.x) <= boxHalfWidth + margin && depth <= boxDepth + margin && depth >= -margin
    }

    private static func isOnOwnGoalLine(_ point: Vector2, team: Team) -> Bool {
        let goalY = team == .blue ? -Pitch.length / 2 : Pitch.length / 2
        return abs(point.y - goalY) < 0.000001
            && abs(point.x) <= Pitch.goalWidth / 2 - Pitch.playerRadius - Pitch.postRadius
    }

    private static func outletCandidates(restart: MatchRestart) -> [Vector2] {
        let origin = restartOrigin(restart)
        let attack = restart.team == .blue ? 1.0 : -1.0
        var offsets: [Vector2] = []
        if restart.kind == .throwIn {
            let inward = origin.x < 0 ? 1.0 : -1.0
            for depth in [5.5, 4.0, 7.0] {
                for along in [4.0, -4.0, 0.0, 6.0, -6.0] {
                    offsets.append(Vector2(x: inward * depth, y: along * attack))
                }
            }
        } else {
            for side in [-1.0, 1.0] {
                for offset in [Vector2(x: 6, y: -3), Vector2(x: 7, y: 0), Vector2(x: 4, y: -5), Vector2(x: 5, y: -6)] {
                    offsets.append(Vector2(x: offset.x * side, y: offset.y) * attack)
                }
            }
            // In a defensive corner, backwards and one lateral route leave the pitch.
            for radius in [6.5, 8.5] {
                for index in 0..<24 {
                    let angle = Double(index) * .pi / 12
                    offsets.append(Vector2(x: cos(angle), y: sin(angle)) * (radius * attack))
                }
            }
        }
        return offsets.map { bounded(origin + $0, inset: 1.2) }.filter {
            let distance = ($0 - origin).length
            return distance >= 5 - 0.000001 && distance <= 9 + 0.000001
        }
    }

    private static func goalKickLayout(restart: MatchRestart, eligible: [Footballer], roster: [Footballer],
                                       previousOutletIDs: [Int], freeKickStandBack: Double) -> Layout {
        var result = Layout()
        let target = goalKickShortOption(for: restart)
        let teamOutfield = roster.filter { $0.team == restart.team && !$0.isGoalkeeper }
            .sorted { $0.id < $1.id }
        let fallbackDefenderCount = teamOutfield.count >= 8 ? 4 : min(2, teamOutfield.count)
        let fallbackDefenderIDs = Set(teamOutfield.prefix(fallbackDefenderCount).map(\.id))
        func isDefender(_ player: Footballer) -> Bool {
            player.clubPlayer.map { $0.role == "D" } ?? fallbackDefenderIDs.contains(player.id)
        }
        let preferred = previousOutletIDs.compactMap { id in eligible.first { $0.id == id } }.first
            ?? eligible.min { first, second in
                let firstDefender = isDefender(first)
                let secondDefender = isDefender(second)
                if firstDefender != secondDefender { return firstDefender }
                let a = (first.state.position - target).lengthSquared
                let b = (second.state.position - target).lengthSquared
                return abs(a - b) < 0.000001 ? first.id < second.id : a < b
            }
        if let preferred {
            result.outletIDs = [preferred.id]
            result.outletTargets[preferred.id] = target
        }
        var occupied = preferred == nil ? [] : [target]
        for opponent in roster.filter({ $0.team != restart.team && !$0.isSentOff }).sorted(by: { $0.id < $1.id }) {
            let target = legalOpponentTarget(from: opponent.state.position, team: opponent.team,
                restart: restart, occupied: occupied, freeKickStandBack: freeKickStandBack)
            result.opponentTargets[opponent.id] = target
            occupied.append(target)
        }
        return result
    }

    private static func goalKickShortOption(for restart: MatchRestart) -> Vector2 {
        let attack = restart.team == .blue ? 1.0 : -1.0
        let takingSide = restart.position.x >= 0 ? 1.0 : -1.0
        return Vector2(x: -takingSide * goalAreaHalfWidth,
                       y: (-Pitch.length / 2 + goalAreaDepth) * attack)
    }
}
