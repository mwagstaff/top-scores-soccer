import UIKit

@MainActor
private final class FootballActionElement: UIAccessibilityElement {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}

/// Tracks each thumb independently. UIKit timestamps determine tap/hold duration.
@MainActor
final class InputController: UIView {
    weak var scene: GameScene?
    private var movementTouch: UITouch?
    private var movementNeedsSync = false
    private var actionTouch: UITouch?
    private var pressedButton: PlayerActionButton?
    private var actionStartedAt = 0.0
    private(set) var joystickOrigin: CGPoint?
    private(set) var joystickOffset = CGPoint.zero
    private var previousBounds: CGRect?
    private var previousSafeAreaInsets: UIEdgeInsets?
    private var status: ActionStatus = .idle
    private var hasBall = true
    private var curving = false
    private var opponentHasBall = false
    private var canSwitch = false
    private var canReceive = false
    private var controllingReceiver = false
    private var canHead = false
    private var preparingHeader = false
    private var queuedHeader = false
    private var canCross = false
    private var incomingCross = false
    private var waitingForAutomaticPlay = false
    private var holdingKeeper = false
    private var controllingKeeper = false
    private var takingThrowIn = false
    private var takingGoalKick = false
    private var takingPenalty = false
    private var power: KickPowerFeedback?
    private let stickRadius: CGFloat = 52
    private var actionRadius: CGFloat { min(47, max(36, bounds.width * 0.12)) }
    private var controlLift: CGFloat { min(32, max(24, bounds.height * 0.03)) }
    private var actionElement: UIAccessibilityElement!
    private var passElement: UIAccessibilityElement!
    private var joystickElement: UIAccessibilityElement!
    private var powerElement: UIAccessibilityElement!
    private var standardActionHint: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        accessibilityIdentifier = "sandbox.surface"
        let shootingElement = FootballActionElement(accessibilityContainer: self)
        shootingElement.activate = { [weak self] in self?.activateButton(.shoot, heldFor: 0.08) ?? false }
        actionElement = shootingElement
        actionElement.accessibilityLabel = "Shoot or long pass"
        actionElement.accessibilityHint = "Within 35 metres of goal, tap to shoot or hold and release for power. Outside that range, hold and release for a long pass or cross. Off the ball, press to slide tackle. When receiving, prepare a shot or header."
        actionElement.accessibilityIdentifier = "sandbox.action"
        standardActionHint = actionElement.accessibilityHint
        actionElement.accessibilityTraits = .button
        let passingElement = FootballActionElement(accessibilityContainer: self)
        passingElement.activate = { [weak self] in self?.activateButton(.pass) ?? false }
        passElement = passingElement
        passElement.accessibilityLabel = "Short pass or block tackle"
        passElement.accessibilityHint = "Press to play a short ground pass in the joystick direction. Off the ball, press for a standing block tackle. When receiving, prepare a first-time pass or header pass."
        passElement.accessibilityIdentifier = "sandbox.pass"
        passElement.accessibilityTraits = .button
        joystickElement = UIAccessibilityElement(accessibilityContainer: self)
        joystickElement.accessibilityLabel = "Movement joystick"
        joystickElement.accessibilityHint = "Touch anywhere on the left side of the pitch, then drag to move and aim. Each new touch centres the joystick under your thumb. Off the ball, your direction automatically selects a nearby player to reach the ball or block its carrier. Run into an opponent's ball from the front or side to win it. From behind, stay close and keep pressing. Steer sideways after shooting to bend the ball, or quickly pull opposite your kick to chip it."
        joystickElement.accessibilityIdentifier = "sandbox.joystick"
        joystickElement.accessibilityTraits = .allowsDirectInteraction
        powerElement = UIAccessibilityElement(accessibilityContainer: self)
        powerElement.accessibilityIdentifier = "sandbox.power"
        powerElement.accessibilityTraits = [.staticText, .updatesFrequently]
        accessibilityElements = [joystickElement!, passElement!, actionElement!]
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private var restingStick: CGPoint {
        CGPoint(x: max(safeAreaInsets.left + 86, bounds.width * 0.14),
                y: bounds.height - max(safeAreaInsets.bottom + 76, 88))
    }
    private var actionColumnX: CGFloat {
        bounds.width - max(safeAreaInsets.right + 56, bounds.width * 0.14)
    }

