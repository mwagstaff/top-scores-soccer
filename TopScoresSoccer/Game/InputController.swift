import UIKit

/// Tracks each thumb independently. UIKit timestamps determine tap/hold duration.
@MainActor
final class InputController: UIView {
    weak var scene: GameScene?
    private var movementTouch: UITouch?
    private var actionTouch: UITouch?
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
    private let actionRadius: CGFloat = 47
    private var actionElement: UIAccessibilityElement!
    private var joystickElement: UIAccessibilityElement!
    private var powerElement: UIAccessibilityElement!
    private var standardActionHint: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        accessibilityIdentifier = "sandbox.surface"
        actionElement = UIAccessibilityElement(accessibilityContainer: self)
        actionElement.accessibilityLabel = "Action"
        actionElement.accessibilityHint = "Aim and tap to pass to a teammate or into space. In defence, hold and release for a high, long clearance. Near goal with no nearby pass, aim towards goal and tap to shoot. Hold for more power, releasing in the green shot band before the red overhit region. On the attacking wing, hold to cross automatically towards your runners; release in green. Tap as your cross reaches an attacker to head towards goal. For other high balls, aim the joystick and tap to head it. With the keeper holding the ball, tap to throw to the highlighted teammate or hold for a high, long throw. For a goal kick, tap to pass to the highlighted teammate or hold for a high, long kick. Hold throw-ins for more distance. Before an incoming ball arrives, tap or hold and release to prepare your next kick. Off the ball, the joystick automatically selects a player for your intended run. Hold to slide, or run into the ball to tackle."
        actionElement.accessibilityIdentifier = "sandbox.action"
        standardActionHint = actionElement.accessibilityHint
        actionElement.accessibilityTraits = .button
        joystickElement = UIAccessibilityElement(accessibilityContainer: self)
        joystickElement.accessibilityLabel = "Movement joystick"
        joystickElement.accessibilityHint = "Touch anywhere on the left side of the pitch, then drag to move and aim. Each new touch centres the joystick under your thumb. Off the ball, your direction automatically selects a nearby player to reach the ball or block its carrier. Run into an opponent's ball from the front or side to win it. From behind, stay close and keep pressing. Steer sideways after shooting to bend the ball, or quickly pull opposite your kick to chip it."
        joystickElement.accessibilityIdentifier = "sandbox.joystick"
        joystickElement.accessibilityTraits = .allowsDirectInteraction
        powerElement = UIAccessibilityElement(accessibilityContainer: self)
        powerElement.accessibilityIdentifier = "sandbox.power"
        powerElement.accessibilityTraits = [.staticText, .updatesFrequently]
        accessibilityElements = [joystickElement!, actionElement!]
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private var restingStick: CGPoint {
        CGPoint(x: max(safeAreaInsets.left + 86, bounds.width * 0.14),
                y: bounds.height - max(safeAreaInsets.bottom + 76, 88))
    }
    private var actionCenter: CGPoint {
        CGPoint(x: bounds.width - max(safeAreaInsets.right + 86, bounds.width * 0.14),
                y: restingStick.y)
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
        actionTouch = nil
        actionStartedAt = 0
        joystickOrigin = nil
        joystickOffset = .zero
        scene?.setMovement(.zero)
        status = .idle
        power = nil
        accessibilityElements = [joystickElement!, actionElement!]
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
            accessibilityElements = power != nil ? [joystickElement!, powerElement!, actionElement!]
                : [joystickElement!, actionElement!]
        }
        actionElement.accessibilityTraits = waitingForAutomaticPlay ? [.button, .notEnabled] : .button
        actionElement.accessibilityLabel = canHead || preparingHeader || queuedHeader ? "Head ball"
            : takingPenalty ? "Take penalty" : canCross || power?.kind == .cross ? "Cross ball" : "Action"
        actionElement.accessibilityHint = takingPenalty
            ? "Aim with the joystick. Tap to shoot, or hold and release in the green power band."
            : incomingCross ? "Tap as the cross reaches your attacker to head towards goal. Close contact and good timing improve the finish."
            : canCross || power?.kind == .cross ? "Keep running and hold Action. Release in the green band to cross automatically towards attackers in the box. Too little power falls short; too much can sail past them. A short tap still passes."
            : standardActionHint
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
            actionElement.accessibilityValue = waitingForAutomaticPlay ? "Automatic opposition restart or goalkeeper distribution; move into position" :
                holdingKeeper ? "Your keeper has the ball in hands. Aim, tap to throw to the highlighted teammate, or hold and release for a high, long throw." :
                takingPenalty ? "Aim at the goal. Tap to shoot, or hold and release in the green band for more power. The goalkeeper will try to save it." :
                takingThrowIn ? "Nearby teammates offer a short throw. Aim and tap to the highlighted player, or hold for more distance and release." :
                takingGoalKick ? "Your keeper is taking a goal kick. Aim, tap to pass to the highlighted teammate, or hold and release for a high, long kick." :
                queuedHeader ? (incomingCross ? "Header queued towards goal. Move under the cross to meet it." : "Header queued. Aim saved; move under the ball to meet it.") :
                preparingHeader ? (incomingCross ? "Jump timed towards goal. Move to meet the cross." : "Preparing header. Aim the joystick and release Action.") :
                canHead ? (incomingCross ? "Tap as the cross reaches you to head towards goal." : "Aim the joystick and tap as the high ball reaches you.") :
                incomingCross ? "Your attackers are meeting the cross. Tap Action as it reaches your player to head towards goal." :
                canCross || power?.kind == .cross ? "Cross available. Keep running, hold Action, then release in green to find attackers in the box." :
                curving ? "Steer sideways to swerve the ball." :
                controllingKeeper && hasBall ? "Your keeper at feet. Move carefully, tap to pass or hold and release to kick." :
                status == .queued ? "Next kick queued" :
                controllingReceiver ? "You control the intended receiver. Steer to move, or centre the joystick to meet the ball. Tap or hold and release to prepare the next kick." :
                canReceive ? "Incoming ball: aim, then tap or hold and release to prepare the next kick" :
                status == .idle ? (hasBall ? "Ready to pass, play into space or shoot" : "Joystick selects your player automatically; hold to slide") : status.rawValue
        }
        let opponentHasBall = scene?.simulation.possessionTeam == .red
        guard self.status != status || self.hasBall != hasBall || self.curving != curving ||
                self.opponentHasBall != opponentHasBall || self.canSwitch != canSwitch || self.canReceive != canReceive ||
                self.controllingReceiver != controllingReceiver ||
                self.canHead != canHead || self.preparingHeader != preparingHeader || self.queuedHeader != queuedHeader ||
                self.canCross != canCross || self.incomingCross != incomingCross ||
                self.waitingForAutomaticPlay != waitingForAutomaticPlay || self.holdingKeeper != holdingKeeper ||
                self.controllingKeeper != controllingKeeper || self.takingThrowIn != takingThrowIn ||
                self.takingGoalKick != takingGoalKick || self.takingPenalty != takingPenalty || self.power != power else { return }
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
        updateAccessibilityFrames()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let scene, !scene.gameplayPaused, scene.simulation.phase == .playing else { return }
        for touch in touches {
            let point = touch.location(in: self)
            switch touchRole(at: point) {
            case .action where actionTouch == nil:
                actionTouch = touch
                actionStartedAt = touch.timestamp
                scene.pressAction(startedAt: touch.timestamp)
            case .movement where beginMovement(at: point, timestamp: touch.timestamp):
                movementTouch = touch
            default:
                break
            }
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch === movementTouch { moveMovement(to: touch.location(in: self), timestamp: touch.timestamp) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Release ACTION before clearing movement when both thumbs lift in the same event.
        for touch in touches where touch === actionTouch {
            scene?.releaseAction(heldFor: max(0, touch.timestamp - actionStartedAt))
            actionTouch = nil
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

    enum TouchRole: Equatable { case movement, action }

    /// Native toolbar controls sit above this view. Within the game surface, ACTION
    /// always owns its hit area, even if another thumb already holds the button.
    func touchRole(at point: CGPoint) -> TouchRole? {
        guard bounds.contains(point) else { return nil }
        if hypot(point.x - actionCenter.x, point.y - actionCenter.y) <= actionRadius + 20 { return .action }
        return point.x < bounds.midX ? .movement : nil
    }

    @discardableResult
    func beginMovement(at point: CGPoint, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard joystickOrigin == nil, touchRole(at: point) == .movement,
              let scene, !scene.gameplayPaused, scene.simulation.phase == .playing else { return false }
        joystickOrigin = point
        joystickOffset = .zero
        scene.setMovement(.zero, timestamp: timestamp)
        updateAccessibilityFrames()
        setNeedsDisplay()
        return true
    }

    func moveMovement(to point: CGPoint, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let origin = joystickOrigin else { return }
        let offset = Vector2(x: point.x - origin.x, y: point.y - origin.y).clampedLength(stickRadius)
        joystickOffset = CGPoint(x: offset.x, y: offset.y)
        let length = offset.length / stickRadius
        let deadZone = min(0.95, max(0, scene?.simulation.tuning.joystickDeadZone ?? 0.12))
        let magnitude = max(0, (length - deadZone) / (1 - deadZone))
        scene?.setMovement(Vector2(x: offset.x, y: -offset.y).normalized * magnitude, timestamp: timestamp)
        setNeedsDisplay()
    }

    func endMovement(timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        movementTouch = nil
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

        let pressed = actionTouch != nil
        let activeColor = power?.overcharging == true || power?.isSweet == true ? power?.tint ?? accent
            : status == .charging || status == .queued ? accent : UIColor.white
        context.setFillColor(activeColor.withAlphaComponent(pressed ? 0.25 : 0.10).cgColor)
        context.setStrokeColor(activeColor.withAlphaComponent(hasBall || canHead || preparingHeader || pressed ? 0.65 : 0.28).cgColor)
        context.setLineWidth(pressed ? 3 : 1.5)
        context.addEllipse(in: CGRect(x: actionCenter.x - actionRadius, y: actionCenter.y - actionRadius,
                                     width: actionRadius * 2, height: actionRadius * 2))
        context.drawPath(using: .fillStroke)
        if pressed {
            context.setStrokeColor(activeColor.withAlphaComponent(0.30).cgColor)
            context.strokeEllipse(in: CGRect(x: actionCenter.x - actionRadius - 7, y: actionCenter.y - actionRadius - 7,
                                            width: actionRadius * 2 + 14, height: actionRadius * 2 + 14))
        }
        let cancelled = pressed && status == .cancelled && !canSwitch
        drawText(actionTitle, at: actionCenter, size: 13, color: activeColor.withAlphaComponent(0.95))
        let actionHint = waitingForAutomaticPlay ? "AUTOMATIC" :
            holdingKeeper ? "TAP / HOLD" : takingThrowIn ? "HOLD FOR RANGE" :
            queuedHeader ? "QUEUED" : preparingHeader ? (incomingCross ? "MEET THE BALL" : "RELEASE") : canHead ? (incomingCross ? "TIME YOUR TAP" : "AIM / TAP") :
            canCross || power?.kind == .cross ? "HOLD / RELEASE" :
            !hasBall && !curving && opponentHasBall && !canReceive ? "HOLD" : "TAP / HOLD"
        drawText(cancelled ? "TRY AGAIN" : actionHint, at: CGPoint(x: actionCenter.x, y: actionCenter.y + 64), size: 10, color: .white.withAlphaComponent(0.72))
        if let power { drawPower(power, in: context) }
    }

    /// Shared by the rendered button and presentation tests; touch routing stays
    /// with the simulation's committed action even when eligibility changes.
    var actionTitle: String {
        if waitingForAutomaticPlay { return "WAIT" }
        if actionTouch != nil && status == .cancelled && !canSwitch { return "RELEASE" }
        if status == .sliding { return "SLIDE" }
        if queuedHeader { return "HEADER" }
        if status == .queued { return "QUEUED" }
        if status == .tackling { return "TACKLE" }
        if holdingKeeper { return "THROW" }
        if takingThrowIn { return "THROW" }
        if takingGoalKick { return "KICK" }
        if takingPenalty { return "SHOOT" }
        if preparingHeader || canHead { return "HEAD" }
        if canCross || power?.kind == .cross { return "CROSS" }
        if status == .charging { return hasBall || canReceive || controllingKeeper ? "KICK" : "SLIDE" }
        if canReceive { return "PREPARE" }
        if status == .recovering { return "RECOVER" }
        return !hasBall && !curving && opponentHasBall ? "SLIDE" : "ACTION"
    }

    private var powerFrame: CGRect {
        let width = min(176, bounds.width * 0.44)
        return CGRect(x: min(bounds.width - safeAreaInsets.right - width - 12, actionCenter.x - width / 2),
                      y: actionCenter.y - 91, width: width, height: 32)
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
}
