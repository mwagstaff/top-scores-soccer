import SpriteKit

/// Shared wording and normalized values for the HUD and thumb-side power meter.
struct KickPowerFeedback: Equatable {
    let kind: KickPowerKind
    let fraction: Double
    let sweetSpot: ClosedRange<Double>?
    let overhitStart: Double?
    let overcharging: Bool

    var isSweet: Bool { sweetSpot?.contains(fraction) == true && !overcharging }
    var aboveSweet: Bool { sweetSpot.map { fraction > $0.upperBound } == true && !overcharging }
    var title: String {
        switch kind {
        case .shot: overcharging ? "OVERHIT" : isSweet ? "RELEASE NOW" : aboveSweet ? "HIGH POWER" : "SHOT POWER"
        case .throwIn: "THROW DISTANCE"
        case .keeperDistribution: "LONG THROW"
        case .longKick: "HOLD FOR HEIGHT"
        }
    }
    var guidance: String {
        switch kind {
        case .shot: overcharging ? "Too much lift · The shot can sail over"
            : isSweet ? "Release in green for a strong shot"
            : aboveSweet ? "Release soon · More hold adds lift" : "Aim for the green band · Release to shoot"
        case .throwIn: "Hold longer to throw farther · Release to throw"
        case .keeperDistribution: "Hold for a high, long throw · Release to throw"
        case .longKick: "Hold longer to send it high and long · Release to clear"
        }
    }
    var accessibilityValue: String {
        "\(Int((fraction * 100).rounded())) percent. \(guidance)"
    }
}

struct SandboxHUD: Equatable {
    var userIsAway = false
    var homeName = "Blue"
    var awayName = "Red"
    var homeAbbreviation = "BLUE"
    var awayAbbreviation = "RED"
    var selectedPlayerName: String?
    var selectedPlayerRating: Int?
    var northGoals = 0
    var southGoals = 0
    var status = "BALL AT FEET"
    var detail = "Tap to pass into space · Hold for power"
    var fps = 60
    var playerSpeed = 0.0
    var ballSpeed = 0.0
    var ballMode = "controlled"
    var action = "idle"
    var canKick = true
    var charge = 0.0
    var power: KickPowerFeedback?
    var curveTime = 0.0
    var selectedPlayerID = 0
    var passTargetID: Int?
    var possession = "Loose"
    var tackles = 0
    var switches = 0
    var ballHeight = 0.0
    var headers = 0
    var chipWindow = 0.0
    var queuedAction: String?
    var slides = 0
    var fouls = 0
    var card: String?
    var bluePlayers = 3
    var redPlayers = 3
    var phase: SandboxPhase = .playing
    var matchTimeRemaining: Double?

    var scoreboardHomeName: String { userIsAway ? awayName : homeName }
    var scoreboardAwayName: String { userIsAway ? homeName : awayName }
    var scoreboardHomeAbbreviation: String { userIsAway ? awayAbbreviation : homeAbbreviation }
    var scoreboardAwayAbbreviation: String { userIsAway ? homeAbbreviation : awayAbbreviation }
    var scoreboardHomeGoals: Int { userIsAway ? southGoals : northGoals }
    var scoreboardAwayGoals: Int { userIsAway ? northGoals : southGoals }
    var scoreboardHomePlayers: Int { userIsAway ? redPlayers : bluePlayers }
    var scoreboardAwayPlayers: Int { userIsAway ? bluePlayers : redPlayers }

