import Observation
import SwiftUI

@MainActor
@Observable
final class GameSession {
    @ObservationIgnored let scene: GameScene
    let configuration: FriendlyMatchConfiguration?
    let careerContext: CareerMatchContext?
    let worldCupContext: WorldCupMatchContext?
    @ObservationIgnored private let onCareerComplete: ((Int, Int) throws -> Void)?
    @ObservationIgnored private let onWorldCupComplete: ((WorldCupUserMatchOutcome) throws -> Void)?
    private(set) var careerResultSaved = false
    private(set) var careerSaveError: String?
    private(set) var worldCupResultSaved = false
    private(set) var worldCupSaveError: String?
    private(set) var tournamentPeriod: TournamentMatchPeriod = .regulation
    private(set) var needsExtraTime = false
    private(set) var penaltyShootout: PenaltyShootout?
    @ObservationIgnored private var attemptedCareerSave = false
    @ObservationIgnored private var handledWorldCupPeriodEnd = false
    @ObservationIgnored private var regulationScore: (user: Int, opponent: Int)?
    var hud = SandboxHUD()
    var mode: ExerciseMode = .launchMode {
        didSet { scene.setMode(mode) }
    }
    var tuning = GameplayTuning.defaults {
        didSet { scene.simulation.tuning = tuning }
    }
    var debugEnabled = false {
        didSet { scene.debugEnabled = debugEnabled }
    }
    var soundEnabled = true {
        didSet { scene.soundEnabled = soundEnabled }
    }
    var hapticsEnabled = true {
        didSet { scene.hapticsEnabled = hapticsEnabled }
    }
    var userPaused = false { didSet { reconcilePause() } }
    var showingSettings = false { didSet { reconcilePause() } }
    var showingHelp = false { didSet { reconcilePause() } }
    var active = true { didSet { reconcilePause() } }

