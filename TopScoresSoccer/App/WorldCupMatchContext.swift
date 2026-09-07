import Foundation

struct WorldCupMatchContext: Equatable, Sendable {
    let fixtureTitle: String
    let userIsAway: Bool
    let isKnockout: Bool
    let shootoutSeed: UInt64
}

enum TournamentMatchPeriod: Equatable, Sendable {
    case regulation, extraTime
}