    var clockText: String {
        let seconds = Int(ceil(max(0, matchTimeRemaining ?? 0)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var matchResult: String {
        if case .practiceEnded = phase { return "Match abandoned" }
        if northGoals == southGoals { return "Honours even" }
        return northGoals > southGoals ? "\(homeName) win" : "\(awayName) win"
    }
}

@MainActor
final class GameScene: SKScene {
    private static let cameraTopInset: CGFloat = 170
    // The lower panel includes player identity, status and guidance above the
    // thumb controls. Reserve its full height when framing the ball and receiver.
    private static let cameraBottomInset: CGFloat = 300
    var simulation: FootballSimulation
    var debugEnabled = false
    var onHUDUpdate: ((SandboxHUD) -> Void)?
    var onResetInput: (() -> Void)?
    var onControlFeedback: ((ActionStatus, Bool, Bool) -> Void)?
    var onWhistle: (() -> Void)?
    var onHaptic: ((GameplayHaptic) -> Void)?
    var hapticsEnabled = true {
        didSet { if !hapticsEnabled { haptics.stop() } }
    }
    var soundEnabled = true {
        didSet { if !soundEnabled { whistle.stop() } }
    }
    private(set) var gameplayPaused = false
    private let pitch = PitchRenderer()
    private let clubKits: MatchKits?
    private let userIsAway: Bool
    private let followCamera = CameraController()
    private let cameraNode = SKCameraNode()
    private let receiverEdgeNode = SKNode()
    private let receiverEdgeArrow = SKShapeNode()
    private let receiverEdgeNumber = SKLabelNode(fontNamed: "Menlo-Bold")
    private let receiverEdgeBackground = SKShapeNode(circleOfRadius: 16)
    private let receiverEdgePreview = SKShapeNode()
    private let whistle = WhistlePlayer()
    private let haptics = GameHaptics()
    private var lastFrame: TimeInterval?
    private var heldActionStartedAt: TimeInterval?
    private var lastPhase: SandboxPhase = .playing
    private var accumulator = 0.0
    private var hudElapsed = 0.0
    private var fpsElapsed = 0.0
    private var frameCount = 0
    private var measuredFPS = 60
    private var lastResetGeneration = 0
    private var previousPlayer = PlayerState()
    private var previousFootballers: [Int: PlayerState] = [:]
    private var previousFalls: [Int: Double] = [:]
    private var previousRecoveries: [Int: Double] = [:]
    private var previousDives: [Int: Double] = [:]
    private var previousKeeperReleases: [Int: Double] = [:]
    private var previousHeaders: [Int: Double] = [:]
    private var previousSelectedID = 0
    private var previousBall = BallState()
    private let fixedStep = 1.0 / 60.0

    init(mode: ExerciseMode = .passing, configuration: FriendlyMatchConfiguration? = nil, userIsAway: Bool = false) {
        simulation = FootballSimulation(mode: mode, configuration: configuration)
        self.userIsAway = userIsAway && simulation.configuration != nil
        clubKits = simulation.configuration.map { MatchKits.resolveForPlay(configuration: $0, userIsAway: userIsAway) }
        super.init(size: CGSize(width: 440, height: 956))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.025, green: 0.11, blue: 0.10, alpha: 1)
        pitch.root.yScale = 0.86
        addChild(pitch.root)
        addChild(cameraNode)
        buildReceiverEdgeMarker()
        camera = cameraNode
        isUserInteractionEnabled = false
        pitch.matchKits = clubKits
        resetCamera()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("Use init()") }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        lastFrame = nil
        haptics.attach(to: view)
        if soundEnabled { whistle.prepare() }
        refreshHUD()
    }

    override func willMove(from view: SKView) {
        whistle.stop()
        haptics.detach()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        updateCameraScale()
        cancelTouches()
    }

    func setMovement(_ movement: Vector2, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !gameplayPaused, simulation.phase == .playing else { return }
        if hapticsEnabled, simulation.movement.length < 0.0001, movement.length > 0.0001 { haptics.prepare() }
        // Invert the pitch projection so screen direction remains the aiming direction.
        let magnitude = movement.length
        simulation.updateMovement(Vector2(x: movement.x, y: movement.y / 0.86).normalized * magnitude,
                                  timestamp: timestamp)
    }

    func pressAction(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !gameplayPaused, simulation.phase == .playing else { return }
        heldActionStartedAt = startedAt
        if hapticsEnabled { haptics.prepare() }
        simulation.pressAction(timestamp: startedAt)
        updateControlFeedback()
        refreshHUD()
    }

    func releaseAction(heldFor duration: Double) {
        heldActionStartedAt = nil
        guard !gameplayPaused, simulation.phase == .playing else { return }
        let before = ImpactSnapshot(simulation)
        simulation.releaseAction(heldFor: duration)
        playImpacts(since: before)
        updateControlFeedback()
        refreshHUD()
    }

    func cancelTouches() {
        heldActionStartedAt = nil
        haptics.stop()
        simulation.cancelInput()
        onResetInput?()
        updateControlFeedback()
    }

    func setGameplayPaused(_ paused: Bool) {
        guard gameplayPaused != paused else { return }
        gameplayPaused = paused
        if paused { whistle.stop() }
        cancelTouches()
        accumulator = 0
        lastFrame = nil
        refreshHUD()
    }

    func resetSandbox(clearScore: Bool = false) {
        simulation.reset(clearScore: clearScore)
        resetPresentation()
    }

    func startAdditionalPeriod(duration: Double) {
        simulation.startAdditionalPeriod(duration: duration)
        resetPresentation()
    }

#if DEBUG
    func debugFinishMatch(northGoals: Int, southGoals: Int) {
        simulation.debugFinishMatch(northGoals: northGoals, southGoals: southGoals)
        resetPresentation()
        refreshHUD()
    }
#endif

    private func resetPresentation() {
        whistle.stop()
        lastResetGeneration = simulation.resetGeneration
        lastPhase = simulation.phase
        cancelTouches()
        accumulator = 0
        previousPlayer = simulation.player
        capturePreviousFootballers()
        previousBall = simulation.ball
        resetCamera()
        render(deltaTime: 0)
        refreshHUD()
    }

    func setMode(_ mode: ExerciseMode) {
        guard simulation.mode != mode else { return }
        simulation.setMode(mode)
        resetPresentation()
    }

    private func capturePreviousFootballers() {
        previousFootballers = Dictionary(uniqueKeysWithValues: simulation.footballers.map { ($0.id, $0.state) })
        previousFalls = Dictionary(uniqueKeysWithValues: simulation.footballers.map { ($0.id, $0.fallProgress) })
        previousRecoveries = Dictionary(uniqueKeysWithValues: simulation.footballers.map { ($0.id, $0.recoveryProgress) })
        previousDives = Dictionary(uniqueKeysWithValues: simulation.footballers.map { ($0.id, $0.goalkeeperDiveProgress) })
        previousKeeperReleases = Dictionary(uniqueKeysWithValues: simulation.footballers.map { ($0.id, $0.goalkeeperReleaseProgress) })
        previousHeaders = Dictionary(uniqueKeysWithValues: simulation.footballers.map { ($0.id, $0.headingProgress) })
        previousSelectedID = simulation.selectedPlayerID
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = lastFrame.map { max(0, currentTime - $0) } ?? fixedStep
        lastFrame = currentTime
        frameCount += 1
        fpsElapsed += elapsed
        if fpsElapsed >= 0.5 {
            measuredFPS = Int((Double(frameCount) / fpsElapsed).rounded())
            fpsElapsed = 0
            frameCount = 0
        }
        guard !gameplayPaused else { return }
        if let startedAt = heldActionStartedAt {
            simulation.updateActionHold(heldFor: max(0, ProcessInfo.processInfo.systemUptime - startedAt))
        }
        accumulator += min(elapsed, fixedStep * 6)
        var steps = 0
        while accumulator >= fixedStep && steps < 6 {
            previousPlayer = simulation.player
            capturePreviousFootballers()
            previousBall = simulation.ball
            let before = ImpactSnapshot(simulation)
            simulation.step(dt: fixedStep)
            playImpacts(since: before)
            accumulator -= fixedStep
            steps += 1
            if simulation.phase != lastPhase {
                if simulation.phase == .fullTime {
                    onWhistle?()
                    if soundEnabled, view != nil { whistle.play() }
                }
                if case .restart(let kind, _) = simulation.phase,
                   kind == .offside || kind == .indirectFreeKick {
                    onWhistle?()
                    if soundEnabled, view != nil { whistle.play() }
                }
                if case .foulContact = lastPhase {
                    switch simulation.phase {
                    case .freeKick, .practiceEnded:
                        onWhistle?()
                        if soundEnabled, view != nil { whistle.play() }
                    default: break
                    }
                }
                lastPhase = simulation.phase
                if simulation.phase != .playing {
                    heldActionStartedAt = nil
                    onResetInput?()
                }
            }
            if simulation.resetGeneration != lastResetGeneration {
                lastResetGeneration = simulation.resetGeneration
                onResetInput?()
                heldActionStartedAt = nil
                previousPlayer = simulation.player
                capturePreviousFootballers()
                previousBall = simulation.ball
                resetCamera()
            }
        }
        render(deltaTime: min(elapsed, 0.1))
        updateControlFeedback()
        hudElapsed += elapsed
        if hudElapsed >= 0.1 { hudElapsed = 0; refreshHUD() }
    }

    private struct ImpactSnapshot {
        let kicks: Int
        let challenges: Int
        let fouls: Int
        let generation: Int

        init(_ simulation: FootballSimulation) {
            kicks = simulation.kickCount
            challenges = simulation.challengeContactCount
            fouls = simulation.foulCount
            generation = simulation.resetGeneration
        }
    }

    /// Compare each mutation with its own starting state: release-time kicks and
    /// later queued contact fire once, while resets and cancelled presses stay silent.
    private func playImpacts(since before: ImpactSnapshot) {
        guard hapticsEnabled, !gameplayPaused, before.generation == simulation.resetGeneration else { return }
        let event: GameplayHaptic
        if simulation.foulCount > before.fouls { event = .foul }
        else if simulation.challengeContactCount > before.challenges {
            event = simulation.lastChallengeWasSlide ? .slideContact : .challenge
        } else if simulation.kickCount > before.kicks {
            event = simulation.lastKickKind == "header" ? .pass : simulation.lastKick == .shot ? .shot : .pass
        } else { return }
        onHaptic?(event)
        haptics.play(event)
    }

    private func render(deltaTime: Double) {
        pitch.matchKits = simulation.mode == .match
            ? clubKits : nil
        let alpha = min(1, max(0, accumulator / fixedStep))
        var player = simulation.player
        var ball = simulation.ball
        if previousSelectedID == simulation.selectedPlayerID {
            player.position = previousPlayer.position * (1 - alpha) + player.position * alpha
        }
        ball.position = previousBall.position * (1 - alpha) + ball.position * alpha
        ball.height = previousBall.height * (1 - alpha) + ball.height * alpha
        let footballers = simulation.footballers.map { footballer in
            var interpolated = footballer
            if let previous = previousFootballers[footballer.id] {
                interpolated.state.position = previous.position * (1 - alpha) + footballer.state.position * alpha
            }
            if let previousFall = previousFalls[footballer.id] {
                interpolated.fallProgress = previousFall * (1 - alpha) + footballer.fallProgress * alpha
            }
            if let previousRecovery = previousRecoveries[footballer.id] {
                interpolated.recoveryProgress = previousRecovery * (1 - alpha) + footballer.recoveryProgress * alpha
            }
            if let previousDive = previousDives[footballer.id] {
                interpolated.goalkeeperDiveProgress = previousDive * (1 - alpha) + footballer.goalkeeperDiveProgress * alpha
            }
            if let previousRelease = previousKeeperReleases[footballer.id] {
                interpolated.goalkeeperReleaseProgress = previousRelease * (1 - alpha)
                    + footballer.goalkeeperReleaseProgress * alpha
            }
            if let previousHeader = previousHeaders[footballer.id] {
                interpolated.headingProgress = previousHeader * (1 - alpha) + footballer.headingProgress * alpha
            }
            return interpolated
        }
        pitch.render(footballers: footballers, selectedPlayerID: simulation.selectedPlayerID,
                     passTargetID: simulation.passTargetID,
                     ball: ball, hasControl: simulation.hasControl,
                     chargeFraction: powerFeedback?.fraction ?? simulation.chargeFraction,
                     aftertouchRemaining: simulation.aftertouchRemaining,
                     aftertouchVector: simulation.aftertouchVector,
                     debug: debugEnabled, deltaTime: deltaTime,
                     controlledGoalkeeper: simulation.isControllingGoalkeeper,
                     holdingGoalkeeperID: simulation.goalkeeperHoldingID)
        var cameraBall = ball
        if simulation.phase != .playing,
           let fallen = footballers.first(where: { $0.fallProgress > 0 }) {
            // Keep the visible challenge in frame while the loose ball runs on.
            cameraBall.position = fallen.state.position
            cameraBall.velocity = fallen.state.velocity
            cameraBall.height = 0
        }
        // A keeper's outlet must be visible while aiming, before it becomes the
        // controlled receiver. Framing never changes the selected footballer.
        let previewingKeeperDistribution = simulation.isHoldingGoalkeeper ||
            (simulation.isTakingRestart && simulation.matchRestart?.team == .blue
                && simulation.matchRestart?.kind == .goalKick)
        let previewTargetID = previewingKeeperDistribution ? simulation.passTargetID : nil
        let cameraPlayer = previewTargetID.flatMap { id in footballers.first { $0.id == id }?.state } ?? player
        cameraNode.position = followCamera.update(ball: cameraBall, player: cameraPlayer,
                                                   viewport: size, scale: baseCameraScale,
                                                   tuning: simulation.tuning, deltaTime: deltaTime,
                                                   topInset: Self.cameraTopInset, bottomInset: Self.cameraBottomInset,
                                                   framingReceiver: previewTargetID != nil || simulation.isControllingPassReceiver)
        cameraNode.setScale(followCamera.resolvedScale)
        receiverEdgeNode.isHidden = followCamera.receiverEdgeMarker == nil
        if let marker = followCamera.receiverEdgeMarker {
            let preview = previewTargetID != nil
            let markerID = previewTargetID ?? simulation.selectedPlayerID
            receiverEdgeNode.position = marker.position
            receiverEdgeArrow.zRotation = marker.angle
            receiverEdgePreview.isHidden = !preview
            receiverEdgeBackground.strokeColor = preview ? .clear : SKColor(red: 1, green: 0.87, blue: 0.37, alpha: 1)
            receiverEdgeArrow.fillColor = preview ? receiverEdgePreview.strokeColor : receiverEdgeBackground.strokeColor
            receiverEdgeNumber.text = simulation.roster[markerID].clubPlayer?.jerseyNumber.map(String.init)
                ?? String(markerID + 1)
        }
    }

    private var baseCameraScale: CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let base = CameraController.recommendedScale(viewport: size,
                                                    topInset: Self.cameraTopInset,
                                                    bottomInset: Self.cameraBottomInset)
        // Slightly more width makes the extra midfield and wide passing options legible.
        return base * (simulation.configuration != nil && simulation.mode == .match ? 1.08 : 1)
    }