    init(configuration: FriendlyMatchConfiguration? = nil, startingMode: ExerciseMode? = nil,
         careerContext: CareerMatchContext? = nil, onCareerComplete: ((Int, Int) throws -> Void)? = nil) {
        self.worldCupContext = nil
        self.onWorldCupComplete = nil
        self.configuration = configuration
        self.careerContext = careerContext
        self.onCareerComplete = onCareerComplete
        let initialMode: ExerciseMode = configuration == nil ? (startingMode ?? .launchMode) : .match
        mode = initialMode
        scene = GameScene(mode: initialMode, configuration: configuration, userIsAway: careerContext?.userIsAway ?? false)
        scene.onHUDUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.hud = snapshot
            if self.isCareerMatch && !self.attemptedCareerSave { self.saveCareerResult() }
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),
           ProcessInfo.processInfo.arguments.contains("--short-match"), mode == .match {
            tuning.matchDuration = 2
            scene.simulation.tuning = tuning
            scene.resetSandbox(clearScore: true)
        }
        if configuration == nil { configureUITestScenario() }
        scene.refreshHUD()
    }

    init(configuration: FriendlyMatchConfiguration, worldCupContext: WorldCupMatchContext,
         onWorldCupComplete: @escaping (WorldCupUserMatchOutcome) throws -> Void) {
        self.configuration = configuration
        self.careerContext = nil
        self.worldCupContext = worldCupContext
        self.onCareerComplete = nil
        self.onWorldCupComplete = onWorldCupComplete
        mode = .match
        scene = GameScene(mode: .match, configuration: configuration, userIsAway: worldCupContext.userIsAway)
        scene.onHUDUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.hud = snapshot
            self.handleWorldCupPeriodEnd()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),
           ProcessInfo.processInfo.arguments.contains("--short-match") {
            tuning.matchDuration = 2
            scene.simulation.tuning = tuning
            scene.resetSandbox(clearScore: true)
        }
        scene.refreshHUD()
    }

    /// Isolated starting positions for real-touch UI checks. Normal launches never enter here.
    private func configureUITestScenario() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting") else { return }
        #if DEBUG
        if mode == .match, arguments.contains("--penalty") || arguments.contains("--free-kick") {
            // Enter through a real rear-on challenge, including contact, fall, whistle and cards.
            // This is a live match penalty, separate from the World Cup shootout screen.
            scene.simulation.tuning.aiSpeedScale = 0
            scene.simulation.pressAction()
            scene.simulation.releaseAction(heldFor: 0.12)
            scene.simulation.cancelInput()
            for id in scene.simulation.roster.indices {
                scene.simulation.roster[id].state = PlayerState(position: Vector2(
                    x: Double(id % 4 - 2) * 12, y: id < 5 ? -20 : 0))
            }
            scene.simulation.roster[4].state.position = Vector2(x: 0, y: -50)
            scene.simulation.roster[9].state.position = Vector2(x: 0, y: 50)
            if arguments.contains("--free-kick") {
                scene.simulation.roster[1].state.position = Vector2(x: -10, y: 12)
                scene.simulation.roster[2].state.position = Vector2(x: 10, y: 12)
            }
            let spot = Vector2(x: 0, y: arguments.contains("--penalty") ? 42 : 20)
            scene.simulation.roster[0].state = PlayerState(position: spot)
            scene.simulation.ball = BallState(position: spot + .up * 0.9, mode: .free)
            scene.simulation.step(dt: 1.0 / 60)
            scene.simulation.roster[5].state = PlayerState(position: spot - .up * 1.44, facing: .up)
            scene.simulation.ball = BallState(position: spot + Vector2(x: 0.9, y: -0.9), mode: .controlled)
            scene.simulation.step(dt: 1.0 / 60)
            scene.simulation.tuning.aiSpeedScale = tuning.aiSpeedScale
            return
        }
        #endif
        if arguments.contains("--header"), mode == .solo {
            scene.simulation.player.position = .zero
            // Keep a reachable ball overhead while XCTest locates the real touch controls.
            // Production gravity and moving arrivals are covered by simulation tests.
            scene.simulation.tuning.ballGravity = 0.01
            scene.simulation.ball = BallState(position: .up, mode: .pass, height: 1.6)
            return
        }
        if arguments.contains("--high-clearance"), mode == .solo {
            scene.simulation.player.position = Vector2(x: 0, y: -30)
            scene.simulation.ball.position = Vector2(x: 0, y: -28.75)
            return
        }
        if arguments.contains("--offside"), mode == .match {
            scene.simulation.tuning.aiSpeedScale = 0
            scene.simulation.pressAction()
            scene.simulation.releaseAction(heldFor: 0.12)
            scene.simulation.cancelInput()
            for id in scene.simulation.roster.indices {
                scene.simulation.roster[id].state.position = Vector2(x: Double(id % 4 - 2) * 10,
                    y: id < 5 ? -10 : 30)
                scene.simulation.roster[id].state.velocity = .zero
            }
            scene.simulation.roster[4].state.position = Vector2(x: 0, y: -50)
            scene.simulation.roster[9].state.position = Vector2(x: 0, y: 50)
            scene.simulation.roster[5].state.position = Vector2(x: 0, y: -4)
            scene.simulation.roster[6].state.position = Vector2(x: 0, y: -20)
            scene.simulation.ball = BallState(position: Vector2(x: 0, y: -5), mode: .free)
            scene.simulation.step(dt: 1.0 / 60)
            scene.simulation.ball = BallState(position: Vector2(x: 0, y: -19), velocity: -.up * 6, mode: .pass)
            scene.simulation.step(dt: 1.0 / 60)
            return
        }
        if arguments.contains("--shot-lane"), mode == .solo {
            scene.simulation.player.position = Vector2(x: 0, y: 32)
            scene.simulation.ball.position = Vector2(x: 0, y: 33.25)
            return
        }
        let hands = arguments.contains("--keeper-hands")
        let feet = arguments.contains("--keeper-feet")
        let throwIn = arguments.contains("--throw-in")
        #if DEBUG
        let goalKick = arguments.contains("--goal-kick")
        #else
        let goalKick = false
        #endif
        guard mode == .match, hands || feet || throwIn || goalKick else { return }
        tuning.aiSpeedScale = 0
        scene.simulation.tuning = tuning
        scene.simulation.pressAction()
        scene.simulation.releaseAction(heldFor: 0.12)
        for id in scene.simulation.roster.indices where !scene.simulation.roster[id].isGoalkeeper {
            scene.simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -22 : 22,
                                                                 y: id < 5 ? -20 : 20)
            scene.simulation.roster[id].state.velocity = .zero
        }
        if hands || throwIn || goalKick {
            // A real opponent touch changes possession/handling eligibility before the next event.
            scene.simulation.ball = BallState(position: scene.simulation.roster[5].state.position + .up,
                                              velocity: .zero, mode: .free)
            scene.simulation.step(dt: 1.0 / 60)
        }
        if goalKick {
            scene.simulation.ball = BallState(position: Vector2(x: 17, y: -52),
                                              velocity: -.up * 90, mode: .free)
            scene.simulation.step(dt: 1.0 / 60)
            for _ in 0..<120 where scene.simulation.phase != .playing {
                scene.simulation.step(dt: 1.0 / 60)
            }
            scene.simulation.roster[0].state = PlayerState(position: Vector2(x: 0, y: -26))
            scene.simulation.roster[1].state = PlayerState(position: Vector2(x: 12, y: -34))
            scene.simulation.cancelInput()
        } else if throwIn {
            scene.simulation.roster[0].state.position = Vector2(x: 24, y: -10)
            scene.simulation.roster[1].state.position = Vector2(x: 25, y: 8)
            scene.simulation.roster[2].state.position = Vector2(x: 18, y: -5)
            scene.simulation.ball = BallState(position: Vector2(x: 34.2, y: 0),
                                              velocity: Vector2(x: 35, y: 0), mode: .free)
            scene.simulation.step(dt: 1.0 / 60)
            for _ in 0..<90 where scene.simulation.phase != .playing {
                scene.simulation.step(dt: 1.0 / 60)
            }
            scene.simulation.tuning.aiSpeedScale = GameplayTuning.defaults.aiSpeedScale
        } else {
            scene.simulation.roster[4].state.position = Vector2(x: 0, y: -47)
            scene.simulation.roster[4].state.velocity = .zero
            scene.simulation.ball = BallState(position: Vector2(x: 0, y: -45.9),
                                              velocity: -.up * 4, mode: .pass)
            for _ in 0..<8 { scene.simulation.step(dt: 1.0 / 60) }
            scene.simulation.cancelInput()
        }
    }

    func reset() { guard !isCompetitionMatch else { return }; scene.resetSandbox() }
    func resetScore() { guard !isCompetitionMatch else { return }; scene.resetSandbox(clearScore: true) }
    func restoreDefaults() { tuning = .defaults }
    var isClubMatch: Bool { configuration != nil && mode == .match }
    var isCareerMatch: Bool { careerContext != nil && isClubMatch }
    var isWorldCupMatch: Bool { worldCupContext != nil && isClubMatch }
    var isCompetitionMatch: Bool { isCareerMatch || isWorldCupMatch }
    var modeTitle: String {
        if isCareerMatch { return careerContext!.fixtureTitle }
        if isWorldCupMatch {
            return tournamentPeriod == .extraTime ? "Extra time · 90–120′" : worldCupContext!.fixtureTitle
        }
        return isClubMatch ? "11v11 friendly" : mode.title
    }
    var resultScore: (home: Int, away: Int) {
        if isCompetitionMatch, case .practiceEnded(let losingTeam) = hud.phase {
            let userLost = losingTeam == .blue
            let homeLost = hud.userIsAway ? !userLost : userLost
            return homeLost ? (0, 3) : (3, 0)
        }
        return (hud.scoreboardHomeGoals, hud.scoreboardAwayGoals)
    }

    /// A finished fixture commits before leaving the pitch. Repeated HUD updates and taps
    /// cannot duplicate it; a failed disk write leaves the result available for explicit retry.
    func saveCareerResult() {
        guard isCareerMatch, !careerResultSaved, let onCareerComplete else { return }
        let score: (Int, Int)
        switch hud.phase {
        case .fullTime: score = (hud.northGoals, hud.southGoals)
        case .practiceEnded(let losingTeam): score = losingTeam == .blue ? (0, 3) : (3, 0)
        default: return
        }
        attemptedCareerSave = true
        do {
            try onCareerComplete(score.0, score.1)
            careerResultSaved = true
            careerSaveError = nil
        } catch {
            careerSaveError = "Your result could not be saved. \(error.localizedDescription)"
        }
    }

    func startExtraTime() {
        guard isWorldCupMatch, needsExtraTime, tournamentPeriod == .regulation else { return }
        regulationScore = userScore
        needsExtraTime = false
        penaltyShootout = nil
        handledWorldCupPeriodEnd = false
        tournamentPeriod = .extraTime
        let duration = ProcessInfo.processInfo.arguments.contains("--short-match") ? 1.0 : 60.0
        tuning.matchDuration = duration
        scene.startAdditionalPeriod(duration: duration)
        scene.refreshHUD()
    }

    func choosePenalty(_ direction: PenaltyDirection) {
        guard var shootout = penaltyShootout, !shootout.isFinished else { return }
        shootout.choose(direction)
        penaltyShootout = shootout
        if shootout.isFinished { saveWorldCupResult() }
    }

    func saveWorldCupResult() {
        guard isWorldCupMatch, !worldCupResultSaved, let onWorldCupComplete else { return }
        let outcome: WorldCupUserMatchOutcome
        switch hud.phase {
        case .practiceEnded(let losingTeam):
            let userLost = losingTeam == .blue
            outcome = .init(regulationUserGoals: userLost ? 0 : 3,
                            regulationOpponentGoals: userLost ? 3 : 0,
                            userGoals: userLost ? 0 : 3, opponentGoals: userLost ? 3 : 0,
                            wentToExtraTime: false, userPenalties: nil, opponentPenalties: nil,
                            userForfeited: userLost, opponentForfeited: !userLost)
        case .fullTime:
            let score = userScore
            let regulation = regulationScore ?? score
            if worldCupContext?.isKnockout == true, score.user == score.opponent {
                guard let shootout = penaltyShootout, shootout.isFinished else { return }
                outcome = .init(regulationUserGoals: regulation.user,
                                regulationOpponentGoals: regulation.opponent,
                                userGoals: score.user, opponentGoals: score.opponent,
                                wentToExtraTime: true, userPenalties: shootout.userGoals,
                                opponentPenalties: shootout.opponentGoals)
            } else {
                outcome = .init(regulationUserGoals: regulation.user,
                                regulationOpponentGoals: regulation.opponent,
                                userGoals: score.user, opponentGoals: score.opponent,
                                wentToExtraTime: tournamentPeriod == .extraTime,
                                userPenalties: nil, opponentPenalties: nil)
            }
        default: return
        }
        do {
            try onWorldCupComplete(outcome)
            worldCupResultSaved = true
            worldCupSaveError = nil
        } catch {
            worldCupSaveError = "Your result could not be saved. \(error.localizedDescription)"
        }
    }

    private var userScore: (user: Int, opponent: Int) {
        (hud.northGoals, hud.southGoals)
    }

    private func handleWorldCupPeriodEnd() {
        guard isWorldCupMatch, !handledWorldCupPeriodEnd else { return }
        switch hud.phase {
        case .practiceEnded:
            handledWorldCupPeriodEnd = true
            saveWorldCupResult()
        case .fullTime:
            let score = userScore
            if worldCupContext?.isKnockout == true, score.user == score.opponent {
                handledWorldCupPeriodEnd = true
                if tournamentPeriod == .regulation {
                    regulationScore = score
                    needsExtraTime = true
                } else {
                    penaltyShootout = PenaltyShootout(seed: worldCupContext?.shootoutSeed ?? 1)
                }
            } else {
                handledWorldCupPeriodEnd = true
                saveWorldCupResult()
            }
        default: break
        }
    }