    private var passCenter: CGPoint {
        CGPoint(x: actionColumnX - actionRadius * 2 - 16, y: restingStick.y - 10 - controlLift)
    }

    private var actionCenter: CGPoint {
        // Stagger the A/B-style cluster without moving the short-pass button.
        CGPoint(x: actionColumnX, y: passCenter.y - actionRadius * 2 * 0.30)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateControlLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateControlLayout()
    }

    private func updateControlLayout() {
        let changed = previousBounds != nil && (previousBounds != bounds || previousSafeAreaInsets != safeAreaInsets)
        previousBounds = bounds
        previousSafeAreaInsets = safeAreaInsets
        if changed, joystickOrigin != nil || actionTouch != nil {
            // A relayout must not reinterpret an old thumb position or release a held kick.
            scene?.cancelTouches()
            clearTouches()
        }
        updateAccessibilityFrames()
        setNeedsDisplay()
    }

    private func updateAccessibilityFrames() {
        guard let actionElement, let joystickElement else { return }
        actionElement.accessibilityFrameInContainerSpace = CGRect(x: actionCenter.x - actionRadius,
                                                                  y: actionCenter.y - actionRadius,
                                                                  width: actionRadius * 2, height: actionRadius * 2)
        passElement.accessibilityFrameInContainerSpace = CGRect(x: passCenter.x - actionRadius,
            y: passCenter.y - actionRadius, width: actionRadius * 2, height: actionRadius * 2)
        let origin = joystickOrigin ?? restingStick
        joystickElement.accessibilityFrameInContainerSpace = CGRect(x: origin.x - stickRadius,
                                                                    y: origin.y - stickRadius,
                                                                    width: stickRadius * 2, height: stickRadius * 2)
            .intersection(bounds)
        joystickElement.accessibilityValue = joystickOrigin == nil ? "Ready: touch and drag on the left" : "Joystick active"
        powerElement?.accessibilityFrameInContainerSpace = powerFrame
    }

    func clearTouches() {
        movementTouch = nil
        movementNeedsSync = false
        actionTouch = nil
        pressedButton = nil
        actionStartedAt = 0
        joystickOrigin = nil
        joystickOffset = .zero
        scene?.setMovement(.zero)
        status = .idle
        power = nil
        accessibilityElements = [joystickElement!, passElement!, actionElement!]
        updateAccessibilityFrames()
        setNeedsDisplay()
    }

    /// Match-state transitions cancel simulation input, but UIKit keeps delivering
    /// the same still-down touch. Preserve the movement thumb so a free kick or
    /// restart can resume aiming without requiring the player to lift and re-press.
    func sceneDidResetInput() {
        guard scene?.gameplayPaused != true else {
            clearTouches()
            return
        }
        actionTouch = nil
        pressedButton = nil
        actionStartedAt = 0
        status = .idle
        power = nil
        accessibilityElements = [joystickElement!, passElement!, actionElement!]
        if joystickOrigin != nil {
            movementNeedsSync = true
            restoreHeldMovementIfPossible()
        } else {
            movementTouch = nil
            joystickOffset = .zero
            scene?.setMovement(.zero)
        }
        updateAccessibilityFrames()
        setNeedsDisplay()
    }

