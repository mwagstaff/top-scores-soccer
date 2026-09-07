import Foundation

enum TackleKind: String, Equatable, Sendable {
    case standing
    case slide
}

enum DisciplinaryCard: String, Equatable, Sendable {
    case none
    case yellow
    case red
}

struct TackleDecision: Equatable, Sendable {
    let foul: Bool
    let card: DisciplinaryCard

    static let clean = TackleDecision(foul: false, card: .none)
}

/// Arcade adjudication for an attempted tackle against an opposing player.
/// The simulation owns reach, contact geometry, random state and restarts.
enum TackleRules {
    struct Configuration: Equatable, Sendable {
        var standingYellowChance = 0.04
        var slideYellowChance = 0.20
        var behindYellowBonus = 0.20
        var highSpeedYellowBonus = 0.12
        var recklessSpeed = 12.0
        var recklessSlideRedChance = 0.04

        static let defaults = Configuration()
    }

    /// Contact fractions describe chronological swept contacts within one step.
    /// `nil` means no contact. A clean touch of the ball before (or at the same
    /// instant as) the body is legal; missing the ball is not itself a foul.
    /// `randomUnit` is a caller-supplied deterministic draw in `0..<1`.
    static func assess(
        kind: TackleKind,
        ballContactFraction: Double?,
        opponentContactFraction: Double?,
        approachFromBehind: Bool,
        relativeSpeed: Double,
        randomUnit: Double,
        configuration: Configuration = .defaults
    ) -> TackleDecision {
        guard let bodyContact = validContact(opponentContactFraction) else { return .clean }
        if let ballContact = validContact(ballContactFraction), ballContact <= bodyContact {
            return .clean
        }

        let speed = relativeSpeed.isFinite ? max(0, relativeSpeed) : 0
        let fastContact = speed >= max(0, configuration.recklessSpeed)
        let redChance = kind == .slide && approachFromBehind && fastContact
            ? probability(configuration.recklessSlideRedChance) : 0
        var yellowChance = kind == .slide
            ? configuration.slideYellowChance : configuration.standingYellowChance
        if approachFromBehind { yellowChance += configuration.behindYellowBonus }
        if fastContact { yellowChance += configuration.highSpeedYellowBonus }
        yellowChance = min(probability(yellowChance), 1 - redChance)

        // Invalid random input should never manufacture a card. Normal draws
        // are clamped only to protect this boundary from caller roundoff.
        let draw = randomUnit.isFinite ? min(max(randomUnit, 0), 1) : 1
        let card: DisciplinaryCard
        if draw < redChance {
            card = .red
        } else if draw < redChance + yellowChance {
            card = .yellow
        } else {
            card = .none
        }
        return TackleDecision(foul: true, card: card)
    }

    private static func validContact(_ fraction: Double?) -> Double? {
        guard let fraction, fraction.isFinite, (0...1).contains(fraction) else { return nil }
        return fraction
    }

    private static func probability(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