#if DEBUG
    func debugAdvanceWorldCupMatch(_ action: WorldCupDebugMatchAction) {
        guard isWorldCupMatch, !worldCupResultSaved else { return }
        worldCupSaveError = nil
        switch action {
        case .win:
            debugFinishWorldCupPeriod(userGoals: 1, opponentGoals: 0)
        case .draw:
            debugFinishWorldCupPeriod(userGoals: 0, opponentGoals: 0)
        case .defeat:
            debugFinishWorldCupPeriod(userGoals: 0, opponentGoals: 1)
        case .extraTime:
            guard worldCupContext?.isKnockout == true else { return }
            debugPrepareTiedRegulation()
            startExtraTime()
        case .penaltyShootout:
            guard worldCupContext?.isKnockout == true else { return }
            if tournamentPeriod == .regulation {
                debugPrepareTiedRegulation()
                startExtraTime()
            }
            penaltyShootout = nil
            handledWorldCupPeriodEnd = false
            debugFinishWorldCupPeriod(userGoals: 0, opponentGoals: 0)
        }
    }

    private func debugPrepareTiedRegulation() {
        tournamentPeriod = .regulation
        regulationScore = nil
        needsExtraTime = false
        penaltyShootout = nil
        handledWorldCupPeriodEnd = false
        debugFinishWorldCupPeriod(userGoals: 0, opponentGoals: 0)
    }

    private func debugFinishWorldCupPeriod(userGoals: Int, opponentGoals: Int) {
        handledWorldCupPeriodEnd = false
        scene.debugFinishMatch(northGoals: userGoals, southGoals: opponentGoals)
    }