    func feedback(status: ActionStatus, hasBall: Bool, curving: Bool) {
        let canSwitch = scene?.simulation.canSwitchToNearestPlayer == true
        let canReceive = scene?.simulation.canPrepareReceivingKick == true || scene?.simulation.isPreparingReceivingKick == true
        let controllingReceiver = scene?.simulation.isControllingPassReceiver == true
        let canHead = scene?.simulation.headingPlayerID != nil
        let preparingHeader = scene?.simulation.isPreparingHeader == true
        let queuedHeader = scene?.simulation.queuedActionKind == "header"
        let canCross = scene?.simulation.canCross == true
        let incomingCross = scene?.simulation.isCrossInFlight == true && scene?.simulation.lastTouchTeam == .blue
        let automaticRestart = scene?.simulation.isTakingRestart == true && scene?.simulation.matchRestart?.team == .red
        let waitingForAutomaticPlay = scene?.simulation.goalkeeperPossessionTeam == .red || automaticRestart
        let holdingKeeper = scene?.simulation.isHoldingGoalkeeper == true
        let controllingKeeper = scene?.simulation.isControllingGoalkeeper == true
        let takingThrowIn = scene?.simulation.isTakingRestart == true && scene?.simulation.matchRestart?.kind == .throwIn
        let takingGoalKick = scene?.simulation.isTakingRestart == true && scene?.simulation.matchRestart?.kind == .goalKick
        let takingPenalty = scene?.simulation.isTakingPenalty == true && scene?.simulation.matchRestart?.team == .blue
        let power = scene?.powerFeedback
        if let power {
            powerElement.accessibilityLabel = power.title
            powerElement.accessibilityValue = power.accessibilityValue
        }
        if (power != nil) != (self.power != nil) {
            accessibilityElements = power != nil ? [joystickElement!, powerElement!, passElement!, actionElement!]
                : [joystickElement!, passElement!, actionElement!]
        }
        actionElement.accessibilityTraits = waitingForAutomaticPlay ? [.button, .notEnabled] : .button
        passElement.accessibilityTraits = waitingForAutomaticPlay || takingPenalty ? [.button, .notEnabled] : .button
        actionElement.accessibilityHint = standardActionHint
        if let scene, ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let sim = scene.simulation
            let rosterDetails = "keepers:\(sim.footballers.filter { $0.isGoalkeeper }.count);selectedKeeper:\(sim.footballers[sim.selectedPlayerID].isGoalkeeper);"
            let shortOptionsReady = sim.restartShortOutletIDs.filter { id in
                let player = sim.footballers[id].state
                return (player.position - sim.ball.position).length <= 9
                    && player.velocity.length < 0.5
            }.count
            let diagnostics: [String] = [
                "lastKick:\(sim.lastKick?.rawValue ?? "none");kicks:\(sim.kickCount);",
                String(format: "player:%.2f,%.2f;", sim.player.position.x, sim.player.position.y),
                "mode:\(sim.mode.rawValue);players:\(sim.footballers.count);selected:\(sim.selectedPlayerID);",
                "target:\(sim.passTargetID.map(String.init) ?? "none");receiverControl:\(sim.isControllingPassReceiver);",
                "shortTarget:\(sim.shortPassTargetID.map(String.init) ?? "none");",
                rosterDetails,
                "restart:\(sim.matchRestart?.kind.rawValue ?? "none");restartReady:\(sim.isTakingRestart);",
                "attacksTopGoal:\(sim.ends.blueAttacksNorth);",
                "penaltyReady:\(sim.isTakingPenalty);freeKickReady:\(sim.isTakingFreeKick);",
                "shortOptionsReady:\(shortOptionsReady);",
                "tackles:\(sim.tackleCount);running:\(sim.runningChallengeCount);switches:\(sim.switchCount);",
                "slides:\(sim.slideCount);standing:\(sim.standingTackleCount);queue:\(sim.queuedActionKind ?? "none");fouls:\(sim.foulCount);canSwitch:\(sim.canSwitchToNearestPlayer);",
                "kickKind:\(sim.lastKickKind ?? "none");receiving:\(canReceive);",
                "canHead:\(canHead);preparingHeader:\(preparingHeader);headers:\(sim.headerCount);headerPlayer:\(sim.lastHeaderPlayerID.map(String.init) ?? "none");",
                "canCross:\(canCross);crossInFlight:\(sim.isCrossInFlight);crosses:\(sim.crossCount);",
                String(format: "chipWindow:%.2f;height:%.2f;", sim.chipWindowRemaining, sim.ball.height),
                "keeperHands:\(holdingKeeper);keeperControl:\(controllingKeeper);power:\(power?.title ?? "none");powerKind:\(sim.powerMeterKind?.rawValue ?? "none");",
                String(format: "powerFraction:%.2f;overhit:%@;", power?.fraction ?? 0, sim.isOverchargingPower ? "true" : "false")
            ]
            actionElement.accessibilityValue = diagnostics.joined()
        } else {
            actionElement.accessibilityValue = power?.accessibilityValue
        }
        let opponentHasBall = scene?.simulation.possessionTeam == .red
        self.status = status
        self.hasBall = hasBall
        self.curving = curving
        self.opponentHasBall = opponentHasBall
        self.canSwitch = canSwitch
        self.canReceive = canReceive
        self.controllingReceiver = controllingReceiver
        self.canHead = canHead
        self.preparingHeader = preparingHeader
        self.queuedHeader = queuedHeader
        self.canCross = canCross
        self.incomingCross = incomingCross
        self.waitingForAutomaticPlay = waitingForAutomaticPlay
        self.holdingKeeper = holdingKeeper
        self.controllingKeeper = controllingKeeper
        self.takingThrowIn = takingThrowIn
        self.takingGoalKick = takingGoalKick
        self.takingPenalty = takingPenalty
        self.power = power
        restoreHeldMovementIfPossible()
        actionElement.accessibilityCustomActions = (hasBall || canReceive) && !waitingForAutomaticPlay
            ? [("Low power kick", 0.25), ("Medium power kick", 0.55), ("High power kick", 0.85)].map { name, fraction in
                UIAccessibilityCustomAction(name: name) { [weak self] _ in
                    guard let self else { return false }
                    return self.activateButton(.shoot, heldFor: fraction * (self.scene?.simulation.tuning.shotChargeDuration ?? 0.95))
                }
            } : nil
        actionElement.accessibilityLabel = takingPenalty ? "Take penalty"
            : canHead || preparingHeader || queuedHeader ? "Head ball"
            : actionTitle == "CROSS" ? "Cross ball" : actionTitle.capitalized
        actionElement.accessibilityHint = takingPenalty
            ? "Aim with the joystick. Tap SHOOT, or hold and release in the green power band."
            : incomingCross ? "Tap as the cross reaches your attacker to head towards goal. Press HEAD PASS for a directional header pass."
            : actionTitle == "CROSS" ? "Hold and release in green to cross automatically towards your runners. Press PASS for a short ground pass."
            : standardActionHint
        if !ProcessInfo.processInfo.arguments.contains("--uitesting"), power == nil {
            actionElement.accessibilityValue = waitingForAutomaticPlay ? "Opposition restarting; move into position"
                : takingGoalKick ? "Your keeper is taking a goal kick. SHORT PASS plays short; hold LONG PASS for distance."
                : holdingKeeper ? "Your keeper has the ball. SHORT THROW finds a nearby teammate; hold LONG THROW for distance."
                : controllingReceiver ? "You control the intended receiver. Steer to move, or centre to meet the ball. SHORT PASS or SHOOT prepares the next touch."
                : canReceive ? "Incoming ball. SHORT PASS or SHOOT prepares your next touch."
                : hasBall ? "SHORT PASS plays short. Hold the other action button for power, then release."
                : "Press BLOCK for a standing tackle or SLIDE for a sliding tackle."
        }
        passElement.accessibilityLabel = passTitle.capitalized
        passElement.accessibilityValue = takingPenalty ? "Unavailable during penalties" : nil
        updateAccessibilityFrames()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let scene, !scene.gameplayPaused else { return }
        for touch in touches {
            let point = touch.location(in: self)
            switch touchRole(at: point) {
            case .action where actionTouch == nil:
                beginActionTouch(touch, button: .shoot)
            case .pass where actionTouch == nil:
                beginActionTouch(touch, button: .pass)
            case .movement where beginMovement(at: point, timestamp: touch.timestamp):
                movementTouch = touch
            default:
                break
            }
        }
        setNeedsDisplay()
    }

    private func beginActionTouch(_ touch: UITouch, button: PlayerActionButton) {
        guard scene?.simulation.phase == .playing,
              !waitingForAutomaticPlay, button != .pass || !takingPenalty else { return }
        actionTouch = touch
        pressedButton = button
        actionStartedAt = touch.timestamp
        scene?.pressAction(button: button, startedAt: touch.timestamp)
    }

    private func activateButton(_ button: PlayerActionButton, heldFor duration: Double = 0) -> Bool {
        guard let scene, !scene.gameplayPaused, scene.simulation.phase == .playing,
              actionTouch == nil, !waitingForAutomaticPlay, button != .pass || !takingPenalty else { return false }
        scene.pressAction(button: button)
        if button == .shoot { scene.releaseAction(heldFor: duration) }
        return true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === movementTouch {
                moveMovement(to: touch.location(in: self), timestamp: touch.timestamp)
            } else if movementTouch == nil {
                let point = touch.location(in: self)
                if beginMovement(at: point, timestamp: touch.timestamp) {
                    movementTouch = touch
                    moveMovement(to: point, timestamp: touch.timestamp)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Release ACTION before clearing movement when both thumbs lift in the same event.
        for touch in touches where touch === actionTouch {
            if pressedButton == .shoot { scene?.releaseAction(heldFor: max(0, touch.timestamp - actionStartedAt)) }
            actionTouch = nil
            pressedButton = nil
            actionStartedAt = 0
        }
        for touch in touches where touch === movementTouch {
            endMovement(timestamp: touch.timestamp)
        }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        scene?.cancelTouches()
        clearTouches()
    }

    enum TouchRole: Equatable { case movement, action, pass }

    /// Native toolbar controls sit above this view. The left half is always the
    /// movement surface; action buttons own their hit areas on the right half.
    func touchRole(at point: CGPoint) -> TouchRole? {
        guard bounds.contains(point) else { return nil }
        if point.x < bounds.midX { return .movement }
        if hypot(point.x - actionCenter.x, point.y - actionCenter.y) <= actionRadius + 7 { return .action }
        if hypot(point.x - passCenter.x, point.y - passCenter.y) <= actionRadius + 7 { return .pass }
        return nil
    }

    @discardableResult
    func beginMovement(at point: CGPoint, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard joystickOrigin == nil, touchRole(at: point) == .movement,
              let scene, !scene.gameplayPaused else { return false }
        joystickOrigin = point
        joystickOffset = .zero
        applyCurrentMovement(timestamp: timestamp)
        updateAccessibilityFrames()
        setNeedsDisplay()
        return true
    }

    func moveMovement(to point: CGPoint, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let origin = joystickOrigin else { return }
        let offset = Vector2(x: point.x - origin.x, y: point.y - origin.y).clampedLength(stickRadius)
        joystickOffset = CGPoint(x: offset.x, y: offset.y)
        applyCurrentMovement(timestamp: timestamp)
        setNeedsDisplay()
    }

    private var currentMovement: Vector2 {
        let offset = Vector2(x: joystickOffset.x, y: joystickOffset.y)
        let length = offset.length / stickRadius
        let deadZone = min(0.95, max(0, scene?.simulation.tuning.joystickDeadZone ?? 0.12))
        let magnitude = max(0, (length - deadZone) / (1 - deadZone))
        return Vector2(x: offset.x, y: -offset.y).normalized * magnitude
    }

    private func applyCurrentMovement(timestamp: TimeInterval) {
        guard let scene else { return }
        if !scene.gameplayPaused, scene.simulation.phase == .playing {
            scene.setMovement(currentMovement, timestamp: timestamp)
            movementNeedsSync = false
        } else {
            movementNeedsSync = true
        }
    }

    private func restoreHeldMovementIfPossible() {
        guard movementNeedsSync, joystickOrigin != nil else { return }
        applyCurrentMovement(timestamp: ProcessInfo.processInfo.systemUptime)
    }

    func endMovement(timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        movementTouch = nil
        movementNeedsSync = false
        joystickOrigin = nil
        joystickOffset = .zero
        scene?.setMovement(.zero, timestamp: timestamp)
        updateAccessibilityFrames()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let accent = UIColor(red: 0.86, green: 0.98, blue: 0.60, alpha: 1)
        if let origin = joystickOrigin {
            context.setFillColor(UIColor(white: 0.02, alpha: 0.28).cgColor)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.48).cgColor)
            context.setLineWidth(1.5)
            context.addEllipse(in: CGRect(x: origin.x - stickRadius, y: origin.y - stickRadius,
                                         width: stickRadius * 2, height: stickRadius * 2))
            context.drawPath(using: .fillStroke)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor)
            context.addEllipse(in: CGRect(x: origin.x - 34, y: origin.y - 34, width: 68, height: 68))
            context.strokePath()
            let thumb = CGPoint(x: origin.x + joystickOffset.x, y: origin.y + joystickOffset.y)
            context.setFillColor((curving ? accent : .white).withAlphaComponent(0.66).cgColor)
            context.fillEllipse(in: CGRect(x: thumb.x - 21, y: thumb.y - 21, width: 42, height: 42))
            drawText(curving ? "CURVE" : "MOVE", at: CGPoint(x: origin.x, y: origin.y + 64), size: 10, color: .white.withAlphaComponent(0.72))
        } else {
            drawText("TOUCH & DRAG", at: CGPoint(x: restingStick.x, y: restingStick.y + 64), size: 9,
                     color: .white.withAlphaComponent(0.50))
        }

        drawActionButton(title: actionTitle, symbolName: actionIconName,
                         center: actionCenter, button: .shoot, context: context)
        drawActionButton(title: passTitle, symbolName: passIconName,
                         center: passCenter, button: .pass, context: context)
        if let power { drawPower(power, in: context) }
    }

    private func drawActionButton(title: String, symbolName: String, center: CGPoint,
                                  button: PlayerActionButton, context: CGContext) {
        let pressed = actionTouch != nil && pressedButton == button
        let disabled = waitingForAutomaticPlay || (button == .pass && takingPenalty)
        let color: UIColor = button == .shoot ? (power?.tint ?? UIColor(red: 1, green: 0.80, blue: 0.40, alpha: 1))
            : UIColor(red: 0.62, green: 0.91, blue: 1, alpha: 1)
        // Twenty percent less opacity keeps both controls readable without
        // obscuring as much of the pitch beneath the player's thumbs.
        context.setFillColor(UIColor(white: 0.025, alpha: pressed ? 0.64 : 0.44).cgColor)
        context.setStrokeColor(color.withAlphaComponent(disabled ? 0.25 : 0.9).cgColor)
        context.setLineWidth(pressed ? 3 : 1.5)
        context.addEllipse(in: CGRect(x: center.x - actionRadius, y: center.y - actionRadius,
                                     width: actionRadius * 2, height: actionRadius * 2))
        context.drawPath(using: .fillStroke)
        if pressed {
            context.setFillColor(color.withAlphaComponent(0.18).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - actionRadius, y: center.y - actionRadius,
                                           width: actionRadius * 2, height: actionRadius * 2))
        }
        drawSymbol(named: disabled ? "pause.fill" : symbolName, at: center,
                   size: pressed ? actionRadius * 0.78 : actionRadius * 0.86,
                   color: color.withAlphaComponent(disabled ? 0.35 : 1))
        drawButtonLabel(disabled ? "WAIT" : title,
                        at: CGPoint(x: center.x, y: center.y + actionRadius + 11),
                        color: disabled ? UIColor.white.withAlphaComponent(0.45) : color)
    }

    var passTitle: String {
        if holdingKeeper || takingThrowIn { return "SHORT THROW" }
        if takingPenalty { return "PASS" }
        if preparingHeader || canHead { return "HEAD PASS" }
        if hasBall || canReceive || takingGoalKick { return "SHORT PASS" }
        return "BLOCK"
    }

    var actionTitle: String {
        if actionTouch != nil && status == .cancelled { return "RELEASE" }
        if holdingKeeper || takingThrowIn { return "LONG THROW" }
        if takingGoalKick { return "LONG PASS" }
        if takingPenalty { return "SHOOT" }
        if queuedHeader { return "HEADER" }
        if preparingHeader || canHead { return "HEAD" }
        if status == .sliding { return "SLIDE" }
        if !hasBall && !canReceive { return "SLIDE" }
        switch scene?.simulation.shootingButtonIntent {
        case .shot: return "SHOOT"
        case .cross: return "CROSS"
        default: return "LONG PASS"
        }
    }

    var passIconName: String {
        if waitingForAutomaticPlay || takingPenalty { return "pause.fill" }
        if holdingKeeper || takingThrowIn { return "hand.raised.fill" }
        if preparingHeader || canHead { return "arrow.right" }
        if hasBall || canReceive || takingGoalKick { return "arrow.right" }
        return "shield.fill"
    }

    var actionIconName: String {
        if waitingForAutomaticPlay { return "pause.fill" }
        if actionTouch != nil && status == .cancelled { return "hand.raised.fill" }
        if holdingKeeper || takingThrowIn { return "hand.raised.fill" }
        if takingGoalKick { return "arrow.up" }
        if takingPenalty { return "scope" }
        if queuedHeader || preparingHeader || canHead { return "person.crop.circle" }
        if status == .sliding || (!hasBall && !canReceive) { return "figure.soccer" }
        switch scene?.simulation.shootingButtonIntent {
        case .shot: return "scope"
        case .cross: return "arrow.up.right"
        default: return "arrow.up"
        }
    }

    private var powerFrame: CGRect {
        let width = min(176, bounds.width * 0.44)
        return CGRect(x: min(bounds.width - safeAreaInsets.right - width - 12, actionCenter.x - width / 2),
                      y: actionCenter.y - actionRadius - 48, width: width, height: 32)
    }

    private func drawPower(_ power: KickPowerFeedback, in context: CGContext) {
        let frame = powerFrame
        let track = CGRect(x: frame.minX, y: frame.maxY - 11, width: frame.width, height: 10)
        let green = UIColor(red: 0.47, green: 0.96, blue: 0.44, alpha: 1)
        let red = UIColor(red: 1, green: 0.36, blue: 0.30, alpha: 1)
        let amber = UIColor(red: 1, green: 0.78, blue: 0.30, alpha: 1)
        let color = power.tint
        context.setFillColor(UIColor(white: 0.025, alpha: 0.9).cgColor)
        context.fill(frame.insetBy(dx: -7, dy: -5))
        context.setFillColor(UIColor.white.withAlphaComponent(0.2).cgColor)
        context.fill(track)
        context.setFillColor(color.withAlphaComponent(0.6).cgColor)
        context.fill(CGRect(x: track.minX, y: track.minY, width: track.width * power.fraction, height: track.height))
        if let sweet = power.sweetSpot {
            let low = CGFloat(min(1, max(0, sweet.lowerBound)))
            let high = CGFloat(min(1, max(Double(low), sweet.upperBound)))
            context.setFillColor(green.withAlphaComponent(0.95).cgColor)
            context.fill(CGRect(x: track.minX + track.width * low, y: track.minY,
                                width: track.width * (high - low), height: track.height))
            let overhit = CGFloat(min(1, max(Double(high), power.overhitStart ?? 1)))
            context.setFillColor(amber.withAlphaComponent(0.75).cgColor)
            context.fill(CGRect(x: track.minX + track.width * high, y: track.minY,
                                width: track.width * (overhit - high), height: track.height))
            context.setFillColor(red.withAlphaComponent(0.75).cgColor)
            context.fill(CGRect(x: track.minX + track.width * overhit, y: track.minY,
                                width: track.width * (1 - overhit), height: track.height))
        }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.75).cgColor)
        context.setLineWidth(1)
        context.stroke(track)
        // A white notch identifies actual power even across the coloured bands.
        let x = track.minX + track.width * power.fraction
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: min(track.maxX - 2, max(track.minX, x - 1)), y: track.minY - 3, width: 3, height: 16))
        drawText(power.title, at: CGPoint(x: frame.midX, y: frame.minY + 5), size: 10,
                 color: power.overcharging || power.isSweet || power.aboveSweet ? color : .white)
    }

    private func drawText(_ text: String, at center: CGPoint, size: CGFloat, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: color, .kern: 1.1
        ]
        let dimensions = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: center.x - dimensions.width / 2,
                                          y: center.y - dimensions.height / 2), withAttributes: attributes)
    }

    private func drawSymbol(named name: String, at center: CGPoint, size: CGFloat, color: UIColor) {
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold, scale: .medium)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else {
            drawText("●", at: center, size: size * 0.72, color: color)
            return
        }
        let dimensions = image.size
        image.draw(at: CGPoint(x: center.x - dimensions.width / 2,
                               y: center.y - dimensions.height / 2))
    }

    private func drawButtonLabel(_ text: String, at center: CGPoint, color: UIColor) {
        let baseFont = UIFont.systemFont(ofSize: text.count > 9 ? 9 : 10, weight: .heavy)
        let font = baseFont.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: baseFont.pointSize) }
            ?? baseFont
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: 0.8,
            .shadow: shadow
        ]
        let dimensions = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: center.x - dimensions.width / 2,
                                            y: center.y - dimensions.height / 2),
                                withAttributes: attributes)
    }
}
