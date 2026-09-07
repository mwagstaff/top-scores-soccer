import UIKit

/// Discrete physical contacts, independent of button-down and ordinary dribble touches.
enum GameplayHaptic: Equatable {
    case pass, shot, challenge, slideContact, foul

    fileprivate var style: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .pass: .light
        case .shot: .medium
        case .challenge: .rigid
        case .slideContact, .foul: .heavy
        }
    }

    fileprivate var intensity: CGFloat {
        switch self {
        case .pass: 0.65
        case .shot: 0.9
        case .challenge: 0.65
        case .slideContact: 0.8
        case .foul: 1
        }
    }
}

@MainActor
final class GameHaptics {
    private weak var view: UIView?
    private var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    func attach(to view: UIView) {
        stop()
        self.view = view
    }

    func detach() {
        stop()
        view = nil
    }

    /// Prepare at the start of an intentional gesture, never continuously while running.
    func prepare() {
        guard view?.window != nil else { return }
        for style in [UIImpactFeedbackGenerator.FeedbackStyle.light, .medium, .rigid, .heavy] {
            generator(for: style)?.prepare()
        }
    }

    func play(_ event: GameplayHaptic) {
        guard view?.window != nil else { return }
        let feedback = generator(for: event.style)
        feedback?.impactOccurred(intensity: event.intensity)
        feedback?.prepare()
    }

    func stop() { generators.removeAll() }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator? {
        guard let view else { return nil }
        if let existing = generators[style] { return existing }
        let generator = UIImpactFeedbackGenerator(style: style, view: view)
        generators[style] = generator
        return generator
    }
}
