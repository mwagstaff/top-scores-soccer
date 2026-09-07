import Foundation

/// The simulation keeps the user's club attacking north, including away fixtures.
/// Venue order is a presentation concern; persisted results use user/opponent order.
struct CareerMatchContext: Equatable, Sendable {
    let fixtureTitle: String
    let userIsAway: Bool
}