#endif

    private func reconcilePause() {
        scene.setGameplayPaused(userPaused || showingSettings || showingHelp || !active)
    }
}

#if DEBUG
enum WorldCupDebugMatchAction: String, CaseIterable, Sendable {
    case win
    case draw
    case defeat
    case extraTime
    case penaltyShootout
}
#endif

extension ExerciseMode {
    static var launchMode: Self {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--solo") { return .solo }
        if arguments.contains("--passing") { return .passing }
        return .match
    }

    var title: String {
        switch self {
        case .solo: "Solo practice"
        case .passing: "Pass & defend"
        case .match: "5v5 match"
        }
    }

    var description: String {
        switch self {
        case .solo: "One player, two empty goals. Practise shooting, chips and first-time touches at your own pace."
        case .passing: "Three blue players against three reds, with empty goals. Practise passing and defending without a match clock."
        case .match: "Four outfield players and a goalkeeper on each side. Saves are automatic; take control when your keeper has the ball. Three minutes of active play; blue attacks north."
        }
    }
}

extension MatchRestartKind {
    var title: String {
        switch self {
        case .kickoff: "Kickoff"
        case .throwIn: "Throw-in"
        case .corner: "Corner"
        case .goalKick: "Goal kick"
        case .freeKick, .offside: "Free kick"
        case .indirectFreeKick: "Indirect free kick"
        case .penalty: "Penalty"
        }
    }
}
