import Foundation

/// Match penalty geometry follows the painted box. Body/contact centres, rather than the
/// ball's position after the foul, decide where an offence occurred.
enum PenaltyRules {
    static let boxHalfWidth = 20.16
    static let boxDepth = 16.5
    static let markDistance = 11.0
    static let standBackDistance = 9.15

    static func insideOwnArea(_ position: Vector2, team: Team, ends: MatchEnds = MatchEnds()) -> Bool {
        guard position.x.isFinite, position.y.isFinite else { return false }
        let attack = ends.attackSign(for: team)
        let depth = Pitch.length / 2 + position.y * attack
        return abs(position.x) <= boxHalfWidth + 0.0000001
            && depth >= -0.0000001 && depth <= boxDepth + 0.0000001
    }

    static func awardsPenalty(at position: Vector2, offender: Team, awarded: Team, ends: MatchEnds = MatchEnds()) -> Bool {
        offender != awarded && insideOwnArea(position, team: offender, ends: ends)
    }

    static func mark(for attackingTeam: Team, ends: MatchEnds = MatchEnds()) -> Vector2 {
        Vector2(x: 0, y: (Pitch.length / 2 - markDistance) * ends.attackSign(for: attackingTeam))
    }

    static func goalkeeperPosition(defending attackingTeam: Team, ends: MatchEnds = MatchEnds()) -> Vector2 {
        Vector2(x: 0, y: Pitch.length / 2 * ends.attackSign(for: attackingTeam))
    }

    /// Players retain their side/width where possible; the penalty arc and area only move
    /// someone who is inside a restricted zone. A foot-radius margin keeps sprites clear.
    static func waitingPosition(_ position: Vector2, attackingTeam: Team,
                                occupied: [Vector2] = [], ends: MatchEnds = MatchEnds()) -> Vector2 {
        let base = projectWaitingPosition(position, attackingTeam: attackingTeam, ends: ends)
        let separation = Pitch.playerRadius * 2 + 0.12
        func clear(_ point: Vector2) -> Bool {
            !occupied.contains { (point - $0).length < separation - 0.0000001 }
        }
        if clear(base) { return base }
        let attack = ends.attackSign(for: attackingTeam)
        let spacing = max(1.65, separation)
        // Prefer a little lateral space on the same legal arc, then a row behind it.
        // The bounded search easily fits a full 22-player roster without nudging the keeper.
        for row in 0...12 {
            for column in 0...40 {
                for side in column == 0 ? [1.0] : [1.0, -1.0] {
                    let requested = Vector2(x: base.x + Double(column) * spacing * side,
                        y: base.y - attack * Double(row) * spacing)
                    let candidate = projectWaitingPosition(requested, attackingTeam: attackingTeam, ends: ends)
                    if clear(candidate) { return candidate }
                }
            }
        }
        return base
    }

    private static func projectWaitingPosition(_ position: Vector2, attackingTeam: Team, ends: MatchEnds = MatchEnds()) -> Vector2 {
        let attack = ends.attackSign(for: attackingTeam)
        let x = min(Pitch.width / 2 - Pitch.playerRadius,
                    max(-Pitch.width / 2 + Pitch.playerRadius, position.x))
        let markY = Pitch.length / 2 - markDistance
        var progress = min(position.y * attack, markY - Pitch.playerRadius - 0.01)
        if abs(x) <= boxHalfWidth + Pitch.playerRadius {
            progress = min(progress, Pitch.length / 2 - boxDepth - Pitch.playerRadius - 0.01)
        }
        let clearance = standBackDistance + Pitch.playerRadius
        if abs(x) < clearance {
            progress = min(progress, markY - sqrt(clearance * clearance - x * x))
        }
        progress = max(-Pitch.length / 2 + Pitch.playerRadius, progress)
        return Vector2(x: x, y: progress * attack)
    }
}

enum PenaltyMechanics {
    /// Even sideways/backward touch aim produces a legal forward penalty. Horizontal aim
    /// chooses the corner; ordinary shot power, loft, overhold and aftertouch stay intact.
    static func shot(origin: Vector2, aim: Vector2, team: Team, heldFor: Double,
                     tuning: GameplayTuning, ends: MatchEnds = MatchEnds()) -> KickMechanics.Shot? {
        guard heldFor.isFinite, heldFor >= 0, aim.x.isFinite, aim.y.isFinite else { return nil }
        let attack = ends.attackSign(for: team)
        let goalY = Pitch.length / 2 * attack
        let forward = max(0.1, (goalY - origin.y) * attack)
        let requested = aim.length > 0.0001 ? aim.normalized : Vector2(x: 0, y: attack)
        let corner = Pitch.goalWidth / 2 - Pitch.postRadius - Pitch.ballRadius - 0.22
        let x = min(corner, max(-corner, origin.x + requested.x * forward / max(0.35, abs(requested.y))))
        let direction = (Vector2(x: x, y: goalY) - origin).normalized
        let duration = heldFor < tuning.holdThreshold
            ? tuning.holdThreshold + tuning.fullChargeDuration * 0.6 : heldFor
        return KickMechanics.shot(origin: origin, aim: direction, team: team, heldFor: duration, tuning: tuning, ends: ends)
    }
}