    private func updateCameraScale() {
        cameraNode.setScale(baseCameraScale)
    }

    private func buildReceiverEdgeMarker() {
        receiverEdgeNode.name = "controlled-receiver-edge"
        receiverEdgeNode.zPosition = 200
        receiverEdgeNode.isHidden = true
        let background = receiverEdgeBackground
        background.fillColor = SKColor(white: 0.04, alpha: 0.88)
        background.strokeColor = SKColor(red: 1, green: 0.87, blue: 0.37, alpha: 1)
        background.lineWidth = 1.5
        receiverEdgeNode.addChild(background)
        let brackets = CGMutablePath()
        for x in [-1.0, 1.0] {
            for y in [-1.0, 1.0] {
                brackets.move(to: CGPoint(x: x * 10, y: y * 16))
                brackets.addLine(to: CGPoint(x: x * 16, y: y * 16))
                brackets.addLine(to: CGPoint(x: x * 16, y: y * 10))
            }
        }
        receiverEdgePreview.name = "receiver-edge-target"
        receiverEdgePreview.path = brackets
        receiverEdgePreview.strokeColor = SKColor(red: 0.49, green: 0.88, blue: 1, alpha: 1)
        receiverEdgePreview.lineWidth = 2
        receiverEdgePreview.isHidden = true
        receiverEdgeNode.addChild(receiverEdgePreview)
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 24, y: 0))
        arrow.addLine(to: CGPoint(x: 16, y: 5))
        arrow.addLine(to: CGPoint(x: 16, y: -5))
        arrow.closeSubpath()
        receiverEdgeArrow.path = arrow
        receiverEdgeArrow.fillColor = background.strokeColor
        receiverEdgeArrow.strokeColor = SKColor(white: 0.04, alpha: 0.88)
        receiverEdgeArrow.lineWidth = 1
        receiverEdgeNode.addChild(receiverEdgeArrow)
        receiverEdgeNumber.fontSize = 12
        receiverEdgeNumber.name = "receiver-edge-number"
        receiverEdgeNumber.fontColor = .white
        receiverEdgeNumber.verticalAlignmentMode = .center
        receiverEdgeNode.addChild(receiverEdgeNumber)
        cameraNode.addChild(receiverEdgeNode)
    }

    private func resetCamera() {
        let point = CGPoint(x: simulation.ball.position.x, y: simulation.ball.position.y * 0.86)
        followCamera.reset(to: point)
        pitch.resetControlFeedback()
        receiverEdgeNode.isHidden = true
        cameraNode.position = point
        updateCameraScale()
    }

    var powerFeedback: KickPowerFeedback? {
        guard !gameplayPaused, simulation.phase == .playing,
              let kind = simulation.powerMeterKind else { return nil }
        let raw = simulation.powerMeterFraction
        let fraction = raw.isFinite ? min(1, max(0, raw)) : 0
        return KickPowerFeedback(kind: kind, fraction: fraction,
                                 sweetSpot: simulation.powerMeterSweetSpot,
                                 overhitStart: kind == .shot ? KickMechanics.shotOverhitStart(tuning: simulation.tuning) : nil,
                                 overcharging: simulation.isOverchargingShot)
    }

    private func updateControlFeedback() {
        onControlFeedback?(simulation.actionStatus, simulation.hasControl,
                           simulation.aftertouchRemaining > 0)
    }

    func refreshHUD() {
        var hud = SandboxHUD()
        hud.userIsAway = userIsAway
        if simulation.mode == .match, let configuration = simulation.configuration {
            hud.homeName = configuration.home.team.shortName ?? configuration.home.team.name
            hud.awayName = configuration.away.team.shortName ?? configuration.away.team.name
            hud.homeAbbreviation = configuration.home.team.scoreboardAbbreviation
            hud.awayAbbreviation = configuration.away.team.scoreboardAbbreviation
            let selected = simulation.roster[simulation.selectedPlayerID].clubPlayer
            hud.selectedPlayerName = selected.map { "\($0.jerseyNumber.map(String.init) ?? "–") · \($0.shortName ?? $0.name)" }
            hud.selectedPlayerRating = selected.map { Int($0.effectiveRating.rounded()) }
        }
        if simulation.isControllingPassReceiver {
            hud.selectedPlayerName = "YOU · \(hud.selectedPlayerName ?? "PLAYER \(simulation.selectedPlayerID + 1)")"
        }
        func sideName(_ team: Team) -> String { team == .blue ? hud.homeName : hud.awayName }
        hud.northGoals = simulation.northGoals
        hud.southGoals = simulation.southGoals
        hud.phase = simulation.phase
        hud.power = powerFeedback
        hud.matchTimeRemaining = simulation.mode == .match ? simulation.matchTimeRemaining : nil
        hud.selectedPlayerID = simulation.selectedPlayerID
        hud.passTargetID = simulation.passTargetID
        hud.possession = simulation.possessionTeam.map(sideName) ?? "Loose"
        hud.tackles = simulation.tackleCount + simulation.runningChallengeCount
        hud.switches = simulation.switchCount
        hud.ballHeight = simulation.ball.height
        hud.headers = simulation.headerCount
        hud.chipWindow = simulation.chipWindowRemaining
        hud.queuedAction = simulation.queuedActionKind
        hud.slides = simulation.slideCount
        hud.fouls = simulation.foulCount
        hud.bluePlayers = simulation.footballers.filter { $0.team == .blue && !$0.isSentOff }.count
        hud.redPlayers = simulation.footballers.filter { $0.team == .red && !$0.isSentOff }.count
        if gameplayPaused {
            hud.status = "PAUSED"
            hud.detail = simulation.mode == .match ? "The match clock is paused." : "Take a breather. Your practice is waiting."
        } else {
            switch simulation.phase {
            case .goal(let north):
                hud.status = "GOAL!"
                hud.detail = north ? "Into the north net. Lovely finish." : "Into the south net. Lovely finish."
            case .outOfPlay:
                hud.status = "OUT OF PLAY"
                hud.detail = "Bringing the ball back to the centre."
            case .restart(let kind, let team):
                if kind == .offside {
                    hud.status = "OFFSIDE"
                    hud.detail = "\(sideName(team)) indirect free kick · Clock paused"
                } else {
                    hud.status = "\(sideName(team).uppercased()) \(kind.title.uppercased())"
                    hud.detail = "Taking positions · Clock paused"
                }
            case .fullTime:
                hud.status = "FULL TIME"
                hud.detail = hud.matchResult
            case .foulContact:
                hud.status = "LATE CHALLENGE"
                hud.detail = "Player goes to ground"
            case .practiceEnded(let losingTeam):
                hud.status = simulation.mode == .match ? "MATCH ABANDONED" : "PRACTICE OVER"
                let team = sideName(losingTeam)
                hud.detail = simulation.mode == .match
                    ? "\(team) has no outfield players left · Start a new match"
                    : "\(team) has no players left · Reset to practise again"
                if simulation.lastFoul?.card == .red { hud.card = "red" }
            case .freeKick(let team):
                let award = simulation.awardedFoulRestartKind == .penalty ? "PENALTY" : "FREE KICK"
                hud.status = "\(sideName(team).uppercased()) \(award)"
                if let foul = simulation.lastFoul {
                    let offender = sideName(team == .blue ? .red : .blue)
                    let identity = simulation.roster[foul.offenderID].clubPlayer.map {
                        "\($0.shortName ?? $0.name)\($0.jerseyNumber.map { " · No. \($0)" } ?? "")"
                    } ?? "\(offender) \(foul.offenderID + 1)"
                    switch foul.card {
                    case .none:
                        hud.detail = "Late challenge by \(identity)"
                    case .yellow:
                        hud.card = "yellow"
                        hud.detail = "Yellow card · \(identity) booked"
                    case .red:
                        hud.card = "red"
                        hud.detail = "Red card · \(identity) sent off"
                    }
                }
            case .playing:
                if let restart = simulation.matchRestart, simulation.isTakingRestart {
                    hud.status = "\(sideName(restart.team).uppercased()) \(restart.kind.title.uppercased())"
                    let automatic = restart.team == .red
                    let targetNumber = simulation.passTargetID.map {
                        simulation.roster[$0].clubPlayer?.jerseyNumber ?? $0 + 1
                    }
                    switch restart.kind {
                    case .offside:
                        hud.detail = automatic ? "Offside · Opposition indirect kick · Clock paused"
                            : "Offside · Indirect kick · Aim and pass to a teammate"
                    case .indirectFreeKick:
                        hud.detail = automatic ? "Opposition indirect kick · Clock paused"
                            : "Indirect kick · Aim and pass to a teammate"
                    case .penalty:
                        hud.detail = automatic ? "Opposition penalty · Clock paused"
                            : "Aim at goal · Tap to shoot or hold for power"
                    case .throwIn:
                        hud.detail = automatic ? "Getting the ball back into play · Clock paused"
                            : targetNumber.map { "Tap to throw to #\($0) · Hold for distance" }
                                ?? "Aim for a nearby teammate · Tap to throw"
                    case .goalKick:
                        hud.detail = automatic ? "Getting the ball back into play · Clock paused"
                            : targetNumber.map { "Tap to pass to #\($0) · Hold for a high kick" }
                                ?? "Aim · Tap to pass · Hold high and long"
                    case .freeKick:
                        hud.detail = automatic ? "Getting the ball back into play · Clock paused"
                            : targetNumber.map { "Tap to pass to #\($0) · Hold for power" }
                                ?? "Aim at a nearby teammate · Tap for a short pass"
                    case .corner, .kickoff:
                        hud.detail = automatic ? "Getting the ball back into play · Clock paused"
                            : "Move the stick to aim · Tap to take it"
                    }
                } else if let keeperTeam = simulation.goalkeeperPossessionTeam {
                    hud.status = "\(sideName(keeperTeam).uppercased()) KEEPER HAS IT"
                    if keeperTeam == .blue {
                        let targetNumber = simulation.passTargetID.map {
                            simulation.roster[$0].clubPlayer?.jerseyNumber ?? $0 + 1
                        }
                        hud.detail = targetNumber.map { "Tap to throw to #\($0) · Hold for a high throw" }
                            ?? "Aim · Tap to throw · Hold high and long"
                    } else {
                        hud.detail = "Get ready for the keeper's throw"
                    }
                } else if simulation.isControllingGoalkeeper &&
                            (simulation.hasControl || simulation.isControllingPassReceiver) {
                    hud.status = simulation.isControllingPassReceiver ? "KEEPER RECEIVING" : "KEEPER AT FEET"
                    hud.detail = simulation.isControllingPassReceiver
                        ? "Move to meet the backpass · Then pass or kick"
                        : "Keeper is vulnerable · Tap to pass or hold to kick"
                } else if let queued = simulation.queuedActionKind {
                    hud.status = queued == "header" ? "HEADER QUEUED" : queued == "shot" ? "POWER KICK QUEUED" : "NEXT TOUCH QUEUED"
                    hud.detail = queued == "header" ? "Aim saved · Move under the ball to meet it" : "Aim saved · Meet the ball to play it first time"
                } else if simulation.isPreparingHeader {
                    hud.status = "PREPARE HEADER"
                    hud.detail = "Aim the stick · Release ACTION to meet the ball"
                } else if simulation.headingPlayerID != nil {
                    hud.status = "HEAD IT"
                    hud.detail = "Aim the stick · Tap ACTION as the ball reaches you"
                } else if simulation.isSliding {
                    hud.status = "SLIDING"
                    hud.detail = "Committed to the challenge · Ball first"
                } else if simulation.isTakingFreeKick {
                    hud.status = "\(hud.homeName.uppercased()) FREE KICK"
                    hud.detail = simulation.passTargetID.map {
                        "Tap to pass to #\(simulation.roster[$0].clubPlayer?.jerseyNumber ?? $0 + 1) · Hold for power"
                    } ?? "Aim at a nearby teammate · Tap for a short pass"
                } else if simulation.isPreparingReceivingKick {
                    hud.status = simulation.actionStatus == .charging ? "CHARGING NEXT KICK" : "PREPARE YOUR TOUCH"
                    hud.detail = "Aim, then release · Your kick waits for the ball"
                } else if simulation.isControllingPassReceiver {
                    hud.status = "CONTROL THE RECEIVER"
                    hud.detail = "Steer to move · Centre to meet the ball"
                } else if simulation.canPrepareReceivingKick {
                    hud.status = "BALL INCOMING"
                    hud.detail = "Aim and tap to prepare · Hold for a powerful kick"
                } else if simulation.aftertouchRemaining > 0 {
                    hud.status = "BEND IT"
                    hud.detail = "Steer sideways to swerve the ball"
                } else if simulation.chipWindowRemaining > 0 {
                    hud.status = "PULL BACK TO CHIP"
                    hud.detail = "A quick backsweep lifts the ball · Time it tightly"
                } else if simulation.ball.height > 0.2 {
                    hud.status = "BALL IN THE AIR"
                    hud.detail = "Watch the shadow for the landing spot"
                } else if simulation.actionStatus == .charging {
                    hud.status = "CHARGING"
                    hud.detail = "Aim towards goal to shoot · Release to strike"
                } else if simulation.actionStatus == .tackling {
                    hud.status = "CHALLENGING"
                    hud.detail = "Keep your eye on the ball"
                } else if simulation.actionStatus == .recovering {
                    hud.status = "RECOVERING"
                    hud.detail = "A missed tackle leaves you exposed"
                } else if simulation.hasControl {
                    hud.status = "BALL AT FEET"
                    if let target = simulation.passTargetID {
                        let number = simulation.roster[target].clubPlayer?.jerseyNumber ?? target + 1
                        hud.detail = "Tap to pass to #\(number) · Hold for power"
                    } else {
                        hud.detail = "Tap into space · Hold for power"
                    }
                } else if simulation.isPressingFromBehind {
                    hud.status = "KEEP PRESSING"
                    hud.detail = "Stay close or move around to the ball"
                } else if simulation.mode != .solo {
                    hud.status = simulation.possessionTeam == .red ? "WIN IT BACK" : "MEET THE BALL"
                    hud.detail = simulation.possessionTeam == .red
                        ? "Steer to select and close down · Hold to slide"
                        : "Steer to select and meet the ball · Tap to prepare"
                } else {
                    hud.status = "CHASE IT DOWN"
                    hud.detail = "Tap to queue a pass · Hold to slide for the ball"
                }
            }
        }
        if let power = hud.power {
            hud.status = simulation.isTakingPenalty ? "PENALTY · \(power.title)" : power.title
            hud.detail = simulation.matchRestart?.kind == .offside || simulation.matchRestart?.kind == .indirectFreeKick
                ? "Indirect kick · Another player must touch before a goal" : power.guidance
        }
        hud.fps = measuredFPS
        hud.playerSpeed = simulation.player.velocity.length
        hud.ballSpeed = simulation.ball.velocity.length
        hud.ballMode = simulation.ball.mode.rawValue
        hud.action = simulation.actionStatus.rawValue
        hud.canKick = simulation.canKick
        hud.charge = simulation.chargeFraction
        hud.curveTime = simulation.aftertouchRemaining
        onHUDUpdate?(hud)
    }
}
