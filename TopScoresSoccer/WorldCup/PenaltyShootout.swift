import Foundation

enum PenaltyDirection: String, CaseIterable, Identifiable, Sendable {
    case left, centre, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .left: "arrow.down.left"
        case .centre: "arrow.down"
        case .right: "arrow.down.right"
        }
    }
}

enum PenaltyTurn: String, Sendable {
    case userShoots, userSaves, finished
}

struct PenaltyAttempt: Identifiable, Equatable, Sendable {
    let id: Int
    let byUser: Bool
    let scored: Bool
}

struct PenaltyShootout: Equatable, Sendable {
    private(set) var userGoals = 0
    private(set) var opponentGoals = 0
    private(set) var userAttempts = 0
    private(set) var opponentAttempts = 0
    private(set) var attempts: [PenaltyAttempt] = []
    private(set) var turn: PenaltyTurn = .userShoots
    private(set) var message = "Choose where to place your penalty."
    private var randomState: UInt64

    init(seed: UInt64) {
        randomState = seed == 0 ? 0xBADC_0FFE_E0DD_F00D : seed
    }

    var isFinished: Bool { turn == .finished }
    var userWon: Bool { isFinished && userGoals > opponentGoals }

    mutating func choose(_ direction: PenaltyDirection) {
        guard !isFinished else { return }
        switch turn {
        case .userShoots:
            let keeper = randomDirection()
            let onTarget = unit() > 0.08
            let scored = onTarget && (keeper != direction || unit() < 0.22)
            userAttempts += 1
            if scored { userGoals += 1 }
            attempts.append(.init(id: attempts.count, byUser: true, scored: scored))
            message = scored ? "Goal! Now choose your keeper’s dive." : "Saved or missed. Choose your keeper’s dive."
            turn = .userSaves
        case .userSaves:
            let shot = randomDirection()
            let onTarget = unit() > 0.1
            let scored = onTarget && (shot != direction || unit() < 0.18)
            opponentAttempts += 1
            if scored { opponentGoals += 1 }
            attempts.append(.init(id: attempts.count, byUser: false, scored: scored))
            if shouldFinish() {
                turn = .finished
                message = userWon ? "You win the shoot-out!" : "The opposition win the shoot-out."
            } else {
                turn = .userShoots
                message = scored ? "They score. Choose your next penalty." : "Saved or missed! Choose your next penalty."
            }
        case .finished: break
        }
    }

    private func shouldFinish() -> Bool {
        if userAttempts < 5 || opponentAttempts < 5 {
            let userRemaining = 5 - userAttempts
            let opponentRemaining = 5 - opponentAttempts
            if userGoals > opponentGoals + opponentRemaining { return true }
            if opponentGoals > userGoals + userRemaining { return true }
            return false
        }
        return userAttempts == opponentAttempts && userGoals != opponentGoals
    }

    private mutating func randomDirection() -> PenaltyDirection {
        PenaltyDirection.allCases[Int(unit() * Double(PenaltyDirection.allCases.count)).clamped(to: 0...2)]
    }

    private mutating func unit() -> Double {
        randomState &+= 0x9E3779B97F4A7C15
        var z = randomState
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / 9_007_199_254_740_992
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
