import Foundation

struct Vector2: Equatable, Sendable {
    var x: Double
    var y: Double
    static let zero = Vector2(x: 0, y: 0)
    static let up = Vector2(x: 0, y: 1)
    var lengthSquared: Double { x * x + y * y }
    var length: Double { sqrt(lengthSquared) }
    var normalized: Vector2 { length > 0.000001 ? self / length : .zero }
    var perpendicular: Vector2 { Vector2(x: -y, y: x) }
    func dot(_ other: Vector2) -> Double { x * other.x + y * other.y }
    func rotated(by angle: Double) -> Vector2 {
        Vector2(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
    }
    func clampedLength(_ maximum: Double) -> Vector2 { length > maximum ? normalized * maximum : self }
    static func + (lhs: Self, rhs: Self) -> Self { Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static prefix func - (value: Self) -> Self { Self(x: -value.x, y: -value.y) }
    static func * (lhs: Self, rhs: Double) -> Self { Self(x: lhs.x * rhs, y: lhs.y * rhs) }
    static func / (lhs: Self, rhs: Double) -> Self { Self(x: lhs.x / rhs, y: lhs.y / rhs) }
    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Double) { lhs = lhs * rhs }
}

struct PlayerState: Sendable {
    var position = Vector2(x: 0, y: -2)
    var velocity = Vector2.zero
    var facing = Vector2.up
}

enum ExerciseMode: String, CaseIterable, Sendable { case solo, passing, match }
enum Team: String, Sendable { case blue, red }

/// Physical ends are separate from team identity and the scoreboard.
struct MatchEnds: Equatable, Sendable {
    var blueAttacksNorth = true

    func attackSign(for team: Team) -> Double {
        (team == .blue ? 1.0 : -1.0) * (blueAttacksNorth ? 1.0 : -1.0)
    }

    func direction(for team: Team) -> Vector2 { .up * attackSign(for: team) }

    func attackingTeam(atNorthGoal north: Bool) -> Team {
        north == blueAttacksNorth ? .blue : .red
    }
}

struct Footballer: Identifiable, Sendable {
    let id: Int
    let team: Team
    var state: PlayerState
    var isTackling = false
    var isSliding = false
    var isSentOff = false
    var isInjured = false
    var isUnavailable: Bool { isSentOff || isInjured }
    var yellowCards = 0
    var isGoalkeeper = false
    var goalkeeperDiveProgress = 0.0
    var goalkeeperReleaseProgress = 0.0
    var goalkeeperReleaseKind: GoalkeeperReleaseKind? = nil
    var goalkeeperReleaseDirection = Vector2.up
    var headingProgress = 0.0
    var fallProgress = 0.0
    var recoveryProgress = 0.0
    var fallDirection = Vector2.up
    /// API identity stays separate from the dense index used by the simulation.
    var clubPlayer: ClubPlayer? = nil
    var abilities: ArcadePlayerAbilities { ArcadePlayerAbilities(player: clubPlayer) }
}

/// These are arcade balancing values derived from one overall rating, not measured scouting
/// statistics. A fixed curve preserves comparisons when the downloaded catalogue changes.
struct ArcadePlayerAbilities: Equatable, Sendable {
    static let conversionVersion = 1
    var speed = 1.0
    var acceleration = 1.0
    var control = 1.0
    var passPower = 1.0
    var shotPower = 1.0
    var defending = 1.0
    var goalkeeping = 1.0
    var passErrorRadians = 0.0
    var shotErrorRadians = 0.0

    init(player: ClubPlayer?) {
        // Practice players retain the exact original mechanics, including perfect kick direction.
        guard let player else { return }
        let raw = player.effectiveRating
        let rating = min(95, max(55, raw.isFinite ? raw : 78))
        let quality = (rating - 78) / (rating < 78 ? 23 : 17)
        let role = player.role
        let defender = role == "D"
        let forward = role == "F"
        let midfielder = role == "M"
        speed = 1 + quality * 0.08
        acceleration = 1 + quality * 0.10
        control = 1 + quality * 0.18
        passPower = 1 + quality * 0.09 + (midfielder ? 0.025 : 0)
        shotPower = 1 + quality * 0.12 + (forward ? 0.035 : defender ? -0.025 : 0)
        defending = 1 + quality * 0.10 + (defender ? 0.04 : forward ? -0.025 : 0)
        goalkeeping = 1 + quality * 0.12
        passErrorRadians = (1.15 - quality * 0.65 - (midfielder ? 0.1 : 0)) * .pi / 180
        shotErrorRadians = (1.8 - quality * 0.9 + (defender ? 0.2 : forward ? -0.15 : 0)) * .pi / 180
    }
}

enum BallMode: String, Sendable { case free, controlled, pass, shot }
enum KickPowerKind: String, Sendable { case shot, cross, throwIn, keeperDistribution, longKick }
struct BallState: Sendable {
    var position = Vector2(x: 0, y: -0.75)
    var velocity = Vector2.zero
    var mode: BallMode = .controlled
    var height = 0.0
    var verticalVelocity = 0.0
}

struct FoulEvent: Equatable, Sendable {
    let id: Int
    let offenderID: Int
    let victimID: Int
    let awardedTeam: Team
    let position: Vector2
    let card: DisciplinaryCard
}

enum MatchRestartKind: String, Equatable, Sendable { case kickoff, throwIn, corner, goalKick, freeKick, offside, penalty, indirectFreeKick }

struct MatchRestart: Equatable, Sendable {
    let kind: MatchRestartKind
    let team: Team
    let position: Vector2
    let takerID: Int?
}

enum SandboxPhase: Equatable, Sendable {
    case playing
    case goal(north: Bool)
    case outOfPlay
    case restart(kind: MatchRestartKind, team: Team)
    case fullTime
    case halfTime
    case foulContact(team: Team)
    case freeKick(team: Team)
    case practiceEnded(losingTeam: Team)
}

enum ActionStatus: String, Sendable { case idle, pressed, charging, cancelled, tackling, sliding, queued, recovering }

enum Pitch {
    static let width = 68.0
    static let length = 105.0
    static let goalWidth = 9.0
    static let goalDepth = 3.0
    static let postRadius = 0.28
    static let playerRadius = 0.72
    static let ballRadius = 0.34
    static let crossbarHeight = 2.44
}
