import Foundation

/// The sole owner of ground-plane movement. Rendering and touch recognition stay outside this type.
struct FootballSimulation {
    var tuning: GameplayTuning
    private(set) var configuration: FriendlyMatchConfiguration?
    // Tests can supply a fixed coin toss; live sessions draw a fresh toss for every new match.
    private let chooseStartingEnds: () -> Bool
    private var firstHalfBlueAttacksNorth = true
    private(set) var ends = MatchEnds()
    private var abilityKickSequence = 0
    var movement = Vector2.zero {
        didSet { rememberDeliberateKickAim() }
    }
    // Module-internal state also supports precise simulation fixtures; presentation reads `footballers`.
    var roster = [Footballer(id: 0, team: .blue, state: PlayerState())]
    private(set) var mode: ExerciseMode = .solo
    private(set) var selectedPlayerID = 0
    var footballers: [Footballer] { roster }
    var player: PlayerState {
        get { roster[selectedPlayerID].state }
        set { roster[selectedPlayerID].state = newValue }
    }
    var ball = BallState()
    private(set) var phase: SandboxPhase = .playing
    // Match scores belong to blue/red respectively, irrespective of the physical goal.
    // Practice mode retains the original north/south goal counters.
    private(set) var northGoals = 0
    private(set) var southGoals = 0
    private(set) var resetGeneration = 0
    private(set) var kickCount = 0
    private(set) var lastKick: BallMode?
    private(set) var lastKickKind: String?
    private(set) var lastDistributionKind: KeeperDistributionKind?
    var distributionPreviewKind: KeeperDistributionKind? {
        guard isHoldingGoalkeeper || (isTakingRestart && matchRestart?.kind == .goalKick), hasControl else { return nil }
        return currentDistributionChoice()?.plan.kind
    }
    private(set) var tackleCount = 0
    private(set) var standingTackleCount = 0
    private(set) var runningChallengeCount = 0
    private(set) var challengeContactCount = 0
    private(set) var lastChallengeWasSlide = false
    private(set) var switchCount = 0
    private(set) var slideCount = 0
    private(set) var chipCount = 0
    private(set) var headerCount = 0
    private(set) var crossCount = 0
    private(set) var lastHeaderPlayerID: Int?
    private struct CrossFlight {
        let passerID: Int
        let receiverID: Int
        let destination: Vector2
        let launchMovement: Vector2
        var remaining: Double
        var manualSteering = false
    }
    private var crossFlight: CrossFlight?
    var isCrossInFlight: Bool {
        crossFlight != nil && phase == .playing && possessionID == nil
            && ball.mode == .pass && ballIsStillInPlay()
    }
    private(set) var queuedPassCount = 0
    private(set) var foulCount = 0
    private(set) var lastFoul: FoulEvent?
    private struct PenaltyFlight {
        let takerID: Int
        let goalkeeperID: Int?
    }
    private var penaltyFlight: PenaltyFlight?
    private var penaltySecondTouchTakerID: Int?
    private(set) var penaltyDoubleTouchCount = 0
    var isTakingPenalty: Bool { isTakingRestart && matchRestart?.kind == .penalty }
    var isPenaltyKickInFlight: Bool { penaltyFlight != nil }
    var awardedFoulRestartKind: MatchRestartKind? {
        let foul: FoulEvent?
        switch phase {
        case .foulContact: foul = pendingFoul
        case .freeKick: foul = lastFoul
        default: return nil
        }
        guard let foul, roster.indices.contains(foul.offenderID) else { return nil }
        return mode == .match && PenaltyRules.awardsPenalty(at: foul.position,
            offender: roster[foul.offenderID].team, awarded: foul.awardedTeam, ends: ends) ? .penalty : .freeKick
    }
    private var penaltyCompletionPending: Bool {
        awardedFoulRestartKind == .penalty || matchRestart?.kind == .penalty || penaltyFlight != nil
    }
    private(set) var matchTimeElapsed = 0.0
    private(set) var matchHalf = 1
    private(set) var periodElapsed = 0.0
    private(set) var stoppageTime = 0.0
    private(set) var pendingInjuryID: Int?
    private(set) var substitutionNotice: String?
    private var substitutionNoticeRemaining = 0.0
    private(set) var unavailableSquadIDs: Set<String> = []
    private var injuryRandomState: UInt64 = 0xA17E_932D
    private var periodHasStarted = false
    // Possession and danger-area boundaries can flicker during a tackle or rebound.
    // Require a short, continuous spell of safe live play before whistling an attack dead.
    private var opportunityGraceRemaining = 0.0
    var halfDuration: Double { matchDuration / 2 }
    var periodTimeRemaining: Double {
        let remaining = halfDuration + stoppageTime - periodElapsed
        return remaining > 0.0000001 ? remaining : 0
    }
    var isInStoppageTime: Bool { periodElapsed >= halfDuration && periodHasStarted }
    var injuryReplacements: [ClubPlayer] {
        guard let id = pendingInjuryID else { return [] }
        return replacements(for: id)
    }

    /// Either side gets to complete a threatening phase, including its awarded set piece.
    /// A catch, settled clearance, goal, offside or defensive restart ends that opportunity.
    var hasGoalScoringOpportunity: Bool {
        guard mode == .match else { return false }
        if penaltyCompletionPending { return true }
        if let foul = pendingFoul ?? (phase == .freeKick(team: .blue) || phase == .freeKick(team: .red) ? lastFoul : nil) {
            return isAttackingPosition(foul.position, for: foul.awardedTeam)
        }
        if let restart = matchRestart {
            switch restart.kind {
            case .corner, .penalty: return true
            case .freeKick, .throwIn: return isAttackingPosition(restart.position, for: restart.team)
            default: return false
            }
        }
        guard phase == .playing, keeperHandsID == nil, ballIsStillInPlay() else { return false }
        let attackingTeam = ends.attackingTeam(atNorthGoal: ball.position.y >= 0)
        let forward = ends.attackSign(for: attackingTeam)
        // A loose ball or a defender's brief claim beside an attacker is still a chance.
        // In particular, a saved ball may be moving sideways/backwards and retain the
        // defender's last touch while the forward is one stride away from a tap-in.
        if isAttackingPosition(ball.position, for: attackingTeam),
           ball.height <= HeadingMechanics.maximumHeight,
           roster.contains(where: {
               $0.team == attackingTeam && !$0.isGoalkeeper && !$0.isUnavailable
                   && ($0.state.position - ball.position).length <= max(4, tuning.kickReach)
           }) { return true }
        if let owner = possessionID {
            return !roster[owner].isGoalkeeper && isAttackingPosition(ball.position, for: roster[owner].team)
        }
        // A shot can be on its way into the goal before it reaches the danger area.
        if ball.mode == .shot, abs(ball.velocity.y) > 1 {
            let goalY = ball.velocity.y > 0 ? Pitch.length / 2 : -Pitch.length / 2
            let arrival = (goalY - ball.position.y) / ball.velocity.y
            if arrival > 0, arrival <= 3,
               abs(ball.position.x + ball.velocity.x * arrival) <= Pitch.goalWidth / 2 + Pitch.ballRadius {
                return true
            }
        }
        // A defensive deflection does not erase an incoming shot/cross.
        return isAttackingPosition(ball.position, for: attackingTeam)
            && (lastTouchTeam == attackingTeam || ball.velocity.y * forward > 1)
    }

    private var canEndPeriod: Bool {
        guard !hasGoalScoringOpportunity else { return false }
        // Decisive stoppages need no grace period; a catch really has ended the attack.
        return phase != .playing || keeperHandsID != nil || opportunityGraceRemaining <= 0
    }

    private func isAttackingPosition(_ position: Vector2, for team: Team) -> Bool {
        let depth = Pitch.length / 2 - position.y * ends.attackSign(for: team)
        return depth < 25 && abs(position.x) < 30
    }

    private mutating func accountForStoppage(_ dt: Double) {
        guard mode == .match, periodHasStarted else { return }
        // Running match time and time lost advance together, preserving the full live-play
        // allocation. Help/settings and the replacement picker never enter this clock.
        periodElapsed += dt
        stoppageTime += dt
    }

    mutating func resumeAfterHalfTime() {
        guard phase == .halfTime else { return }
        matchHalf = 2
        ends.blueAttacksNorth.toggle()
        periodElapsed = 0
        stoppageTime = 0
        periodHasStarted = false
        opportunityGraceRemaining = 0
        prepareMatchRestart(MatchRestart(kind: .kickoff, team: .red, position: .zero, takerID: nil))
    }

    private mutating func finishHalf() {
        if matchHalf == 2 { finishMatch(); return }
        cancelInput()
        clearRestartSupport()
        resetOffsideForRestart()
        penaltyFlight = nil
        penaltySecondTouchTakerID = nil
        keeperHandsID = nil
        possessionID = nil
        controlClaim = false
        activePassTargetID = nil
        matchRestart = nil
        freeKickReadyTeam = nil
        phase = .halfTime
        ball.velocity = .zero
        ball.verticalVelocity = 0
        for id in roster.indices { roster[id].state.velocity = .zero }
    }
    private(set) var matchRestart: MatchRestart?
    private(set) var lastTouchTeam: Team?
    private(set) var lastDeliberatePlayTeam: Team?
    private var handlingRestrictedTeam: Team?
    private var keeperHandsID: Int?
    private var regroupingKeeperID: Int?
    private var regroupingSaveCount = -1
    private var shortOutletID: Int?
    /// A catch owns one stable outlet; stale catch state is never exposed after release/reset.
    var keeperShortOutletID: Int? {
        guard phase == .playing, let keeper = keeperHandsID, possessionID == keeper,
              regroupingKeeperID == keeper, regroupingSaveCount == goalkeeperSaveCount, let outlet = shortOutletID,
              roster.indices.contains(outlet), roster[outlet].team == roster[keeper].team,
              !roster[outlet].isUnavailable, !roster[outlet].isGoalkeeper else { return nil }
        return outlet
    }
    var goalkeeperHoldingID: Int? { phase == .playing ? keeperHandsID : nil }
    var isHoldingGoalkeeper: Bool { goalkeeperHoldingID == selectedPlayerID && roster[selectedPlayerID].team == .blue }
    var isControllingGoalkeeper: Bool {
        phase == .playing && roster[selectedPlayerID].team == .blue && roster[selectedPlayerID].isGoalkeeper
            && !roster[selectedPlayerID].isUnavailable
            && (possessionID == selectedPlayerID || isControllingPassReceiver
                || (lastKickerID == selectedPlayerID && (curveRemaining > 0 || chipRemaining > 0)))
    }
    private(set) var goalkeeperSaveCount = 0
    private(set) var offsideCount = 0
    private var pendingOffside: OffsideRules.Snapshot?
    private var offsideTouchPositions: [Vector2]?
    private var indirectKickTakerID: Int?
    private var attackingTargets: [Int: Vector2] = [:]
    var matchDuration: Double { max(1, tuning.matchDuration) }
    var matchTimeRemaining: Double { max(0, matchDuration - matchTimeElapsed) }
    var isTakingRestart: Bool { mode == .match && phase == .playing && matchRestart != nil }
    var goalkeeperPossessionTeam: Team? {
        guard phase == .playing, let owner = keeperHandsID else { return nil }
        return roster[owner].team
    }

    private struct RearPressure {
        let ownerID: Int
        var elapsed: Double
    }
    private var rearPressure: [Int: RearPressure] = [:]
    private var runningWinProtection = 0.0
    private var runningWinOwnerID: Int?
    private var keeperStates: [Int: GoalkeeperAI.State] = [:]
    private var keeperIntents: [Int: GoalkeeperAI.Intent] = [:]
    private var possessionID: Int? = 0
    private var activePassTargetID: Int?
    private var receiverControlRemaining = 0.0
    private var earlyPassAdjustment: EarlyPassAdjustment.State?
    private(set) var earlyPassAdjustmentCount = 0
    private(set) var lastEarlyPassAdjustmentAngle = 0.0
    var earlyPassAdjustmentRemaining: Double { earlyPassAdjustment?.remaining ?? 0 }
    private var unreachablePassElapsed = 0.0
    private var lastKickerID: Int?
    private var kickGuards: [Int: Double] = [:]
    private var tackleTimers: [Int: Double] = [:]
    private var recoveryTimers: [Int: Double] = [:]
    private var tackleDirections: [Int: Vector2] = [:]
    private var tackleHits: Set<Int> = []
    private var switchCountdown = 0.0
    private var switchCandidateID: Int?
    private var switchCandidateElapsed = 0.0
    private var aiDecisionCountdown = 1.0
    private var actionWasTackle = false
    private var actionReceiving = false
    private var actionHeading = false
    private var actionHeaderOnPress = false
    private struct QueuedHeader {
        let actorID: Int
        let aim: Vector2
        var goalDirected = false
        var remaining: Double
    }
    private var queuedHeader: QueuedHeader?
    private var headingTimers: [Int: Double] = [:]
    private var actionReceivingRemaining = 0.0
    private var recentReceiverID: Int?
    private var recentReceptionRemaining = 0.0
    private var actionAllowsManualSwitch = false
    private var actionStartedWithSelectionDirection = false
    private var actionKickAim = Vector2.up
    private struct PassIntent {
        let targetID: Int?
        let aim: Vector2
    }
    private var actionPassIntent: PassIntent?
    private var actionTimestamp: Double?
    private var movementTimestamp: Double?
    private var actionForward = Vector2.up
    private var actionSawForwardStick = false
    private var actionReverseAt: Double?
    private var throughBallLandingPoint: Vector2?
    private var recentKickAim: Vector2?
    private var recentKickAimActorID: Int?
    private var recentKickAimRemaining = 0.0
    private var actionActorID = 0
    private var actionCommittedSlide = false
    private var actionUsesTimestamps = false
    private var tackleKinds: [Int: TackleKind] = [:]
    private var previousFootballerPositions: [Vector2] = []
    private var randomState: UInt64 = 0x51CC_E2D4
    private var freeKickReadyTeam: Team?
    private var pendingFoul: FoulEvent?
    private var foulContactElapsed = 0.0
    private var foulOffenderWasSliding = false
    private var freeKickKickCountdown = 0.0
    private var restartOutletIDs: [Int] = []
    private var restartOutletTargets: [Int: Vector2] = [:]
    private var restartSupportElapsed = 0.0
    /// Stable short options belong only to the current waiting restart.
    var restartShortOutletIDs: [Int] {
        guard restartSupportContext != nil else { return [] }
        return restartOutletIDs.filter { eligibleRestartOutlet($0) }
    }
    private var restartSupportContext: MatchRestart? {
        guard phase == .playing, let team = freeKickReadyTeam, let taker = possessionID else { return nil }
        let context = matchRestart ?? MatchRestart(kind: .freeKick, team: team, position: ball.position, takerID: taker)
        switch context.kind {
        case .throwIn, .goalKick, .freeKick, .offside, .indirectFreeKick: return context
        default: return nil
        }
    }
    private var chipRemaining = 0.0
    private var kickInputBaseline: Vector2?
    private var originalKickDirection = Vector2.up
    private struct QueuedPass {
        let actorID: Int
        let aim: Vector2
        let heldFor: Double
        let passIntent: PassIntent?
        var remaining: Double
    }
    private var queuedPass: QueuedPass?

    private var controlClaim = true
    private var dribbleCountdown = 0.0
    private var reacquisitionCountdown = 0.0
    private var restartCountdown = 0.0
    private var actionDown = false
    private var actionCancelled = false
    private var actionElapsed = 0.0
    private var curveRemaining = 0.0
    private var originalShotDirection = Vector2.up
    private var curveAngle = 0.0
    private(set) var aftertouchVector = Vector2.zero

    init(tuning: GameplayTuning = .defaults, mode: ExerciseMode = .solo,
         configuration: FriendlyMatchConfiguration? = nil, injurySeed: UInt64 = 0xA17E_932D,
         chooseStartingEnds: @escaping () -> Bool = { true }) {
        self.chooseStartingEnds = chooseStartingEnds
        self.injuryRandomState = injurySeed
        self.tuning = tuning
        self.configuration = configuration?.isValid == true ? configuration : nil
        self.mode = self.configuration == nil ? mode : .match
        if self.mode == .passing { configureExercise() }
        else if self.mode == .match { configureMatch() }
    }

    mutating func setMode(_ newMode: ExerciseMode) {
        guard newMode != mode else { return }
        mode = newMode
        reset(clearScore: true)
    }

    var possessionTeam: Team? {
        if mode == .solo { return hasControl ? .blue : nil }
        guard phase == .playing, let id = possessionID else { return nil }
        return roster[id].team
    }

    var passTargetID: Int? {
        guard mode != .solo, matchRestart?.kind != .penalty else { return nil }
        if isHoldingGoalkeeper || (isTakingRestart && matchRestart?.kind == .goalKick) {
            return currentDistributionChoice()?.targetID
        }
        if actionDown, !actionCancelled, actionElapsed >= tuning.holdThreshold, hasControl,
           let cross = crossingOpportunity(for: actionActorID) { return cross.receiverID }
        if actionDown, !actionCancelled, actionElapsed < tuning.holdThreshold,
           let intent = actionPassIntent { return intent.targetID }
        if let queued = queuedPass, let intent = queued.passIntent { return intent.targetID }
        if let target = activePassTargetID { return target }
        guard hasControl else { return nil }
        return quickPassTarget(from: selectedPlayerID, aim: intendedKickAim(for: selectedPlayerID))
    }

    var isControllingPassReceiver: Bool {
        phase == .playing && mode != .solo && receiverControlRemaining > 0
            && ball.mode == .pass && activePassTargetID == selectedPlayerID
            && !roster[selectedPlayerID].isUnavailable
    }

    var canPrepareReceivingKick: Bool { receivingPlayerID != nil }
    var isPreparingReceivingKick: Bool { actionDown && actionReceiving && !actionCancelled }
    var isPreparingHeader: Bool { (actionDown && actionHeading && !actionHeaderOnPress && !actionCancelled) || queuedHeader != nil }
    var headingPlayerID: Int? {
        guard phase == .playing, freeKickReadyTeam == nil, keeperHandsID == nil, !hasControl,
              ball.height > tuning.airborneContactHeight, ballIsStillInPlay() else { return nil }
        if let queuedHeader { return queuedHeader.actorID }
        let candidates = roster.filter { $0.team == .blue && eligibleHeader($0.id)
            && headerArrival(for: $0.id, window: HeadingMechanics.prepareWindow) != nil }
        if candidates.contains(where: { $0.id == selectedPlayerID }) { return selectedPlayerID }
        return candidates.min {
            let left = headerArrival(for: $0.id, window: HeadingMechanics.prepareWindow) ?? .infinity
            let right = headerArrival(for: $1.id, window: HeadingMechanics.prepareWindow) ?? .infinity
            return abs(left - right) < 0.000001 ? $0.id < $1.id : left < right
        }?.id
    }
    var isTakingFreeKick: Bool {
        phase == .playing && freeKickReadyTeam == .blue
            && (mode != .match || matchRestart?.kind == .freeKick)
    }

    /// Only an actually incoming friendly/free ball offers a receiving action; outgoing aim never
    /// participates in this prediction, so a prepared return pass can point away from the arrival.
    var receivingPlayerID: Int? {
        guard phase == .playing, !hasControl, !isTackling, freeKickReadyTeam == nil,
              ballIsStillInPlay(), !ballNeedsBoundaryRescue else { return nil }
        if let owner = possessionID, (ball.position - roster[owner].state.position).length <= tuning.controlReleaseDistance {
            return roster[owner].team == .blue && owner == recentReceiverID && recentReceptionRemaining > 0
                && eligibleReceiver(owner) ? owner : nil
        }
        if let kicker = lastKickerID, roster[kicker].team == .red, ball.mode != .free { return nil }
        let candidates = roster.filter { $0.team == .blue && eligibleReceiver($0.id)
            && incomingArrival(for: $0.id) != nil }
        if let intended = activePassTargetID, candidates.contains(where: { $0.id == intended }) { return intended }
        return candidates.min {
            let a = ($0.state.position - ball.position).lengthSquared
            let b = ($1.state.position - ball.position).lengthSquared
            return abs(a - b) < 0.000001 ? $0.id < $1.id : a < b
        }?.id
    }

    var canSwitchToNearestPlayer: Bool {
        phase == .playing && mode != .solo && !hasControl && !isTackling && freeKickReadyTeam == nil
            && preferredBlueSelection(manual: true).id != selectedPlayerID
    }

    var rearPressureProgress: Double {
        guard phase == .playing, let pressure = rearPressure[selectedPlayerID],
              pressure.ownerID == possessionID else { return 0 }
        return min(1, pressure.elapsed / max(0.01, tuning.rearPressureDuration))
    }
    var isPressingFromBehind: Bool { rearPressureProgress > 0 }

    var isTackling: Bool { roster[selectedPlayerID].isTackling }
    var isSliding: Bool { roster[selectedPlayerID].isSliding }
    var chipWindowRemaining: Double { chipRemaining }
    var queuedPassRemaining: Double { queuedPass?.remaining ?? 0 }
    var queuedPassPlayerID: Int? { queuedPass?.actorID }
    var queuedActionRemaining: Double { queuedHeader?.remaining ?? queuedPassRemaining }
    var queuedActionKind: String? {
        if queuedHeader != nil { return "header" }
        guard let queued = queuedPass else { return nil }
        return queued.heldFor >= tuning.holdThreshold ? "shot" : "pass"
    }

    var hasControl: Bool {
        if isHoldingGoalkeeper { return true }
        if mode != .solo {
            return phase == .playing && !roster[selectedPlayerID].isUnavailable && possessionID == selectedPlayerID
                && ball.height <= tuning.airborneContactHeight
                && (kickGuards[selectedPlayerID] ?? 0) <= 0
                && (ball.position - player.position).length <= controlReleaseDistance(for: selectedPlayerID)
                && (ball.velocity - player.velocity).length <= controlSpeedLimit(for: selectedPlayerID) * 1.25
        }
        return phase == .playing && controlClaim && reacquisitionCountdown <= 0 && ball.height <= tuning.airborneContactHeight
            && (ball.position - player.position).length <= tuning.controlReleaseDistance
            && (ball.velocity - player.velocity).length <= tuning.controlRelativeSpeed * 1.25
    }

    var canKick: Bool {
        isHoldingGoalkeeper || (hasControl && (ball.position - player.position).length <= tuning.kickReach)
    }

    var canCross: Bool { hasControl && crossingOpportunity(for: selectedPlayerID) != nil }

    private func crossingExclusions(for actor: Int) -> Set<Int> {
        mode == .match ? OffsideRules.snapshot(actor: actor, ball: ball.position,
            roster: roster, restart: matchRestart?.kind, ends: ends)?.candidates ?? [] : []
    }

    private func crossingOpportunity(for actor: Int) -> CrossingMechanics.Opportunity? {
        guard mode != .solo, phase == .playing, matchRestart == nil, freeKickReadyTeam == nil,
              keeperHandsID == nil, roster.indices.contains(actor), !roster[actor].isGoalkeeper else { return nil }
        return CrossingMechanics.opportunity(crosser: roster[actor], roster: roster, tuning: tuning,
            ends: ends, excludedReceiverIDs: crossingExclusions(for: actor))
    }

    var powerMeterKind: KickPowerKind? {
        guard actionDown, !actionCancelled, !actionWasTackle, !actionHeading else { return nil }
        if isHoldingGoalkeeper { return .keeperDistribution }
        if matchRestart?.kind == .throwIn { return .throwIn }
        if matchRestart?.kind == .goalKick { return .longKick }
        if matchRestart?.kind == .penalty { return .shot }
        if hasControl, crossingOpportunity(for: actionActorID) != nil { return .cross }
        return assistedShotDirection(from: actionActorID, aim: intendedKickAim(for: actionActorID)) != nil ? .shot : .longKick
    }
    var powerMeterFraction: Double {
        guard let kind = powerMeterKind else { return 0 }
        if kind == .cross { return CrossingMechanics.meterFraction(heldFor: actionElapsed, tuning: tuning) }
        return kind == .shot ? KickMechanics.shotMeterFraction(heldFor: actionElapsed, tuning: tuning) : charge(for: actionElapsed)
    }
    var powerMeterSweetSpot: ClosedRange<Double>? {
        if powerMeterKind == .cross { return CrossingMechanics.sweetSpot(tuning: tuning) }
        return powerMeterKind == .shot ? KickMechanics.shotSweetSpot(tuning: tuning) : nil
    }
    var powerMeterOverhitStart: Double? {
        if powerMeterKind == .cross { return CrossingMechanics.overhitStart(tuning: tuning) }
        return powerMeterKind == .shot ? KickMechanics.shotOverhitStart(tuning: tuning) : nil
    }

    var isOverchargingPower: Bool {
        if powerMeterKind == .cross { return CrossingMechanics.isOverhit(heldFor: actionElapsed, tuning: tuning) }
        return isOverchargingShot
    }

    var isOverchargingShot: Bool {
        powerMeterKind == .shot && KickMechanics.isOverhit(heldFor: actionElapsed, tuning: tuning)
    }

    var actionStatus: ActionStatus {
        if isSliding { return .sliding }
        if isTackling { return .tackling }
        if queuedPass != nil || queuedHeader != nil { return .queued }
        if (recoveryTimers[selectedPlayerID] ?? 0) > 0 { return .recovering }
        guard actionDown else { return .idle }
        if actionCancelled { return .cancelled }
        if actionWasTackle { return .pressed }
        return actionElapsed < tuning.holdThreshold ? .pressed : .charging
    }

    var chargeFraction: Double {
        guard actionDown, !actionCancelled, !actionWasTackle, !actionHeading else { return 0 }
        return charge(for: actionElapsed)
    }

    var aftertouchRemaining: Double { curveRemaining }

    /// The caller advances this at 60 Hz using its frame-time accumulator.
    mutating func step(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        if case .practiceEnded = phase { return }
        if phase == .fullTime || phase == .halfTime || pendingInjuryID != nil { return }
        substitutionNoticeRemaining = max(0, substitutionNoticeRemaining - dt)
        if substitutionNoticeRemaining == 0 { substitutionNotice = nil }
        if case .foulContact = phase { accountForStoppage(dt); advanceFoulAftermath(dt: dt); return }
        if case .freeKick(let team) = phase { accountForStoppage(dt); advanceFreeKickAftermath(for: team, dt: dt); return }
        opportunityGraceRemaining = hasGoalScoringOpportunity ? 0.75 : max(0, opportunityGraceRemaining - dt)
        if mode == .match, periodHasStarted, periodTimeRemaining <= 0.0000001,
           canEndPeriod { finishHalf(); return }
        if mode != .solo, phase == .playing, !checkPracticeCanContinue() { return }
        guard phase == .playing else {
            accountForStoppage(dt)
            restartCountdown -= dt
            if restartCountdown <= 0 {
                if mode == .match, let restart = matchRestart { prepareMatchRestart(restart) }
                else { automaticReset() }
            }
            return
        }

        if mode != .solo {
            let liveMatch = mode == .match && freeKickReadyTeam == nil
            let extendingAttack = liveMatch && periodTimeRemaining <= 0.0000001
            let playDT = liveMatch && !extendingAttack ? min(dt, periodTimeRemaining) : dt
            if liveMatch { periodHasStarted = true }
            else { accountForStoppage(dt) }
            if playDT > 0 { stepExercise(dt: playDT) }
            if liveMatch {
                matchTimeElapsed = min(matchDuration, matchTimeElapsed + playDT)
                periodElapsed += playDT
                updatePenaltyCompletion()
                if hasGoalScoringOpportunity { opportunityGraceRemaining = 0.75 }
                // Complete the foul animation and any injury selection before ending a half.
                let foulAftermath = pendingFoul != nil || {
                    if case .freeKick = phase { return true }; return false
                }()
                if periodTimeRemaining <= 0.0000001 && canEndPeriod
                    && !foulAftermath && pendingInjuryID == nil { finishHalf() }
            }
            return
        }

        reacquisitionCountdown = max(0, reacquisitionCountdown - dt)
        dribbleCountdown = max(0, dribbleCountdown - dt)
        advanceRecoveryTimers(dt: dt)
        refreshControl()
        advanceActionClock(dt: dt)

        let wasCurving = curveRemaining > 0
        previousFootballerPositions = roster.map(\.state.position)
        if (tackleTimers[0] ?? 0) > 0 { moveCommittedTackle(0, dt: dt) }
        else { movePlayer(dt: dt, coasting: wasCurving) }
        refreshControl(allowAcquisition: false)
        nudgeBallIfReachable()
        applyChipInput(dt: dt)
        applyAftertouch(dt: dt)
        advanceBall(dt: dt)
        finishActionTimers(dt: dt)
        if phase == .playing { refreshControl() }
    }

    mutating func updateMovement(_ value: Vector2, timestamp: Double? = nil) {
        movementTimestamp = timestamp?.isFinite == true ? timestamp : nil
        movement = value
        movementTimestamp = nil
    }

    mutating func pressAction(timestamp: Double? = nil) {
        if mode == .match, freeKickReadyTeam != nil, freeKickReadyTeam != .blue { return }
        guard phase == .playing, !actionDown, !roster[selectedPlayerID].isUnavailable,
              !roster[selectedPlayerID].isGoalkeeper || isControllingGoalkeeper else { return }
        earlyPassAdjustment = nil
        // Touching ACTION should recognise the same close pickup as the next simulation tick.
        if mode != .solo {
            refreshExerciseControl()
            guard phase == .playing else { return }
            // A direction change and ACTION can arrive between ticks. Infer the intended actor
            // before capturing this press, so a held slide cannot start with the old selection.
            if selectionStick.length > 0 { selectRelevantBluePlayer() }
        } else { refreshControl() }
        let header = headingPlayerID
        if let header {
            if header != selectedPlayerID { selectBlue(header) }
            endAftertouch()
            chipRemaining = 0
            kickInputBaseline = nil
        }
        let receiver = header == nil ? receivingPlayerID : nil
        if let receiver {
            if receiver != selectedPlayerID { selectBlue(receiver) }
            // Preparing the receiver's next action explicitly leaves the original kick's chip window,
            // including when an assisted pass has already handed control to this receiver.
            if lastKickerID != receiver {
                endAftertouch()
                chipRemaining = 0
                kickInputBaseline = nil
            }
        }
        actionKickAim = intendedKickAim(for: selectedPlayerID)
        if isHoldingGoalkeeper || (isTakingRestart && matchRestart?.kind == .goalKick) {
            actionPassIntent = PassIntent(targetID: distributionChoice(from: selectedPlayerID,
                aim: actionKickAim, heldFor: 0, hands: isHoldingGoalkeeper).targetID, aim: actionKickAim)
        } else {
            actionPassIntent = mode != .solo && (hasControl || receiver != nil)
                && matchRestart?.kind != .throwIn && matchRestart?.kind != .penalty
                ? PassIntent(targetID: quickPassTarget(from: selectedPlayerID, aim: actionKickAim), aim: actionKickAim) : nil
        }
        actionTimestamp = timestamp?.isFinite == true ? timestamp : nil
        actionForward = player.facing
        actionSawForwardStick = validMovement.length >= tuning.kickAimStickThreshold
            && validMovement.normalized.dot(actionForward) > 0.55
        actionReverseAt = nil
        actionDown = true
        actionElapsed = 0
        actionUsesTimestamps = false
        actionActorID = selectedPlayerID
        actionCommittedSlide = false
        actionReceiving = receiver != nil
        actionHeading = header != nil
        actionHeaderOnPress = header.map { isAttackingCross(for: $0) } ?? false
        actionReceivingRemaining = max(0.01, tuning.queuedPassDuration)
        actionWasTackle = !hasControl && !actionReceiving && !actionHeading
        actionAllowsManualSwitch = mode != .solo && actionWasTackle && !isTackling && freeKickReadyTeam == nil
        actionStartedWithSelectionDirection = selectionStick.length > 0
        actionCancelled = curveRemaining > 0 || chipRemaining > 0 || (recoveryTimers[selectedPlayerID] ?? 0) > 0
        queuedPass = nil
        queuedHeader = nil
        // A cross asks for a timed jump on button-down. Holding cannot retry a missed jump.
        if actionHeaderOnPress, !actionCancelled {
            armHeader(for: actionActorID, aim: actionKickAim, goalDirected: true)
        }
    }

    /// External touch timestamps take ownership of this press's clock; simulation steps then never add time twice.
    mutating func updateActionHold(heldFor duration: Double) {
        guard actionDown, duration.isFinite, duration >= 0 else { return }
        actionUsesTimestamps = true
        actionElapsed = max(actionElapsed, duration)
        commitHeldSlideIfNeeded()
    }

    private mutating func advanceActionClock(dt: Double) {
        guard actionDown else { return }
        if !actionUsesTimestamps { actionElapsed += dt }
        if actionReceiving, !hasControl {
            actionReceivingRemaining -= dt
            if actionReceivingRemaining <= 0 { actionCancelled = true }
        }
        commitHeldSlideIfNeeded()
    }

    private mutating func commitHeldSlideIfNeeded() {
        guard actionWasTackle, !actionCancelled, !actionCommittedSlide,
              actionElapsed >= tuning.slideHoldThreshold else { return }
        let state = roster[actionActorID].state
        let direction = state.velocity.length > 0.35 ? state.velocity.normalized : state.facing
        actionCommittedSlide = startTackle(id: actionActorID, direction: direction, kind: .slide)
        if actionCommittedSlide {
            slideCount += 1
            tackleCount += 1
            queuedPass = nil
        }
    }

    /// Duration comes from touch timestamps, so a dropped render frame cannot change tap/hold classification.
    mutating func releaseAction(heldFor duration: Double) {
        guard actionDown else { return }
        if duration.isFinite, duration >= 0 {
            actionElapsed = max(actionElapsed, duration)
            commitHeldSlideIfNeeded()
        }
        let validDuration = duration.isFinite && duration >= 0
        let manualSwitchTap = actionAllowsManualSwitch && !actionCommittedSlide
            && (!actionStartedWithSelectionDirection || selectionStick.length > 0)
            && validDuration && duration < tuning.slideHoldThreshold
        let offBallTap = actionWasTackle && !actionCancelled && !actionCommittedSlide
            && validDuration && duration < tuning.slideHoldThreshold
        let actor = actionActorID
        let headingRelease = actionHeading && !actionHeaderOnPress && !actionCancelled && validDuration && phase == .playing
        let headerAlreadyRequested = actionHeading && actionHeaderOnPress
        let receivingRelease = actionReceiving && !actionCancelled && validDuration && phase == .playing
        let eligible = phase == .playing && !actionWasTackle && !actionCancelled && canKick && validDuration
        let aim = intendedKickAim(for: actor)
        let backheel = eligible && !isHoldingGoalkeeper && matchRestart?.kind != .throwIn
            && duration < tuning.holdThreshold && actionSawForwardStick
            && actionReverseAt.map { duration >= $0 && duration - $0 <= tuning.backheelReversalWindow + 0.000001 } == true
            && aim.dot(actionForward) < -0.7
        if backheel { roster[actor].state.facing = actionForward }
        let passIntent = duration < tuning.holdThreshold && !backheel ? actionPassIntent : nil
        let delivery = eligible && (isHoldingGoalkeeper || matchRestart?.kind == .goalKick)
            ? currentDistributionChoice(heldFor: duration) : nil
        actionPassIntent = nil
        actionDown = false
        actionHeading = false
        actionHeaderOnPress = false
        actionElapsed = 0
        actionCancelled = false
        actionWasTackle = false
        actionReceiving = false
        actionUsesTimestamps = false
        actionCommittedSlide = false
        actionAllowsManualSwitch = false
        actionStartedWithSelectionDirection = false
        if let delivery {
            releaseDistribution(by: actor, choice: delivery, heldFor: duration, human: true)
            return
        }
        if headingRelease {
            armHeader(for: actor, aim: aim)
            return
        }
        if headerAlreadyRequested { return }
        if receivingRelease {
            if eligible { performHumanKick(by: actor, aim: aim, heldFor: duration, backheel: backheel, passIntent: passIntent) }
            else { _ = armQueuedKick(for: actor, aim: aim, heldFor: duration, receiving: true, passIntent: passIntent) }
            return
        }
        if manualSwitchTap, phase == .playing, switchToNearestBlueImmediately() { return }
        if offBallTap, phase == .playing {
            _ = armQueuedKick(for: actor, aim: aim, heldFor: 0, receiving: false)
            return
        }
        guard eligible else { return }
        performHumanKick(by: actor, aim: aim, heldFor: duration, backheel: backheel, passIntent: passIntent)
    }

    private mutating func performHumanKick(by actor: Int, aim requested: Vector2, heldFor duration: Double,
                                          clearingBoundary: Bool = false, backheel: Bool = false,
                                          passIntent: PassIntent? = nil) {
        guard !penaliseOffsideInvolvement(by: actor) else { return }
        if matchRestart?.kind == .penalty {
            launchPenalty(by: actor, aim: requested, heldFor: duration, human: true)
            return
        }
        if keeperHandsID == actor {
            releaseKeeperBall(by: actor, aim: requested, heldFor: duration, human: true)
            return
        }
        if matchRestart?.kind == .goalKick {
            releaseDistribution(by: actor, choice: distributionChoice(from: actor, aim: requested,
                heldFor: duration, hands: false), heldFor: duration, human: true)
            return
        }
        if matchRestart?.kind == .throwIn {
            let flight = KickMechanics.throwIn(heldFor: duration, tuning: tuning)
            activePassTargetID = nil
            lastKickKind = "throw in"
            kickBall(by: actor, aim: clearanceDirection(requested), speed: flight.speed, isShot: false, human: true)
            ball.height = flight.height
            ball.verticalVelocity = flight.verticalVelocity
            chipRemaining = 0
            endAftertouch()
            return
        }
        if !clearingBoundary, duration >= tuning.holdThreshold, crossingOpportunity(for: actor) != nil,
           let plan = CrossingMechanics.plan(origin: ball.position, crosser: roster[actor], roster: roster,
                heldFor: duration, tuning: tuning, ends: ends, sequence: abilityKickSequence,
                excludedReceiverIDs: crossingExclusions(for: actor)) {
            launchCross(by: actor, plan: plan, human: true)
            return
        }
        let tapAim = passIntent?.aim ?? requested
        let quickShot = !backheel && duration < tuning.holdThreshold
            && shouldShootQuickTap(from: actor, aim: tapAim, target: passIntent?.targetID)
        let isShot = duration >= tuning.holdThreshold || quickShot
        var aim = (quickShot ? tapAim : requested).normalized
        var lift = 0.0
        var landing: Vector2?
        let speed: Double
        if isShot {
            activePassTargetID = nil
            if assistedShotDirection(from: actor, aim: aim) != nil,
               let shot = KickMechanics.shot(origin: ball.position, aim: aim, team: roster[actor].team,
                                             heldFor: duration, tuning: tuning, ends: ends) {
                aim = shot.direction
                lift = shot.verticalVelocity
                speed = shot.speed
                lastKickKind = shot.isOverhit ? "overhit shot" : "shot"
            } else {
                lastKickKind = "long kick"
                let flight = KickMechanics.longKick(heldFor: duration, tuning: tuning)
                speed = flight.speed
                lift = flight.verticalVelocity
            }
        } else {
            if let passIntent {
                // Movement may already be preparing the recipient's run. The recipient shown
                // at button-down remains the recipient; a special kick explicitly leaves this lock.
                aim = passIntent.aim
                activePassTargetID = passIntent.targetID.flatMap { target in
                    let candidate = roster[target]
                    // His guard prevents reclaiming his own outgoing kick, not being
                    // chosen for an immediate one-two from a teammate.
                    return candidate.team == roster[actor].team && !candidate.isUnavailable
                        && !candidate.isTackling && candidate.fallProgress <= 0.001
                        && (recoveryTimers[target] ?? 0) <= 0 ? target : nil
                }
            } else {
                activePassTargetID = mode != .solo ? choosePassTarget(from: actor, aim: aim) : nil
            }
            var spacePoint = ball.position + aim * 14
            spacePoint.x = min(Pitch.width / 2 - 1, max(-Pitch.width / 2 + 1, spacePoint.x))
            spacePoint.y = min(Pitch.length / 2 - 1, max(-Pitch.length / 2 + 1, spacePoint.y))
            let spaceRunner = !backheel && activePassTargetID == nil && mode != .solo
                ? throughBallRunner(from: actor, aim: aim, landing: spacePoint) : nil
            if let spaceRunner {
                var point = spacePoint
                point.x = min(Pitch.width / 2 - 1, max(-Pitch.width / 2 + 1, point.x))
                point.y = min(Pitch.length / 2 - 1, max(-Pitch.length / 2 + 1, point.y))
                landing = point
                activePassTargetID = spaceRunner
                speed = sqrt(64 + 2 * max(0, tuning.ballFriction) * (point - ball.position).length)
                lastKickKind = "through ball"
            } else if let target = activePassTargetID {
                aim = ledPassDirection(to: target, from: actor)
                speed = assistedPassSpeed(to: target, from: actor)
                lastKickKind = backheel ? "backheel" : "pass"
            } else {
                speed = max(tuning.knockAheadSpeed, roster[actor].state.velocity.dot(aim) + tuning.knockAheadSpeedBonus)
                lastKickKind = backheel ? "backheel" : "knock ahead"
            }
        }
        if clearingBoundary { aim = clearanceDirection(aim) }
        let footScale = roster[actor].isGoalkeeper ? tuning.keeperFootKickScale : 1
        kickBall(by: actor, aim: aim, speed: speed * footScale, isShot: isShot, human: true)
        ball.verticalVelocity = lift
        throughBallLandingPoint = landing
        if backheel { ball.height = 0; ball.verticalVelocity = 0; kickInputBaseline = validMovement }
    }

    private func throughBallRunner(from actor: Int, aim: Vector2, landing: Vector2) -> Int? {
        let travel = (landing - ball.position).length
        let offsidePlayers = mode == .match ? OffsideRules.snapshot(actor: actor, ball: ball.position,
            roster: roster, restart: matchRestart?.kind, ends: ends)?.candidates ?? [] : []
        return roster.filter { candidate in
            guard candidate.id != actor, candidate.team == roster[actor].team, !candidate.isGoalkeeper,
                  !candidate.isUnavailable, !candidate.isTackling, !offsidePlayers.contains(candidate.id),
                  (recoveryTimers[candidate.id] ?? 0) <= 0 else { return false }
            let offset = candidate.state.position - ball.position
            return offset.dot(aim) > 1 && abs(offset.dot(aim.perpendicular)) <= 10
                && (candidate.state.position - landing).length < min(14, travel - 1)
        }.min {
            let a = ($0.state.position - landing).lengthSquared
            let b = ($1.state.position - landing).lengthSquared
            return abs(a - b) < 0.000001 ? $0.id < $1.id : a < b
        }?.id
    }

    private mutating func launchCross(by actor: Int, plan: CrossingMechanics.Plan, human: Bool) {
        let launchMovement = validMovement
        activePassTargetID = plan.receiverID
        lastKickKind = "cross"
        roster[actor].state.facing = plan.direction
        kickBall(by: actor, aim: plan.direction, speed: plan.speed, isShot: false, human: human)
        // The planner already applies rating error and power. Keep its solved physical flight.
        ball.velocity = plan.direction * plan.speed
        ball.height = plan.height
        ball.verticalVelocity = plan.verticalVelocity
        throughBallLandingPoint = plan.destination
        crossFlight = CrossFlight(passerID: actor, receiverID: plan.receiverID,
            destination: plan.destination, launchMovement: launchMovement,
            remaining: max(2.5, plan.flightTime + 1))
        if human { crossCount += 1 }
        receiverControlRemaining = human ? max(2.5, plan.flightTime + 1) : 0
        earlyPassAdjustment = nil
        chipRemaining = 0
        endAftertouch()
        kickInputBaseline = nil
    }

    private func isAttackingCross(for actor: Int) -> Bool {
        guard isCrossInFlight, let cross = crossFlight,
              roster[actor].team == roster[cross.passerID].team else { return false }
        let depth = Pitch.length / 2 - roster[actor].state.position.y * ends.attackSign(for: roster[actor].team)
        return depth > 0 && depth <= 24 && abs(roster[actor].state.position.x) <= 20.5
    }

    private struct DistributionChoice {
        let targetID: Int?
        let plan: KeeperDeliveryPlanner.Plan
    }

    private func currentDistributionChoice(heldFor duration: Double? = nil) -> DistributionChoice? {
        guard isHoldingGoalkeeper || (isTakingRestart && matchRestart?.kind == .goalKick), hasControl else { return nil }
        let held = duration ?? (actionDown ? actionElapsed : 0)
        let aim = actionDown ? actionPassIntent?.aim ?? actionKickAim : intendedKickAim(for: selectedPlayerID)
        let captured = actionDown && held < tuning.holdThreshold ? actionPassIntent : nil
        return distributionChoice(from: selectedPlayerID, aim: aim, heldFor: held,
            hands: isHoldingGoalkeeper, captured: captured)
    }

    private func keeperThrowRange(heldFor duration: Double) -> Double {
        // The short safe outlet remains an 8–10m option; longer taps can now use overarm delivery.
        44 * KeeperDeliveryPlanner.ability(roster[keeperHandsID ?? selectedPlayerID].abilities)
    }

    private func distributionPlan(to receiver: Int, from actor: Int, heldFor duration: Double,
                                  hands: Bool) -> KeeperDeliveryPlanner.Plan {
        let target = roster[receiver]
        let humanHandoff = actor == selectedPlayerID && roster[actor].team == .blue
        let speed = tuning.playerMaxSpeed * target.abilities.speed
            * (target.isGoalkeeper ? tuning.keeperFootSpeedScale : tuning.offBallSpeedBoost)
        return KeeperDeliveryPlanner.plan(origin: ball.position, receiver: target.state,
            requestedVelocity: humanHandoff ? validMovement * speed : nil,
            acceleration: tuning.playerAcceleration * target.abilities.acceleration,
            deceleration: tuning.playerDeceleration, hands: hands, heldFor: duration,
            ability: KeeperDeliveryPlanner.ability(roster[actor].abilities),
            blockers: roster.filter { $0.team != roster[actor].team && !$0.isUnavailable }.map { $0.state.position },
            tuning: tuning)
    }

    private func distributionChoice(from actor: Int, aim: Vector2, heldFor duration: Double,
                                    hands: Bool, captured: PassIntent? = nil) -> DistributionChoice {
        let quality = KeeperDeliveryPlanner.ability(roster[actor].abilities)
        let held = duration >= tuning.holdThreshold
        let power = charge(for: duration)
        let range = (held ? (hands ? 47 : 55) + 23 * power : hands ? 44 : 45) * quality
        let minimumDistance = held ? 20 + 12 * power : 1.8
        let offside = mode == .match ? OffsideRules.snapshot(actor: actor, ball: ball.position,
            roster: roster, restart: matchRestart?.kind, ends: ends)?.candidates ?? [] : []
        let candidates = roster.filter { candidate in
            candidate.id != actor && candidate.team == roster[actor].team && !candidate.isGoalkeeper
                && !candidate.isUnavailable && !candidate.isTackling && candidate.fallProgress <= 0.001
                && (recoveryTimers[candidate.id] ?? 0) <= 0 && !offside.contains(candidate.id)
        }
        if let captured {
            if let id = captured.targetID, candidates.contains(where: { $0.id == id }) {
                let plan = distributionPlan(to: id, from: actor, heldFor: duration, hands: hands)
                if plan.isReachable { return DistributionChoice(targetID: id, plan: plan) }
            }
            return DistributionChoice(targetID: nil, plan: KeeperDeliveryPlanner.space(origin: ball.position,
                aim: captured.aim, hands: hands, heldFor: duration, ability: quality, tuning: tuning))
        }
        let direction = aim.length > 0.0001 ? aim.normalized : roster[actor].state.facing
        var best: DistributionChoice?
        var bestScore = -Double.infinity
        for candidate in candidates {
            let offset = candidate.state.position - ball.position
            let distance = offset.length
            guard distance >= minimumDistance, distance <= range,
                  offset.normalized.dot(direction) >= cos(tuning.passAssistAngle * .pi / 180) else { continue }
            let plan = distributionPlan(to: candidate.id, from: actor, heldFor: duration, hands: hands)
            guard plan.isReachable else { continue }
            let risk = passLaneRisk(to: plan.destination, arrivalTime: plan.flightTime, team: roster[actor].team)
            let rangePreference = held ? -abs(distance - range * 0.85) / max(1, range) : -distance / max(1, range)
            let score = offset.normalized.dot(direction) * 6 + rangePreference * 1.5 - risk.receiver * 0.3
            if score > bestScore { bestScore = score; best = DistributionChoice(targetID: candidate.id, plan: plan) }
        }
        return best ?? DistributionChoice(targetID: nil, plan: KeeperDeliveryPlanner.space(origin: ball.position,
            aim: direction, hands: hands, heldFor: duration, ability: quality, tuning: tuning))
    }

    private mutating func releaseKeeperBall(by actor: Int, aim: Vector2, heldFor duration: Double, human: Bool) {
        releaseDistribution(by: actor, choice: distributionChoice(from: actor, aim: aim,
            heldFor: duration, hands: true), heldFor: duration, human: human)
    }

    private mutating func releaseDistribution(by actor: Int, choice: DistributionChoice,
                                              heldFor duration: Double, human: Bool) {
        let held = duration >= tuning.holdThreshold
        let plan = choice.plan
        activePassTargetID = choice.targetID
        lastDistributionKind = plan.kind
        if human { lastKickKind = plan.kind.rawValue }
        // The planner has already used ability to bound the launch. Compensate only for the
        // existing shared pass multiplier; actual execution keeps its bounded accuracy error.
        kickBall(by: actor, aim: plan.direction, speed: plan.speed / max(0.1, roster[actor].abilities.passPower),
                 isShot: false, human: human)
        ball.height = plan.height
        ball.verticalVelocity = plan.verticalVelocity
        chipRemaining = 0
        earlyPassAdjustment = nil
        if choice.targetID != nil, human { receiverControlRemaining = max(4, plan.flightTime + 1.5) }
        if held, human, tuning.aftertouchDuration > 0 {
            originalShotDirection = ball.velocity.normalized
            curveAngle = 0
            curveRemaining = tuning.aftertouchDuration
            kickInputBaseline = validMovement
        } else { endAftertouch() }
        // A quick outlet finishes the caught dive's recovery at the same position.
        // Its release pose must not remain hidden underneath a completed catch pose.
        if var keeper = keeperStates[actor] {
            keeper.diveRemaining = 0
            keeper.recoveryRemaining = 0
            keeper.recoveryPoseExtent = 0
            keeperStates[actor] = keeper
        }
        roster[actor].goalkeeperDiveProgress = 0
        roster[actor].goalkeeperReleaseProgress = 0.001
        roster[actor].goalkeeperReleaseKind = plan.kind == .underarmThrow ? .underarmThrow
            : plan.kind == .groundGoalKick || plan.kind == .loftedGoalKick || plan.kind == .longGoalKick ? .goalKick : .overarmThrow
        roster[actor].goalkeeperReleaseDirection = ball.velocity.normalized
    }

    private func assistedShotDirection(from actor: Int, aim: Vector2) -> Vector2? {
        let attack = ends.attackSign(for: roster[actor].team)
        let goal = Vector2(x: 0, y: Pitch.length / 2 * attack)
        let offset = goal - ball.position
        guard offset.length <= min(32, tuning.shotAssistRange), offset.y * attack > 0,
              aim.dot(offset.normalized) >= cos(tuning.shotAssistAngle * .pi / 180) else { return nil }
        return offset.normalized
    }

    /// A short, deliberate passing option wins. Otherwise a goalward tap in the
    /// danger area uses the same on-target shot physics as a minimally charged shot.
    private func shouldShootQuickTap(from actor: Int, aim: Vector2, target: Int?) -> Bool {
        guard mode == .match, matchRestart == nil, freeKickReadyTeam == nil,
              !roster[actor].isGoalkeeper,
              assistedShotDirection(from: actor, aim: aim.normalized) != nil else { return false }
        let goal = ends.direction(for: roster[actor].team) * (Pitch.length / 2)
        guard (goal - ball.position).length <= 24 else { return false }
        if let target, !roster[target].isUnavailable,
           (roster[target].state.position - roster[actor].state.position).length <= 18 { return false }
        return choosePassTarget(from: actor, aim: aim, maximumDistance: 18) == nil
    }

    var quickTapWillShoot: Bool {
        guard hasControl else { return false }
        let aim = actionPassIntent?.aim ?? intendedKickAim(for: selectedPlayerID)
        return shouldShootQuickTap(from: selectedPlayerID, aim: aim, target: actionPassIntent?.targetID)
    }

    private func quickPassTarget(from actor: Int, aim: Vector2) -> Int? {
        let target = choosePassTarget(from: actor, aim: aim)
        return shouldShootQuickTap(from: actor, aim: aim, target: target) ? nil : target
    }

    /// Used for touch cancellation, pause and interruption. This never releases a kick.
    mutating func cancelInput() {
        earlyPassAdjustment = nil
        movement = .zero
        rearPressure.removeAll()
        recentKickAim = nil
        recentKickAimActorID = nil
        recentKickAimRemaining = 0
        actionTimestamp = nil
        actionReverseAt = nil
        actionSawForwardStick = false
        actionDown = false
        actionPassIntent = nil
        actionCancelled = false
        actionWasTackle = false
        actionReceiving = false
        actionHeading = false
        actionHeaderOnPress = false
        actionReceivingRemaining = 0
        actionAllowsManualSwitch = false
        actionStartedWithSelectionDirection = false
        actionCommittedSlide = false
        actionUsesTimestamps = false
        actionElapsed = 0
        endAftertouch()
        chipRemaining = 0
        kickInputBaseline = nil
        queuedPass = nil
        queuedHeader = nil
        for index in roster.indices {
            roster[index].isTackling = false
            roster[index].isSliding = false
        }
        // The collision aftermath owns this physical pose; pausing only cancels human input.
        if let foul = pendingFoul ?? lastFoul, foulOffenderWasSliding,
           phase == .foulContact(team: foul.awardedTeam) || phase == .freeKick(team: foul.awardedTeam) {
            roster[foul.offenderID].isSliding = true
        }
        tackleTimers.removeAll()
        tackleDirections.removeAll()
        tackleKinds.removeAll()
    }

    mutating func reset(clearScore: Bool = false, preserveStartingEnds: Bool = false) {
        clearRestartSupport()
        resetOffsideForRestart()
        penaltyFlight = nil
        penaltySecondTouchTakerID = nil
        penaltyDoubleTouchCount = 0
        offsideCount = 0
        let clearScore = clearScore || mode == .match
        cancelInput()
        matchTimeElapsed = 0
        matchHalf = 1
        ends = MatchEnds()
        periodElapsed = 0
        stoppageTime = 0
        periodHasStarted = false
        opportunityGraceRemaining = 0
        pendingInjuryID = nil
        substitutionNotice = nil
        substitutionNoticeRemaining = 0
        unavailableSquadIDs.removeAll()
        matchRestart = nil
        lastTouchTeam = nil
        lastDeliberatePlayTeam = nil
        handlingRestrictedTeam = nil
        keeperHandsID = nil
        throughBallLandingPoint = nil
        goalkeeperSaveCount = 0
        headerCount = 0
        crossCount = 0
        crossFlight = nil
        lastHeaderPlayerID = nil
        headingTimers.removeAll()
        keeperStates.removeAll()
        keeperIntents.removeAll()
        selectedPlayerID = 0
        roster = [Footballer(id: 0, team: .blue, state: PlayerState())]
        ball = BallState()
        ball.mode = .free
        controlClaim = false
        dribbleCountdown = 0
        reacquisitionCountdown = 0
        restartCountdown = 0
        phase = .playing
        possessionID = nil
        activePassTargetID = nil
        receiverControlRemaining = 0
        runningWinProtection = 0
        runningWinOwnerID = nil
        lastKickerID = nil
        recentReceiverID = nil
        recentReceptionRemaining = 0
        kickGuards.removeAll()
        recoveryTimers.removeAll()
        tackleHits.removeAll()
        switchCountdown = 0
        switchCandidateID = nil
        switchCandidateElapsed = 0
        pendingFoul = nil
        foulContactElapsed = 0
        foulOffenderWasSliding = false
        aiDecisionCountdown = 1
        freeKickReadyTeam = nil
        lastFoul = nil
        randomState = 0x51CC_E2D4
        abilityKickSequence = 0
        if mode == .passing { configureExercise() }
        else if mode == .match { configureMatch(chooseEnds: !preserveStartingEnds) }
        resetGeneration += 1
        if clearScore {
            northGoals = 0
            southGoals = 0
            kickCount = 0
            lastKick = nil
            lastKickKind = nil
            lastDistributionKind = nil
            tackleCount = 0
            switchCount = 0
            standingTackleCount = 0
            runningChallengeCount = 0
            challengeContactCount = 0
            lastChallengeWasSlide = false
            slideCount = 0
            chipCount = 0
            earlyPassAdjustmentCount = 0
            lastEarlyPassAdjustmentAngle = 0
            queuedPassCount = 0
            foulCount = 0
        }
    }

    /// Starts another timed period from kickoff while retaining the regulation score.
    /// Tournament presentation owns whether this is extra time; the simulation only needs
    /// a fresh, shorter match period with the same two teams and score.
    mutating func startAdditionalPeriod(duration: Double) {
        guard mode == .match, duration.isFinite, duration > 0 else { return }
        let savedNorthGoals = northGoals
        let savedSouthGoals = southGoals
        let savedRoster = roster
        let savedUnavailable = unavailableSquadIDs
        let savedInjuryRandom = injuryRandomState
        reset(clearScore: true, preserveStartingEnds: true)
        roster = savedRoster
        unavailableSquadIDs = savedUnavailable
        injuryRandomState = savedInjuryRandom
        prepareMatchRestart(MatchRestart(kind: .kickoff, team: .blue, position: .zero, takerID: nil))
        tuning.matchDuration = duration
        northGoals = savedNorthGoals
        southGoals = savedSouthGoals
    }

#if DEBUG
    /// Test-build match shortcut. Production results can only reach full time through the clock.
    mutating func debugFinishMatch(northGoals: Int, southGoals: Int) {
        guard mode == .match else { return }
        self.northGoals = max(0, northGoals)
        self.southGoals = max(0, southGoals)
        finishMatch()
    }
#endif

    private var validMovement: Vector2 {
        guard movement.x.isFinite, movement.y.isFinite else { return .zero }
        return movement.clampedLength(1)
    }

    /// Touch events can change direction and lift again between fixed ticks. Remember those
    /// deliberate samples immediately, without advancing an input clock or triggering a kick.
    private mutating func rememberDeliberateKickAim() {
        guard phase == .playing, !isTackling,
              validMovement.length >= max(0.01, tuning.kickAimStickThreshold),
              lastKickerID != selectedPlayerID || (curveRemaining <= 0 && chipRemaining <= 0) else { return }
        recentKickAim = validMovement.normalized
        recentKickAimActorID = selectedPlayerID
        recentKickAimRemaining = max(0, tuning.kickAimMemoryDuration)
        if actionDown, actionActorID == selectedPlayerID, !actionWasTackle, !actionCancelled {
            let direction = validMovement.normalized
            if direction.dot(actionForward) > 0.55 { actionSawForwardStick = true; actionReverseAt = nil }
            if actionSawForwardStick, direction.dot(actionForward) < -0.7,
               actionKickAim.dot(actionForward) >= -0.7 {
                actionReverseAt = actionTimestamp.flatMap { start in movementTimestamp.map { max(0, $0 - start) } }
                    ?? actionElapsed
            }
            actionKickAim = direction
        }
    }

    /// Retain a deliberate kick direction through thumb lift and small centre-stick noise.
    /// A strong release direction still wins, including for a queued first-time action.
    private func intendedKickAim(for actor: Int) -> Vector2 {
        if validMovement.length >= max(0.01, tuning.kickAimStickThreshold) { return validMovement.normalized }
        if actionDown, actionActorID == actor { return actionKickAim }
        if recentKickAimActorID == actor, recentKickAimRemaining > 0, let recentKickAim { return recentKickAim }
        return roster[actor].state.facing
    }

    private func charge(for duration: Double) -> Double {
        min(1, max(0, (duration - tuning.holdThreshold) / max(0.001, tuning.fullChargeDuration)))
    }

    private mutating func movePlayer(dt: Double, coasting: Bool) {
        let stick = coasting ? Vector2.zero : validMovement
        let boost = (hasControl ? 1.0 : max(1, tuning.offBallSpeedBoost))
            * ((recoveryTimers[selectedPlayerID] ?? 0) > 0 ? 0.4 : 1.0)
        let requested = stick * max(0, tuning.playerMaxSpeed * boost)
        let acceleration = stick.length > 0.0001 ? tuning.playerAcceleration : tuning.playerDeceleration
        player.velocity += (requested - player.velocity).clampedLength(max(0, acceleration) * dt)

        if stick.length > 0.0001 {
            let desired = atan2(stick.y, stick.x)
            let current = atan2(player.facing.y, player.facing.x)
            let difference = atan2(sin(desired - current), cos(desired - current))
            let turn = min(abs(difference), max(0, tuning.playerTurnRate) * dt)
            player.facing = player.facing.rotated(by: difference < 0 ? -turn : turn).normalized
        }
        player.position += player.velocity * dt

        let xLimit = Pitch.width / 2 - Pitch.playerRadius
        let yLimit = Pitch.length / 2 - Pitch.playerRadius
        if abs(player.position.x) > xLimit {
            player.position.x = min(xLimit, max(-xLimit, player.position.x))
            player.velocity.x = 0
        }
        if abs(player.position.y) > yLimit {
            player.position.y = min(yLimit, max(-yLimit, player.position.y))
            player.velocity.y = 0
        }
    }

    private mutating func refreshControl(allowAcquisition: Bool = true) {
        let separation = (ball.position - player.position).length
        let relativeSpeed = (ball.velocity - player.velocity).length
        if controlClaim {
            controlClaim = reacquisitionCountdown <= 0
                && ball.height <= tuning.airborneContactHeight && !isTackling
                && separation <= tuning.controlReleaseDistance
                && relativeSpeed <= tuning.controlRelativeSpeed * 1.25
            if !controlClaim, ball.mode == .controlled { ball.mode = .free }
        } else if allowAcquisition, reacquisitionCountdown <= 0, !isTackling, queuedPass == nil,
                  canAcquireLooseBall(with: player, playerID: selectedPlayerID) {
            controlClaim = true
            ball.mode = .controlled
            dribbleCountdown = 0
            endAftertouch()
        }
        if actionDown, !actionWasTackle, !actionReceiving, !actionHeading, !controlClaim { actionCancelled = true }
    }

    private func canAcquireLooseBall(with state: PlayerState, playerID: Int? = nil) -> Bool {
        let offset = ball.position - state.position
        let relativeVelocity = ball.velocity - state.velocity
        guard ballIsStillInPlay(), ball.height <= tuning.airborneContactHeight,
              offset.length <= acquisitionReach(for: playerID),
              relativeVelocity.length <= acquisitionSpeedLimit(for: playerID) else { return false }
        // A wider foot reach helps a close stationary/incoming ball, without pulling an escaping
        // ball back from a boundary or attracting fast shots before physical contact.
        return offset.length <= Pitch.playerRadius + Pitch.ballRadius
            || (!ballNeedsBoundaryRescue && relativeVelocity.dot(offset.normalized) <= 0.5)
    }

    private mutating func nudgeBallIfReachable() {
        guard controlClaim, !isTackling, queuedPass == nil, dribbleCountdown <= 0,
              ball.height <= tuning.airborneContactHeight else { return }
        let offset = ball.position - player.position
        guard offset.length <= tuning.dribbleReach else { return }
        let speed = player.velocity.length
        if speed < 0.35 {
            // A reachable cushioning touch, without moving the ball to a scripted location.
            ball.velocity *= 0.25
        } else {
            let direction = player.velocity.normalized
            let forwardGap = offset.dot(direction)
            // Turning away exposes a ball behind the player instead of pulling it around their body.
            guard forwardGap >= -0.75 else { return }
            let preferredGap = 1.0 + 0.22 * min(1, speed / max(0.1, tuning.playerMaxSpeed))
            let touchSpeed = max(0, speed + min(4.5, (preferredGap - forwardGap) * 7))
            let lateralGap = offset - direction * forwardGap
            ball.velocity = (direction * touchSpeed - lateralGap * 10).clampedLength(speed + 4.5)
        }
        ball.mode = .controlled
        dribbleCountdown = max(0.01, tuning.dribbleTouchInterval)
    }

    private mutating func applyAftertouch(dt: Double) {
        guard curveRemaining > 0 else { return }
        guard acceptsFreshKickInput() else {
            curveRemaining = max(0, curveRemaining - dt)
            aftertouchVector = .zero
            return
        }
        guard ball.mode == .shot || ball.mode == .pass, ball.velocity.length > 0.1 else {
            endAftertouch()
            return
        }
        let effectiveDT = min(dt, curveRemaining)
        let duration = max(0.001, tuning.aftertouchDuration)
        let envelope = pow(max(0, (curveRemaining - effectiveDT / 2) / duration),
                           max(0, tuning.aftertouchDecay))
        let lateral = validMovement.dot(originalShotDirection.perpendicular)
        let response = lateral * tuning.aftertouchStrength * envelope
        let limit = max(0, tuning.aftertouchMaxAngle) * .pi / 180
        let nextAngle = min(limit, max(-limit, curveAngle + response * effectiveDT))
        ball.velocity = ball.velocity.rotated(by: nextAngle - curveAngle)
        curveAngle = nextAngle
        aftertouchVector = originalShotDirection.perpendicular * response
        curveRemaining = max(0, curveRemaining - dt)
        if curveRemaining <= 0 { endAftertouch() }
    }

    private mutating func endAftertouch() {
        curveRemaining = 0
        curveAngle = 0
        aftertouchVector = .zero
    }

    private enum Contact {
        case post(Vector2)
        case player(Int)
        case control(Int)
        case runningChallenge(Int)
        case goalkeeper(Int, GoalkeeperAI.SaveOutcome)
        case queuedPass(Int)
        case header(Int)
        case slideBall(Int)
        case foul(offender: Int, victim: Int, behind: Bool, relativeSpeed: Double)
        case boundary(north: Bool?)
    }

    /// Every ball, stretched-foot and boundary event competes on the same swept timeline.
    /// A queue or slide can save a ball before its crossing, never after it has left play.
    private mutating func advanceBall(dt: Double) {
        let xBoundary = Pitch.width / 2 + Pitch.ballRadius
        let yBoundary = Pitch.length / 2 + Pitch.ballRadius
        if abs(ball.position.x) > xBoundary { finishAtBoundary(north: nil); return }
        if abs(ball.position.y) > yBoundary { finishAtBoundary(north: ball.position.y > 0); return }
        let posts = [Vector2(x: -Pitch.goalWidth / 2, y: Pitch.length / 2),
                     Vector2(x: Pitch.goalWidth / 2, y: Pitch.length / 2),
                     Vector2(x: -Pitch.goalWidth / 2, y: -Pitch.length / 2),
                     Vector2(x: Pitch.goalWidth / 2, y: -Pitch.length / 2)]
        var remaining = dt
        var elapsed = 0.0
        var glancedPlayers: Set<Int> = []
        for _ in 0..<10 {
            guard remaining > 0.0000001 else { return }
            let segmentBall = ball
            let speed = ball.velocity.length
            let friction = ball.height > 0.001 || ball.verticalVelocity > 0
                ? 0 : max(0, tuning.ballFriction)
            let rollingTime = friction > 0 ? min(remaining, speed / friction) : remaining
            let travel = max(0, speed * rollingTime - 0.5 * friction * rollingTime * rollingTime)
            let displacement = ball.velocity.normalized * travel
            var earliest = 1.0
            var contact: Contact?
            func eligibleHeight(_ fraction: Double, maximum: Double) -> Bool {
                BallFlight.height(after: remaining * fraction, ball: segmentBall,
                                  gravity: tuning.ballGravity) <= maximum
            }
            func positionAtSegmentStart(_ id: Int) -> Vector2 {
                guard id < previousFootballerPositions.count else { return roster[id].state.position }
                let previous = previousFootballerPositions[id]
                return previous + (roster[id].state.position - previous) * min(1, elapsed / dt)
            }
            func actorTravel(_ id: Int) -> Vector2 {
                roster[id].state.position - positionAtSegmentStart(id)
            }
            func ballTouchTime(_ id: Int, radius: Double) -> Double? {
                let start = positionAtSegmentStart(id)
                let relativeOffset = ball.position - start
                if relativeOffset.length <= radius { return 0 }
                return sweptCircle(from: relativeOffset, by: displacement - actorTravel(id),
                                   center: .zero, radius: radius)
            }

            for post in posts {
                if let time = sweptCircle(from: ball.position, by: displacement, center: post,
                                          radius: Pitch.ballRadius + Pitch.postRadius),
                   time <= earliest, eligibleHeight(time, maximum: Pitch.crossbarHeight) {
                    earliest = time
                    contact = .post(post)
                }
            }
            for footballer in roster where eligibleHeader(footballer.id) {
                let id = footballer.id
                let humanAttempt = queuedHeader?.actorID == id
                // AI commits only to a descending ball at head height. A high clearance
                // passes over the line; outfield opponents cannot collect it with their feet.
                let aiAttempt = mode != .solo && footballer.team == .red && tuning.aiSpeedScale > 0
                    && !(lastKickerID == id && activePassTargetID != nil)
                    && segmentBall.verticalVelocity < 0 && segmentBall.height <= HeadingMechanics.maximumHeight
                    && (segmentBall.position - positionAtSegmentStart(id)).length <= HeadingMechanics.reach + 0.4
                // Receive a short friendly throw at the feet when it is already reachable.
                // Automatic headers must not turn a simple outlet into a volley back at its thrower.
                let canCushion = aiAttempt && !isAttackingCross(for: id) && isIntendedFriendlyPass(to: id)
                    && neutralReceivingMeeting(for: id, reach: acquisitionReach(for: id), horizon: 0.4,
                        maximumRelativeSpeed: acquisitionSpeedLimit(for: id)) != nil
                guard humanAttempt || (aiAttempt && !canCushion) else { continue }
                var delay = 0.0
                if humanAttempt, queuedHeader?.goalDirected == true {
                    var jumper = footballer
                    jumper.state.position = positionAtSegmentStart(id)
                    // A prepared jump meets the centre of the cross if reachable, instead of
                    // always glancing it at the outer edge of the collision circle. A block,
                    // save or boundary earlier on this same timeline still wins.
                    guard let preferred = HeadingMechanics.preferredContactDelay(ball: segmentBall,
                        player: jumper, window: min(0.2, queuedHeader!.remaining), gravity: tuning.ballGravity),
                        preferred < remaining else { continue }
                    delay = preferred
                }
                var contactBall = segmentBall
                BallFlight.advance(&contactBall, dt: delay, gravity: tuning.ballGravity)
                let startFraction = delay / remaining
                let relativeTravel = displacement - actorTravel(id)
                if let fraction = HeadingMechanics.contactFraction(ball: contactBall,
                    relativeOffset: segmentBall.position - positionAtSegmentStart(id) + relativeTravel * startFraction,
                    relativeTravel: relativeTravel * (1 - startFraction), duration: remaining - delay, gravity: tuning.ballGravity) {
                    let time = startFraction + (1 - startFraction) * fraction
                    if time < earliest,
                       !humanAttempt || elapsed + remaining * time <= (queuedHeader?.remaining ?? 0) {
                        earliest = time
                        contact = .header(id)
                    }
                }
            }
            for footballer in roster where !footballer.isUnavailable {
                let id = footballer.id
                if footballer.isGoalkeeper && (mode != .match || canHandleBall(id)) { continue }
                let guardActive = mode == .solo ? reacquisitionCountdown > 0 : (kickGuards[id] ?? 0) > 0
                let canQueue = queuedPass?.actorID == id && !guardActive
                    && (possessionID == nil || possessionID == id)
                let canSlide = footballer.isSliding && !tackleHits.contains(id)
                let owner = mode == .solo ? (controlClaim ? selectedPlayerID : nil) : possessionID
                guard canQueue || canSlide || (owner != id && !guardActive && !glancedPlayers.contains(id)) else { continue }
                let start = positionAtSegmentStart(id)
                let offset = ball.position - start
                let relativeVelocity = ball.velocity - footballer.state.velocity
                let canAcquire = owner == nil && !canQueue && !footballer.isTackling && !ballNeedsBoundaryRescue
                    && relativeVelocity.length <= acquisitionSpeedLimit(for: id)
                    && relativeVelocity.dot(offset.normalized) <= 0.5
                let radius = canQueue ? tuning.queuedPassReach : canSlide ? tuning.slideReach
                    : canAcquire ? acquisitionReach(for: id)
                    : Pitch.playerRadius + Pitch.ballRadius
                if let time = ballTouchTime(id, radius: max(0.1, radius)), time < earliest,
                   eligibleHeight(time, maximum: tuning.airborneContactHeight),
                   !canQueue || elapsed + remaining * time <= (queuedPass?.remaining ?? 0) {
                    earliest = time
                    contact = canQueue ? .queuedPass(id) : canSlide ? .slideBall(id)
                        : canAcquire ? .control(id) : .player(id)
                }
            }

            if mode == .match {
                for keeper in roster where keeper.isGoalkeeper && !keeper.isUnavailable && (kickGuards[keeper.id] ?? 0) <= 0
                    && handlingRestrictedTeam != keeper.team {
                    if let owner = possessionID, roster[owner].team == keeper.team { continue }
                    let state = keeperStates[keeper.id] ?? GoalkeeperAI.State()
                    let profile = GoalkeeperAI.contactProfile(state: state, configuration: keeperConfiguration(for: keeper.id))
                    guard let time = ballTouchTime(keeper.id, radius: profile.reach), time <= earliest,
                          eligibleHeight(time, maximum: profile.maximumHeight) else { continue }
                    var candidateBall = segmentBall
                    candidateBall.position += displacement * time
                    candidateBall.velocity = candidateBall.velocity.normalized * max(0, speed - friction * remaining * time)
                    BallFlight.advance(&candidateBall, dt: remaining * time, gravity: tuning.ballGravity)
                    var candidateKeeper = keeper.state
                    candidateKeeper.position = positionAtSegmentStart(keeper.id) + actorTravel(keeper.id) * time
                    if let outcome = GoalkeeperAI.saveOutcome(ball: candidateBall, keeper: candidateKeeper,
                                                              team: keeper.team, state: state,
                                                              configuration: keeperConfiguration(for: keeper.id)) {
                        earliest = time
                        contact = .goalkeeper(keeper.id, outcome)
                    }
                }
            }

            var pressureWindows: [Int: (owner: Int, entry: Double, exit: Double)] = [:]
            if mode != .solo, let owner = possessionID, freeKickReadyTeam == nil,
               !(runningWinProtection > 0 && runningWinOwnerID == owner) {
                let ownerStart = positionAtSegmentStart(owner)
                for actor in roster where canAttemptRunningChallenge(actor.id, against: owner,
                                                                     from: positionAtSegmentStart(actor.id),
                                                                     ownerPosition: ownerStart) {
                    let id = actor.id
                    let start = positionAtSegmentStart(id)
                    let behind = (start - ownerStart).normalized.dot(roster[owner].state.facing) < -0.35
                    if behind {
                        guard let body = sweptCircleInterval(from: start - ownerStart,
                                                             by: actorTravel(id) - actorTravel(owner),
                                                             radius: max(0.1, tuning.rearPressureBodyReach)),
                              let foot = sweptCircleInterval(from: ball.position - start,
                                                             by: displacement - actorTravel(id),
                                                             radius: max(0.1, tuning.rearPressureBallReach)) else { continue }
                        let entry = max(body.0, foot.0)
                        let exit = min(body.1, foot.1)
                        guard entry <= exit, eligibleHeight(entry, maximum: tuning.airborneContactHeight),
                              eligibleHeight(exit, maximum: tuning.airborneContactHeight) else { continue }
                        pressureWindows[id] = (owner, entry, exit)
                        let previous = entry <= 0.000001 && rearPressure[id]?.ownerID == owner
                            ? rearPressure[id]!.elapsed : 0
                        let required = max(0, max(0.01, tuning.rearPressureDuration) - previous)
                        let time = entry + required / remaining
                        if time <= exit + 0.0000001, time <= earliest,
                           eligibleHeight(time, maximum: tuning.airborneContactHeight) {
                            earliest = max(0, time)
                            contact = .runningChallenge(id)
                        }
                    } else if let time = ballTouchTime(id, radius: max(0.1, tuning.passiveControlReach)),
                              time <= earliest, eligibleHeight(time, maximum: tuning.airborneContactHeight) {
                        earliest = time
                        contact = .runningChallenge(id)
                    }
                }
            }

            for tackler in roster where tackler.isSliding && !tackler.isUnavailable && !tackleHits.contains(tackler.id) {
                let id = tackler.id
                let tacklerStart = positionAtSegmentStart(id)
                let possibleBallTime = ballTouchTime(id, radius: max(0.1, tuning.slideReach))
                let ballTime = possibleBallTime.flatMap { eligibleHeight($0, maximum: tuning.airborneContactHeight) ? $0 : nil }
                for opponent in roster where opponent.team != tackler.team && !opponent.isUnavailable {
                    let otherStart = positionAtSegmentStart(opponent.id)
                    let relative = tacklerStart - otherStart
                    let relativeTravel = actorTravel(id) - actorTravel(opponent.id)
                    let bodyTime: Double?
                    if relative.length <= Pitch.playerRadius * 2 + 0.0001 { bodyTime = 0 }
                    else { bodyTime = sweptCircle(from: relative, by: relativeTravel, center: .zero,
                                                  radius: Pitch.playerRadius * 2) }
                    guard let time = bodyTime, time <= earliest else { continue }
                    // A ball-first tackle is clean for the whole commitment, even if bodies meet afterwards.
                    guard ballTime == nil || ballTime! > time else { continue }
                    let behind = relative.normalized.dot(opponent.state.facing) < -0.4
                    earliest = time
                    contact = .foul(offender: id, victim: opponent.id, behind: behind,
                                    relativeSpeed: (tackler.state.velocity - opponent.state.velocity).length)
                }
            }

            let boundaries: [(Double, Double, Double, Bool?)] = [
                (ball.position.x, displacement.x, xBoundary, nil),
                (ball.position.x, displacement.x, -xBoundary, nil),
                (ball.position.y, displacement.y, yBoundary, true),
                (ball.position.y, displacement.y, -yBoundary, false)
            ]
            for (origin, delta, boundary, north) in boundaries where abs(delta) > 0.0000001 {
                guard delta * boundary > 0 else { continue }
                let time = (boundary - origin) / delta
                if time >= 0, time <= earliest {
                    earliest = time
                    contact = .boundary(north: north)
                }
            }

            // Count only the pursuit that actually happened before the chosen event. A boundary
            // or an earlier contact can never be rescued by pressure from the future of this tick.
            advanceRearPressure(windows: pressureWindows, through: earliest, duration: remaining)
            let segmentTime = remaining * earliest
            ball.position += displacement * earliest
            ball.velocity = ball.velocity.normalized * max(0, speed - friction * segmentTime)
            BallFlight.advance(&ball, dt: segmentTime, gravity: tuning.ballGravity)
            elapsed += segmentTime
            remaining -= segmentTime
            guard let contact else { return }
            earlyPassAdjustment = nil
            offsideTouchPositions = roster.indices.map { positionAtSegmentStart($0) }
            defer { offsideTouchPositions = nil }
            let involved: Int?
            switch contact {
            case .control(let id), .player(let id), .queuedPass(let id), .slideBall(let id),
                 .runningChallenge(let id), .goalkeeper(let id, _), .header(let id): involved = id
            case .foul(let offender, _, _, _):
                involved = (ball.position - positionAtSegmentStart(offender)).length <= tuning.slideReach + 0.5 ? offender : nil
            default: involved = nil
            }
            if let involved, penaliseOffsideInvolvement(by: involved) { return }
            switch contact {
            case .boundary(let north):
                finishAtBoundary(north: north)
                return
            case .post(let center):
                let normal = contactNormal(center: center, travel: displacement)
                ball.position = center + normal * (Pitch.ballRadius + Pitch.postRadius + 0.0001)
                ball.velocity = reflected(ball.velocity, normal: normal) * 0.78
                loseControlOnContact()
            case .control(let id):
                receiveBall(by: id)
            case .runningChallenge(let id):
                let previousOwner = possessionID
                receiveBall(by: id)
                if id == selectedPlayerID { runningChallengeCount += 1 }
                if id == selectedPlayerID || previousOwner == selectedPlayerID {
                    challengeContactCount += 1
                    lastChallengeWasSlide = false
                }
                runningWinOwnerID = id
                runningWinProtection = 0.35
                if let previousOwner { kickGuards[previousOwner] = max(kickGuards[previousOwner] ?? 0, 0.35) }
            case .goalkeeper(let id, let outcome):
                recordBallTouch(by: id, save: true)
                goalkeeperSaveCount += 1
                var state = keeperStates[id] ?? GoalkeeperAI.State()
                GoalkeeperAI.recordSave(state: &state, outcome: outcome, configuration: keeperConfiguration(for: id))
                keeperStates[id] = state
                switch outcome {
                case .catchBall:
                    pendingOffside = nil
                    possessionID = id
                    keeperHandsID = id
                    if roster[id].team == .blue { selectBlue(id) }
                    controlClaim = selectedPlayerID == id
                    activePassTargetID = nil
                    queuedPass = nil
                    ball.mode = .controlled
                    ball.velocity = .zero
                    ball.verticalVelocity = 0
                    roster[id].state.position = positionAtSegmentStart(id)
                    roster[id].state.velocity = .zero
                    ball.position = roster[id].state.position + (ends.direction(for: roster[id].team)) * 0.6
                    ball.height = 1
                    endAftertouch()
                    chipRemaining = 0
                    if actionDown { actionCancelled = true }
                    return
                case .parry(let velocity, let verticalVelocity):
                    loseControlOnContact()
                    ball.velocity = velocity
                    ball.verticalVelocity = verticalVelocity
                    kickGuards[id] = 0.20
                }
            case .queuedPass(let id):
                executeQueuedPass(by: id)
            case .header(let id):
                let human = queuedHeader?.actorID == id
                let aim = human ? queuedHeader!.aim : (ends.direction(for: roster[id].team)
                    + Vector2(x: -ball.position.x * 0.015, y: 0)).normalized
                let preparedFor = human ? HeadingMechanics.prepareWindow - queuedHeader!.remaining + elapsed : 0.11
                performHeader(by: id, aim: aim, human: human, preparedFor: preparedFor)
            case .slideBall(let id):
                knockBallFromTackle(by: id)
            case .foul(let offender, let victim, let behind, let relativeSpeed):
                let decision = TackleRules.assess(kind: .slide, ballContactFraction: nil,
                                                  opponentContactFraction: 0, approachFromBehind: behind,
                                                  relativeSpeed: relativeSpeed, randomUnit: nextRandomUnit())
                // Restore all actors to the actual swept body-contact instant before the fall.
                for id in roster.indices { roster[id].state.position = positionAtSegmentStart(id) }
                commitFoul(offender: offender, victim: victim, decision: decision)
                return
            case .player(let id):
                recordBallTouch(by: id)
                var receiver = roster[id].state
                receiver.position = positionAtSegmentStart(id)
                let normal = contactNormal(center: receiver.position, travel: displacement)
                ball.position = receiver.position + normal * (Pitch.ballRadius + Pitch.playerRadius + 0.0001)
                if mode != .solo, let owner = possessionID, owner != id, !roster[id].isTackling {
                    // A protected dribble can glance a body, but ownership only changes through
                    // the shared running-challenge event. This also protects friendly possession.
                    ball.velocity = reflected(ball.velocity, normal: normal) * 0.35 + roster[owner].state.velocity * 0.65
                    glancedPlayers.insert(id)
                    endAftertouch()
                    chipRemaining = 0
                    continue
                }
                if mode != .solo, (ball.velocity - receiver.velocity).length <= (roster[id].isGoalkeeper ? tuning.keeperFootControlSpeed : tuning.receivingSpeed) * roster[id].abilities.control,
                   !roster[id].isTackling {
                    receiveBall(by: id)
                } else {
                    ball.velocity = reflected(ball.velocity - receiver.velocity, normal: normal) * 0.45 + receiver.velocity
                    loseControlOnContact()
                    kickGuards[id] = 0.12
                    if mode == .solo { reacquisitionCountdown = 0.12 }
                }
            }
            if ball.velocity.length <= 0.1 { endAftertouch(); chipRemaining = 0 }
        }
        // A contact budget prevents overlapping bodies from generating an unbounded loop.
        ball.velocity = .zero
        BallFlight.advance(&ball, dt: remaining, gravity: tuning.ballGravity)
    }

    /// Running challenges require an active approach, not a passive overlapping body. Rear
    /// pursuit uses carrier distance as well as ball distance so ordinary body shielding is feasible.
    private func canAttemptRunningChallenge(_ id: Int, against owner: Int,
                                            from position: Vector2, ownerPosition: Vector2) -> Bool {
        let actor = roster[id]
        let carrier = roster[owner]
        guard id != owner, actor.team != carrier.team,
              !actor.isUnavailable, !actor.isGoalkeeper, !actor.isTackling,
              !carrier.isUnavailable, keeperHandsID != owner,
              (recoveryTimers[id] ?? 0) <= 0, (kickGuards[id] ?? 0) <= 0,
              queuedPass?.actorID != id, actor.state.velocity.length >= 1,
              ball.height <= tuning.airborneContactHeight,
              (ball.velocity - actor.state.velocity).length <= tuning.controlRelativeSpeed * 1.5 else { return false }
        let toBall = (ball.position - position).normalized
        let toCarrier = (ownerPosition - position).normalized
        let motion = actor.state.velocity
        guard max(motion.dot(toBall), motion.dot(toCarrier)) >= 0.5 else { return false }
        if id == selectedPlayerID {
            return validMovement.length > 0.1 && max(validMovement.dot(toBall), validMovement.dot(toCarrier)) > 0.25
        }
        return true
    }

    private mutating func advanceRearPressure(windows: [Int: (owner: Int, entry: Double, exit: Double)],
                                             through fraction: Double, duration: Double) {
        var next: [Int: RearPressure] = [:]
        for (id, window) in windows {
            guard fraction >= window.entry, fraction <= window.exit + 0.0000001 else { continue }
            let prior = window.entry <= 0.000001 && rearPressure[id]?.ownerID == window.owner
                ? rearPressure[id]!.elapsed : 0
            let elapsed = prior + max(0, fraction - window.entry) * duration
            if elapsed > 0 { next[id] = RearPressure(ownerID: window.owner, elapsed: elapsed) }
        }
        rearPressure = next
    }

    /// Entry and exit fractions of simultaneous relative motion inside a reach circle.
    private func sweptCircleInterval(from offset: Vector2, by displacement: Vector2,
                                     radius: Double) -> (Double, Double)? {
        let a = displacement.lengthSquared
        let c = offset.lengthSquared - radius * radius
        guard a > 0.000000001 else { return c <= 0 ? (0, 1) : nil }
        let b = offset.dot(displacement)
        let discriminant = b * b - a * c
        guard discriminant >= 0 else { return nil }
        let root = sqrt(discriminant)
        let entry = max(0, (-b - root) / a)
        let exit = min(1, (-b + root) / a)
        return entry <= exit ? (entry, exit) : nil
    }

    private func sweptCircle(from start: Vector2, by displacement: Vector2,
                             center: Vector2, radius: Double) -> Double? {
        let offset = start - center
        let a = displacement.lengthSquared
        guard a > 0.000000001 else { return nil }
        let approach = offset.dot(displacement)
        let c = offset.lengthSquared - radius * radius
        if c <= 0 { return approach < 0 ? 0 : nil }
        guard approach < 0 else { return nil }
        let discriminant = approach * approach - a * c
        guard discriminant >= 0 else { return nil }
        let time = (-approach - sqrt(discriminant)) / a
        return time >= 0 && time <= 1 ? time : nil
    }

    private func contactNormal(center: Vector2, travel: Vector2) -> Vector2 {
        let offset = ball.position - center
        return offset.length > 0.000001 ? offset.normalized : -travel.normalized
    }

    private func reflected(_ vector: Vector2, normal: Vector2) -> Vector2 {
        vector - normal * (2 * min(0, vector.dot(normal)))
    }

    private mutating func loseControlOnContact() {
        keeperHandsID = nil
        throughBallLandingPoint = nil
        rearPressure.removeAll()
        endAftertouch()
        chipRemaining = 0
        controlClaim = false
        possessionID = nil
        activePassTargetID = nil
        if actionDown { actionCancelled = true }
        ball.mode = .free
    }

    private mutating func finishAtBoundary(north: Bool?) {
        keeperHandsID = nil
        throughBallLandingPoint = nil
        let clearMouth = Pitch.goalWidth / 2 - Pitch.postRadius - Pitch.ballRadius
        let isGoal = indirectKickTakerID == nil && north != nil && abs(ball.position.x) <= clearMouth
            && ball.height + Pitch.ballRadius * 2 <= Pitch.crossbarHeight
        if isGoal, let north {
            phase = .goal(north: north)
            // Historical property names also serve practice mode; match totals belong to blue/red.
            if mode == .match ? ends.attackingTeam(atNorthGoal: north) == .blue : north {
                northGoals += 1
            } else { southGoals += 1 }
        } else { phase = .outOfPlay }
        restartCountdown = max(0, tuning.restartDelay)
        if mode == .match {
            let kind: MatchRestartKind
            let team: Team
            let spot: Vector2
            if isGoal, let north {
                kind = .kickoff
                team = ends.attackingTeam(atNorthGoal: !north)
                spot = .zero
            } else if let north {
                let defending: Team = ends.attackingTeam(atNorthGoal: !north)
                let attacking: Team = ends.attackingTeam(atNorthGoal: north)
                if lastTouchTeam == defending {
                    kind = .corner
                    team = attacking
                    spot = Vector2(x: ball.position.x >= 0 ? Pitch.width / 2 - 0.8 : -Pitch.width / 2 + 0.8,
                                   y: north ? Pitch.length / 2 - 0.8 : -Pitch.length / 2 + 0.8)
                } else {
                    kind = .goalKick
                    team = defending
                    let side = ball.position.x >= 0 ? 1.0 : -1.0
                    spot = Vector2(x: side * RestartSupport.goalAreaHalfWidth,
                                   y: north ? Pitch.length / 2 - RestartSupport.goalAreaDepth
                                       : -Pitch.length / 2 + RestartSupport.goalAreaDepth)
                }
            } else {
                kind = .throwIn
                team = lastTouchTeam == .red ? .blue : .red
                spot = Vector2(x: ball.position.x > 0 ? Pitch.width / 2 - 0.8 : -Pitch.width / 2 + 0.8,
                               y: min(Pitch.length / 2 - 2, max(-Pitch.length / 2 + 2, ball.position.y)))
            }
            matchRestart = MatchRestart(kind: kind, team: team, position: spot, takerID: nil)
            if !isGoal {
                phase = .restart(kind: kind, team: team)
                restartCountdown = max(0, tuning.matchRestartDelay)
            }
        }
        controlClaim = false
        possessionID = nil
        activePassTargetID = nil
        ball.mode = .free
        ball.velocity = .zero
        ball.verticalVelocity = 0
        for index in roster.indices { roster[index].state.velocity = .zero }
        resetOffsideForRestart()
        cancelInput()
    }

    // MARK: - Quick match

    private func startingMatchPosition(for id: Int) -> Vector2 {
        if let configuration {
            let home = id < 11
            let lineup = home ? configuration.home : configuration.away
            let slot = id % 11
            if lineup.formation.slots.indices.contains(slot) {
                let formationSlot = lineup.formation.slots[slot]
                var position = formationSlot.position
                // Both sides start in their own half; formation slots also describe the
                // more expansive open-play shape used after the kickoff.
                switch formationSlot.role {
                case "G": break
                case "D": position.y = min(-25, position.y)
                case "F": position.y = -4
                default: position.y = min(-12, position.y - 10)
                }
                return position * ends.attackSign(for: home ? .blue : .red)
            }
        }
        let local = id % 5
        let sign = -ends.attackSign(for: id < 5 ? .blue : .red)
        if local == 4 { return Vector2(x: 0, y: sign * (Pitch.length / 2 - 2.5)) }
        return Vector2(x: local.isMultiple(of: 2) ? -12 : 12, y: sign * (local < 2 ? 25 : 10))
    }

    private mutating func configureMatch(chooseEnds: Bool = true) {
        if chooseEnds { firstHalfBlueAttacksNorth = chooseStartingEnds() }
        ends = MatchEnds(blueAttacksNorth: firstHalfBlueAttacksNorth)
        if let configuration {
            roster = [configuration.home, configuration.away].enumerated().flatMap { side, lineup in
                lineup.players.enumerated().map { slot, profile in
                    let id = side * 11 + slot
                    var state = PlayerState()
                    state.position = startingMatchPosition(for: id)
                    state.facing = ends.direction(for: side == 0 ? .blue : .red)
                    var footballer = Footballer(id: id, team: side == 0 ? .blue : .red, state: state)
                    footballer.isGoalkeeper = slot == 0
                    footballer.clubPlayer = profile
                    return footballer
                }
            }
            selectedPlayerID = 9
            possessionID = nil
            prepareMatchRestart(MatchRestart(kind: .kickoff, team: .blue, position: .zero, takerID: nil))
            return
        }
        roster = (0..<10).map { id in
            var state = PlayerState()
            state.position = startingMatchPosition(for: id)
            state.facing = ends.direction(for: id < 5 ? .blue : .red)
            var footballer = Footballer(id: id, team: id < 5 ? .blue : .red, state: state)
            footballer.isGoalkeeper = id % 5 == 4
            return footballer
        }
        selectedPlayerID = 2
        possessionID = nil
        prepareMatchRestart(MatchRestart(kind: .kickoff, team: .blue, position: .zero, takerID: nil))
    }

    private mutating func prepareMatchRestart(_ restart: MatchRestart) {
        clearRestartSupport()
        resetOffsideForRestart()
        penaltyFlight = nil
        penaltySecondTouchTakerID = nil
        regroupingKeeperID = nil
        shortOutletID = nil
        keeperHandsID = nil
        throughBallLandingPoint = nil
        guard checkPracticeCanContinue() else { return }
        cancelInput()
        freeKickReadyTeam = nil
        activePassTargetID = nil
        receiverControlRemaining = 0
        runningWinProtection = 0
        kickGuards.removeAll()
        recoveryTimers.removeAll()
        tackleHits.removeAll()
        keeperStates.removeAll()
        keeperIntents.removeAll()
        for id in roster.indices {
            roster[id].state.velocity = .zero
            roster[id].fallProgress = 0
            roster[id].recoveryProgress = 0
            roster[id].goalkeeperDiveProgress = 0
            if restart.kind == .kickoff {
                roster[id].state.position = startingMatchPosition(for: id)
                roster[id].state.facing = ends.direction(for: roster[id].team)
            }
        }
        if restart.kind == .penalty {
            placePenalty(for: restart.team)
            return
        }
        ball = BallState()
        ball.position = restart.position
        let keeper = roster.first { $0.team == restart.team && $0.isGoalkeeper && !$0.isUnavailable }?.id
        let taker = restart.kind == .goalKick ? (keeper ?? nearestFootballer(team: restart.team, to: ball.position))
            : nearestFootballer(team: restart.team, to: ball.position)
        let attack = ends.direction(for: restart.team)
        let kickoffPartner = restart.kind == .kickoff ? roster.filter {
            $0.team == restart.team && $0.id != taker && !$0.isGoalkeeper && !$0.isUnavailable
        }.min {
            let a = ($0.state.position - ball.position).lengthSquared
            let b = ($1.state.position - ball.position).lengthSquared
            return abs(a - b) < 0.000001 ? $0.id < $1.id : a < b
        }?.id : nil
        let lateral = Vector2(x: attack.y, y: 0)
        let facing = restart.kind == .kickoff && kickoffPartner != nil ? lateral
            : restart.kind == .throwIn || restart.kind == .corner
                ? (Vector2(x: 0, y: ball.position.y - attack.y * 6) - ball.position).normalized : attack
        for id in roster.indices where !roster[id].isUnavailable {
            if id == taker {
                roster[id].state.position = ball.position - facing * 1.2
                roster[id].state.facing = facing
            } else if id == kickoffPartner {
                roster[id].state.position = ball.position + lateral * 4.5
                roster[id].state.facing = -lateral
            } else {
                let clearance = restart.kind == .kickoff ? 9.7
                    : roster[id].team == restart.team ? 3.0
                    : restart.kind == .throwIn ? RestartSupport.throwInDistance : tuning.freeKickStandBack
                let offset = roster[id].state.position - ball.position
                if offset.length < clearance {
                    let away = offset.length > 0.01 ? offset.normalized
                        : Vector2(x: id.isMultiple(of: 2) ? 1 : -1, y: -attack.y)
                    roster[id].state.position = ball.position + away * clearance
                    clampFootballer(id)
                    if (roster[id].state.position - ball.position).length < clearance - 0.001 {
                        let inward = ball.position.length > 0.1 ? -ball.position.normalized
                            : Vector2(x: id.isMultiple(of: 2) ? 1 : -1, y: 0)
                        roster[id].state.position = ball.position + inward * clearance
                    }
                }
            }
            clampFootballer(id)
        }
        possessionID = taker
        if restart.team == .blue { selectBlue(taker) }
        else { selectedPlayerID = nearestFootballer(team: .blue, to: ball.position) }
        controlClaim = selectedPlayerID == taker
        ball.mode = .controlled
        lastTouchTeam = restart.team
        matchRestart = MatchRestart(kind: restart.kind, team: restart.team, position: ball.position, takerID: taker)
        dribbleCountdown = 0
        freeKickReadyTeam = restart.team
        freeKickKickCountdown = 0.65
        phase = .playing
        refreshRestartSupport()
        enforceRestartClearance()
        resetGeneration += 1
    }

    private mutating func placePenalty(for team: Team) {
        ball = BallState(position: PenaltyRules.mark(for: team, ends: ends), mode: .controlled)
        let attack = ends.direction(for: team)
        let taker = nearestFootballer(team: team, to: ball.position)
        let defender = roster.first { $0.team != team && $0.isGoalkeeper && !$0.isUnavailable }?.id
        var occupied = [ball.position - attack * 1.2, PenaltyRules.goalkeeperPosition(defending: team, ends: ends)]
        for id in roster.indices where !roster[id].isUnavailable {
            roster[id].state.velocity = .zero
            if id == taker {
                roster[id].state.position = ball.position - attack * 1.2
                roster[id].state.facing = attack
            } else if id == defender {
                roster[id].state.position = PenaltyRules.goalkeeperPosition(defending: team, ends: ends)
                roster[id].state.facing = -attack
            } else {
                roster[id].state.position = PenaltyRules.waitingPosition(roster[id].state.position,
                    attackingTeam: team, occupied: occupied, ends: ends)
                roster[id].state.facing = (ball.position - roster[id].state.position).normalized
                occupied.append(roster[id].state.position)
            }
        }
        possessionID = taker
        if team == .blue { selectBlue(taker) }
        else { selectedPlayerID = nearestFootballer(team: .blue, to: ball.position) }
        controlClaim = selectedPlayerID == taker
        matchRestart = MatchRestart(kind: .penalty, team: team, position: ball.position, takerID: taker)
        lastTouchTeam = team
        freeKickReadyTeam = team
        freeKickKickCountdown = 0.85
        phase = .playing
        resetGeneration += 1
    }

    private mutating func launchPenalty(by actor: Int, aim: Vector2, heldFor duration: Double, human: Bool) {
        guard matchRestart?.kind == .penalty, possessionID == actor,
              let shot = PenaltyMechanics.shot(origin: ball.position, aim: aim, team: roster[actor].team,
                                              heldFor: duration, tuning: tuning, ends: ends) else { return }
        let keeper = roster.first { $0.team != roster[actor].team && $0.isGoalkeeper && !$0.isUnavailable }?.id
        activePassTargetID = nil
        if human { lastKickKind = shot.isOverhit ? "overhit penalty" : "penalty" }
        kickBall(by: actor, aim: shot.direction, speed: shot.speed, isShot: true, human: human)
        ball.verticalVelocity = shot.verticalVelocity
        penaltySecondTouchTakerID = actor
        penaltyFlight = PenaltyFlight(takerID: actor, goalkeeperID: keeper)
    }

    private mutating func updatePenaltyCompletion() {
        guard penaltyFlight != nil else { return }
        if phase != .playing || keeperHandsID != nil || possessionID != nil
            || (ball.velocity.length < 0.1 && ball.height < 0.01 && abs(ball.verticalVelocity) < 0.1) {
            penaltyFlight = nil
        }
    }

    @discardableResult
    private mutating func penalisePenaltyTouch(by actor: Int) -> Bool {
        guard mode == .match, phase == .playing, freeKickReadyTeam == nil, ballIsStillInPlay() else { return false }
        guard penaltySecondTouchTakerID == actor else { return false }
        let awarded: Team = roster[actor].team == .blue ? .red : .blue
        let spot = ball.position
        penaltyDoubleTouchCount += 1
        penaltySecondTouchTakerID = nil
        penaltyFlight = nil
        cancelInput()
        resetOffsideForRestart()
        possessionID = nil
        controlClaim = false
        keeperHandsID = nil
        activePassTargetID = nil
        throughBallLandingPoint = nil
        freeKickReadyTeam = nil
        matchRestart = MatchRestart(kind: .indirectFreeKick, team: awarded, position: spot, takerID: nil)
        phase = .restart(kind: .indirectFreeKick, team: awarded)
        restartCountdown = max(0.5, tuning.matchRestartDelay)
        ball.velocity = .zero
        ball.verticalVelocity = 0
        ball.mode = .free
        for id in roster.indices { roster[id].state.velocity = .zero }
        return true
    }

    private mutating func launchAutomaticMatchRestart() {
        guard let restart = matchRestart, let taker = possessionID else { return }
        let attack = ends.direction(for: roster[taker].team)
        if restart.kind == .penalty {
            // Deterministic varying corner aim; opposition uses the same physical shot profile.
            let lateral = taker.isMultiple(of: 2) ? 0.22 : -0.22
            launchPenalty(by: taker, aim: Vector2(x: lateral, y: attack.y), heldFor: 0.7, human: false)
            return
        }
        if restart.kind == .goalKick {
            let tap = distributionChoice(from: taker, aim: attack, heldFor: 0.12, hands: false)
            let duration = tap.targetID == nil ? 0.75 : 0.12
            releaseDistribution(by: taker, choice: duration < tuning.holdThreshold ? tap
                : distributionChoice(from: taker, aim: attack, heldFor: duration, hands: false),
                heldFor: duration, human: false)
            return
        }
        var aim = restart.kind == .throwIn || restart.kind == .corner || restart.kind == .kickoff
            ? roster[taker].state.facing : attack
        let shortOption = readyRestartOutletID
        activePassTargetID = shortOption ?? choosePassTarget(from: taker, aim: aim)
        let target = activePassTargetID
        let speed: Double
        if let target { aim = ledPassDirection(to: target, from: taker); speed = assistedPassSpeed(to: target, from: taker) }
        else { speed = tuning.passSpeed }
        var throwFlight = restart.kind == .throwIn ? KickMechanics.throwIn(heldFor: 0.65, tuning: tuning) : nil
        if restart.kind == .throwIn, let target = shortOption {
            // Let a short option receive a descending throw at the feet. The old fixed
            // long throw passed several metres over the outlet we had just waited for.
            let profile = KickMechanics.throwIn(heldFor: 0.12, tuning: tuning)
            let gravity = max(0.01, tuning.ballGravity)
            let time = (profile.verticalVelocity + sqrt(profile.verticalVelocity * profile.verticalVelocity
                + 2 * gravity * (profile.height - 0.2))) / gravity
            let destination = restartOutletTargets[target] ?? roster[target].state.position
            let offset = destination - ball.position
            aim = offset.normalized
            throwFlight = KickMechanics.Flight(speed: offset.length / time / max(0.1, roster[taker].abilities.passPower),
                verticalVelocity: profile.verticalVelocity, height: profile.height)
        }
        kickBall(by: taker, aim: aim, speed: throwFlight?.speed ?? speed, isShot: false, human: false)
        if let flight = throwFlight { ball.height = flight.height; ball.verticalVelocity = flight.verticalVelocity }
        if roster[taker].team == .blue, let target { selectBlue(target); receiverControlRemaining = 4 }
    }

    private mutating func finishMatch() {
        clearRestartSupport()
        penaltyFlight = nil
        penaltySecondTouchTakerID = nil
        resetOffsideForRestart()
        keeperHandsID = nil
        throughBallLandingPoint = nil
        phase = .fullTime
        matchTimeElapsed = matchDuration
        matchRestart = nil
        freeKickReadyTeam = nil
        possessionID = nil
        controlClaim = false
        activePassTargetID = nil
        ball.velocity = .zero
        ball.verticalVelocity = 0
        for id in roster.indices { roster[id].state.velocity = .zero }
        cancelInput()
    }

    private mutating func recordBallTouch(by actor: Int, deliberate: Bool = false, controlled: Bool = false,
                                          save: Bool = false) {
        earlyPassAdjustment = nil
        crossFlight = nil
        let team = roster[actor].team
        if let taker = penaltySecondTouchTakerID, actor != taker { penaltySecondTouchTakerID = nil }
        if let flight = penaltyFlight, actor != flight.takerID, actor != flight.goalkeeperID {
            penaltyFlight = nil
        }
        if mode == .match {
            if let taker = indirectKickTakerID, taker != actor { indirectKickTakerID = nil }
            // A ricochet or save by the opposition does not make an offside attacker legal.
            // Controlled possession and deliberate distribution begin a new attacking phase.
            if !save, deliberate || controlled || pendingOffside == nil || pendingOffside?.team == team {
                pendingOffside = OffsideRules.snapshot(actor: actor, ball: ball.position, roster: roster,
                    positions: offsideTouchPositions, restart: matchRestart?.kind, ends: ends)
            }
        }
        lastTouchTeam = team
        if deliberate {
            lastDeliberatePlayTeam = team
            handlingRestrictedTeam = team
        } else if handlingRestrictedTeam != team { handlingRestrictedTeam = nil }
    }

    private mutating func resetOffsideForRestart() {
        crossFlight = nil
        queuedHeader = nil
        headingTimers.removeAll(keepingCapacity: true)
        for id in roster.indices { roster[id].headingProgress = 0 }
        pendingOffside = nil
        indirectKickTakerID = nil
        offsideTouchPositions = nil
        attackingTargets.removeAll(keepingCapacity: true)
    }

    /// Being beyond the line is harmless until the player touches or challenges for this ball.
    @discardableResult
    private mutating func penaliseOffsideInvolvement(by actor: Int) -> Bool {
        if penalisePenaltyTouch(by: actor) { return true }
        guard mode == .match, phase == .playing, freeKickReadyTeam == nil,
              let snapshot = pendingOffside, snapshot.candidates.contains(actor),
              roster[actor].team == snapshot.team, !roster[actor].isUnavailable,
              ballIsStillInPlay() else { return false }
        let spot = offsideTouchPositions?.indices.contains(actor) == true
            ? offsideTouchPositions![actor] : roster[actor].state.position
        let awarded: Team = snapshot.team == .blue ? .red : .blue
        offsideCount += 1
        cancelInput()
        resetOffsideForRestart()
        possessionID = nil
        controlClaim = false
        keeperHandsID = nil
        activePassTargetID = nil
        throughBallLandingPoint = nil
        freeKickReadyTeam = nil
        matchRestart = MatchRestart(kind: .offside, team: awarded, position: spot, takerID: nil)
        phase = .restart(kind: .offside, team: awarded)
        restartCountdown = max(0.5, tuning.matchRestartDelay)
        ball.velocity = .zero
        ball.verticalVelocity = 0
        ball.mode = .free
        for id in roster.indices {
            roster[id].state.velocity = .zero
            roster[id].isTackling = false
            roster[id].isSliding = false
        }
        tackleTimers.removeAll()
        tackleDirections.removeAll()
        tackleKinds.removeAll()
        return true
    }

    private func controlReleaseDistance(for id: Int) -> Double {
        (roster[id].isGoalkeeper ? tuning.keeperFootReleaseDistance : tuning.controlReleaseDistance)
            * roster[id].abilities.control
    }
    private func controlSpeedLimit(for id: Int) -> Double {
        (roster[id].isGoalkeeper ? tuning.keeperFootControlSpeed : tuning.controlRelativeSpeed)
            * roster[id].abilities.control
    }
    private func canHandleBall(_ keeper: Int) -> Bool {
        mode == .match && roster[keeper].isGoalkeeper && handlingRestrictedTeam != roster[keeper].team
            && GoalkeeperAI.isInOwnBox(ball.position, team: roster[keeper].team, configuration: keeperConfiguration)
            && GoalkeeperAI.isInOwnBox(roster[keeper].state.position, team: roster[keeper].team, configuration: keeperConfiguration)
    }

    private var keeperConfiguration: GoalkeeperAI.Configuration {
        var configuration = GoalkeeperAI.Configuration.defaults
        configuration.gravity = tuning.ballGravity
        configuration.ends = ends
        return configuration
    }

    private func keeperConfiguration(for id: Int) -> GoalkeeperAI.Configuration {
        var configuration = keeperConfiguration
        let abilities = roster[id].abilities
        configuration.movementSpeed *= abilities.speed * (roster[id].team == .red ? tuning.difficulty.speedMultiplier : 1)
        configuration.acceleration *= abilities.acceleration
        configuration.catchSpeedLimit *= abilities.goalkeeping
        configuration.diveCatchSpeedLimit *= abilities.goalkeeping
        configuration.diveLookAhead *= abilities.goalkeeping * (roster[id].team == .red ? tuning.difficulty.speedMultiplier : 1)
        configuration.standingReach *= 1 + (abilities.goalkeeping - 1) * 0.5
        configuration.diveReach *= 1 + (abilities.goalkeeping - 1) * 0.5
        configuration.recoveryDuration /= abilities.goalkeeping
        return configuration
    }

    private mutating func moveGoalkeeper(_ id: Int, dt: Double) {
        var state = keeperStates[id] ?? GoalkeeperAI.State()
        let hands = keeperHandsID == id
        let intent = GoalkeeperAI.step(state: &state, keeper: roster[id].state, team: roster[id].team,
                                       ball: ball, ownsBall: hands, dt: dt,
                                       handlingAllowed: handlingRestrictedTeam != roster[id].team,
                                       configuration: keeperConfiguration(for: id))
        keeperStates[id] = state
        keeperIntents[id] = intent
        roster[id].goalkeeperDiveProgress = intent.diveProgress
        if id == selectedPlayerID, isControllingGoalkeeper {
            // A manual catch/feet reception never inherits an automatic retreat to the goal mouth.
            // Recovery still finishes visibly before the keeper can run with a diving catch.
            let recovering = intent.diveProgress > 0.01
            moveExerciseFootballer(id, stick: recovering || (curveRemaining > 0 && lastKickerID == selectedPlayerID) ? .zero : receivingMovementIntent(),
                                   speedScale: tuning.keeperFootSpeedScale, dt: dt)
            if recovering { roster[id].state.facing = intent.facing }
            if hands {
                let box = keeperConfiguration
                let sign = -ends.attackSign(for: roster[id].team)
                roster[id].state.position.x = min(box.boxHalfWidth - 0.8,
                    max(-box.boxHalfWidth + 0.8, roster[id].state.position.x))
                let depth = (Pitch.length / 2 - roster[id].state.position.y * sign)
                roster[id].state.position.y = (Pitch.length / 2 - min(box.boxDepth - 0.8, max(1.3, depth))) * sign
            }
        } else if possessionID == id, !hands {
            // The autonomous keeper's feet are an ordinary vulnerable dribble, with a short decision delay.
            let direction = ends.direction(for: roster[id].team)
            moveExerciseFootballer(id, stick: direction * 0.4, speedScale: tuning.keeperFootSpeedScale, dt: dt)
        } else {
            roster[id].state.velocity = intent.velocity
            roster[id].state.position += intent.velocity * dt
            roster[id].state.facing = intent.facing
            clampFootballer(id)
        }
    }

    private mutating func distributeFromGoalkeeper(_ keeper: Int) {
        let attack = ends.direction(for: roster[keeper].team)
        let tap = distributionChoice(from: keeper, aim: attack, heldFor: 0.12, hands: true)
        let duration = tap.targetID == nil ? 0.75 : 0.12
        releaseDistribution(by: keeper, choice: duration < tuning.holdThreshold ? tap
            : distributionChoice(from: keeper, aim: attack, heldFor: duration, hands: true),
            heldFor: duration, human: false)
    }

    private var validRegroupingKeeper: Int? {
        guard mode == .match, phase == .playing, let keeper = keeperHandsID,
              possessionID == keeper, roster.indices.contains(keeper),
              !roster[keeper].isUnavailable, roster[keeper].isGoalkeeper else { return nil }
        return keeper
    }

    private func shortOutletPosition(for id: Int, keeper: Int) -> Vector2 {
        let carrier = roster[keeper]
        let attack = ends.attackSign(for: carrier.team)
        let offset = roster[id].state.position.x - carrier.state.position.x
        let side = abs(offset) > 0.5 ? (offset > 0 ? 1.0 : -1.0) : (id.isMultiple(of: 2) ? -1.0 : 1.0)
        return Vector2(x: min(27, max(-27, carrier.state.position.x + side * 6.5)),
                       y: min(46, max(-46, carrier.state.position.y + attack * 5.5)))
    }

    private mutating func updateKeeperShortOutlet() {
        guard let keeper = validRegroupingKeeper else {
            regroupingKeeperID = nil
            shortOutletID = nil
            return
        }
        let team = roster[keeper].team
        func available(_ id: Int) -> Bool {
            roster.indices.contains(id) && roster[id].team == team && !roster[id].isUnavailable
                && !roster[id].isGoalkeeper && !roster[id].isTackling && roster[id].fallProgress <= 0.001
                && (recoveryTimers[id] ?? 0) <= 0
        }
        if regroupingKeeperID == keeper, regroupingSaveCount == goalkeeperSaveCount,
           let id = shortOutletID, available(id) { return }
        regroupingKeeperID = keeper
        regroupingSaveCount = goalkeeperSaveCount
        shortOutletID = roster.filter { available($0.id) }.min { first, second in
            func score(_ candidate: Footballer) -> Double {
                let target = shortOutletPosition(for: candidate.id, keeper: keeper)
                let opponentGap = roster.filter { $0.team != team && !$0.isUnavailable }
                    .map { ($0.state.position - target).length }.min() ?? 20
                return (candidate.state.position - target).length + max(0, 6 - opponentGap) * 2
            }
            let a = score(first), b = score(second)
            return abs(a - b) < 0.000001 ? first.id < second.id : a < b
        }?.id
    }

    /// Temporary targets for a genuine catch. Open-play support, chasing and receiving resume
    /// immediately when hands possession ends; no player is moved directly to these positions.
    func keeperRegroupTarget(for id: Int) -> Vector2? {
        guard let keeper = validRegroupingKeeper, roster.indices.contains(id),
              !roster[id].isGoalkeeper, !roster[id].isUnavailable else { return nil }
        let holdingTeam = roster[keeper].team
        if id == keeperShortOutletID { return shortOutletPosition(for: id, keeper: keeper) }
        let friendly = roster[id].team == holdingTeam
        let attack = ends.attackSign(for: holdingTeam)
        var target = matchFormationTarget(for: id, inPossession: friendly)
        let members = roster.filter { $0.team == roster[id].team && !$0.isGoalkeeper }.map(\.id)
        let slot = members.firstIndex(of: id) ?? 0
        let role = configuration.map {
            (roster[id].team == .blue ? $0.home : $0.away).formation.slots[id % 11].role
        } ?? (slot < 2 ? "D" : "F")
        let shapeDepth = friendly ? 4.5 : role == "F" ? 4.5 : role == "D" ? 12.0 : 8.0
        let minimumDepth = keeperConfiguration.boxDepth + shapeDepth
        let depth = Pitch.length / 2 + target.y * attack
        if depth < minimumDepth { target.y = (-Pitch.length / 2 + minimumDepth) * attack }
        if friendly, abs(target.x - roster[keeper].state.position.x) < 12 {
            let keeperX = roster[keeper].state.position.x
            var side = target.x < keeperX ? -1.0 : 1.0
            if abs(keeperX + side * 15) > 28 { side = -side }
            target.x = keeperX + side * 15
        }
        target.x = min(28, max(-28, target.x))
        target.y = min(46, max(-46, target.y))
        return target
    }

    private func mustWithdrawFromKeeper(_ id: Int, keeper: Int, position: Vector2? = nil) -> Bool {
        guard roster[id].team != roster[keeper].team else { return false }
        let point = position ?? roster[id].state.position
        let attack = ends.attackSign(for: roster[keeper].team)
        let depth = Pitch.length / 2 + point.y * attack
        return (abs(point.x) < keeperConfiguration.boxHalfWidth + 1.5
                && depth < keeperConfiguration.boxDepth + 1.5)
            || (point - roster[keeper].state.position).length < 8
    }

    private func keeperProtectedMovement(for id: Int, requested: Vector2) -> Vector2 {
        guard let keeper = validRegroupingKeeper, roster[id].team != roster[keeper].team,
              let target = keeperRegroupTarget(for: id) else { return requested }
        let lookAhead = roster[id].state.position + requested * tuning.playerMaxSpeed * 0.12
        guard mustWithdrawFromKeeper(id, keeper: keeper) || mustWithdrawFromKeeper(id, keeper: keeper, position: lookAhead)
        else { return requested }
        let escape = (target - roster[id].state.position).normalized
        // Inside the protected area, keep sideways/away control while preventing a human from
        // replacing the AI's withdrawn chaser with a new keeper press. Motion remains integrated.
        let inward = min(0, requested.dot(escape))
        let permitted = requested - escape * inward
        return (permitted + escape * 0.8).clampedLength(1)
    }

    private func keeperShapeReadyToRelease(_ keeper: Int) -> Bool {
        let elapsed = keeperStates[keeper]?.holdingElapsed ?? 0
        // A training fixture with stationary AI must still progress; live AI gets time to form
        // a safe outlet, but an unreachable/blocked outlet cannot stall the opposition forever.
        if tuning.aiSpeedScale <= 0 || elapsed >= 3 { return true }
        guard let outlet = keeperShortOutletID else { return true }
        let point = roster[outlet].state.position
        let carrier = roster[keeper].state.position
        let offset = point - carrier
        guard offset.length >= 4, offset.length <= keeperThrowRange(heldFor: 0.15),
              (point - shortOutletPosition(for: outlet, keeper: keeper)).length < 3 else { return false }
        for opponent in roster where opponent.team != roster[keeper].team && !opponent.isUnavailable {
            if mustWithdrawFromKeeper(opponent.id, keeper: keeper) { return false }
            let projection = min(1, max(0, (opponent.state.position - carrier).dot(offset) / max(0.01, offset.lengthSquared)))
            if (opponent.state.position - (carrier + offset * projection)).length < 3 { return false }
        }
        return true
    }

    private func matchFormationTarget(for id: Int, inPossession: Bool) -> Vector2 {
        let team = roster[id].team
        let attack = ends.attackSign(for: team)
        if let configuration {
            let lineup = team == .blue ? configuration.home : configuration.away
            let slot = lineup.formation.slots[id % 11]
            let ballProgress = ball.position.y * attack
            let anchor: Double
            let minimum: Double
            let maximum: Double
            switch slot.role {
            case "D":
                anchor = ballProgress - (inPossession ? 23 : 17)
                minimum = -39; maximum = inPossession ? 4 : -8
            case "F":
                anchor = ballProgress + (inPossession ? 15 : 3)
                minimum = inPossession ? -3 : -16; maximum = 43
            default:
                // Preserve differences between holding, central and advanced midfield slots.
                let depth = min(7, max(-7, slot.position.y * 0.5))
                anchor = ballProgress + (inPossession ? 1 : -8) + depth
                minimum = -32; maximum = 32
            }
            let width = inPossession ? 1.0 : 0.87
            let x = slot.position.x * attack * width + ball.position.x * 0.16
            return Vector2(x: min(28, max(-28, x)), y: min(maximum, max(minimum, anchor)) * attack)
        }
        let members = roster.filter { $0.team == team && !$0.isGoalkeeper }.map(\.id)
        let slot = members.firstIndex(of: id) ?? 0
        let defender = slot < 2
        let ballProgress = ball.position.y * attack
        let ownProgress: Double
        if defender { ownProgress = min(inPossession ? 8 : -2, max(-34, ballProgress - (inPossession ? 14 : 10))) }
        else { ownProgress = min(37, max(inPossession ? -8 : -23, ballProgress + (inPossession ? 9 : -6))) }
        let width = defender ? 14.0 : 12.0
        return Vector2(x: (slot.isMultiple(of: 2) ? -width : width) + ball.position.x * 0.14,
                       y: ownProgress * attack)
    }

    // MARK: - Passing and defending exercise

    private mutating func configureExercise() {
        let positions = [Vector2(x: 0, y: -10), Vector2(x: -11, y: 2), Vector2(x: 11, y: 5),
                         Vector2(x: -7, y: 18), Vector2(x: 8, y: 25), Vector2(x: 0, y: 36)]
        roster = positions.enumerated().map { index, position in
            var state = PlayerState()
            state.position = position
            state.facing = index < 3 ? .up : -.up
            return Footballer(id: index, team: index < 3 ? .blue : .red, state: state)
        }
        selectedPlayerID = 0
        ball.position = player.position + .up * 1.25
        ball.velocity = .zero
        ball.mode = .controlled
        possessionID = 0
        controlClaim = true
    }

    private mutating func stepExercise(dt: Double) {
        dribbleCountdown = max(0, dribbleCountdown - dt)
        switchCountdown = max(0, switchCountdown - dt)
        aiDecisionCountdown = max(0, aiDecisionCountdown - dt / tuning.difficulty.decisionInterval)
        advanceRecoveryTimers(dt: dt)
        refreshExerciseControl()
        guard phase == .playing else { return }
        selectRelevantBluePlayer(dt: dt)
        advanceActionClock(dt: dt)
        if let team = freeKickReadyTeam {
            advanceRestartSupport(dt: dt)
            if team == .red {
                freeKickKickCountdown -= dt
                let hasShortOption = readyRestartOutletID != nil
                let supportReady = restartSupportContext == nil || tuning.aiSpeedScale <= 0 || restartShortOutletIDs.isEmpty
                    || hasShortOption || restartSupportElapsed >= 3
                if freeKickKickCountdown <= 0 && supportReady {
                    if mode == .match { launchAutomaticMatchRestart() }
                    else { launchRedFreeKick() }
                }
            } else if let kicker = possessionID, validMovement.length > 0.0001 {
                // A set-piece stick aims in place: retain this facing when the
                // thumb lifts so a later neutral-stick release uses that aim.
                roster[kicker].state.facing = validMovement.normalized
                roster[kicker].state.velocity = .zero
            }
            return
        }

        applyEarlyPassAdjustment(dt: dt)
        updateKeeperShortOutlet()
        previousFootballerPositions = roster.map(\.state.position)
        prepareAITackles()
        guard phase == .playing else { return }
        updateAttackingSupport()
        let receiverIntent = receivingMovementIntent()
        let intents = roster.map { footballer -> Vector2 in
            if footballer.id == selectedPlayerID {
                return keeperProtectedMovement(for: footballer.id, requested: curveRemaining > 0 && lastKickerID == selectedPlayerID ? .zero : receiverIntent)
            }
            let offset = aiTarget(for: footballer.id) - footballer.state.position
            return offset / max(1.5, offset.length)
        }
        for id in roster.indices {
            if mode == .match, roster[id].isGoalkeeper, !roster[id].isUnavailable {
                moveGoalkeeper(id, dt: dt)
                continue
            }
            guard !roster[id].isUnavailable, !roster[id].isGoalkeeper else {
                roster[id].state.velocity = .zero
                continue
            }
            if (tackleTimers[id] ?? 0) > 0 {
                moveCommittedTackle(id, dt: dt)
            } else {
                let recoveryScale = (recoveryTimers[id] ?? 0) > 0 ? 0.4 : 1.0
                let offBallBoost = possessionID == id ? 1.0 : max(1, tuning.offBallSpeedBoost)
                let speedScale = (id == selectedPlayerID ? 1 : aiMovementScale(for: id)) * recoveryScale * offBallBoost
                moveExerciseFootballer(id, stick: intents[id], speedScale: speedScale, dt: dt)
            }
        }
        separateFootballers()

        refreshExerciseControl(allowAcquisition: false)
        if let owner = keeperHandsID, possessionID == owner {
            ball.position = roster[owner].state.position + (ends.direction(for: roster[owner].team)) * 0.6
            ball.velocity = .zero
            ball.height = 1.0
            ball.verticalVelocity = 0
            if roster[owner].team == .red, keeperIntents[owner]?.shouldDistribute == true,
               keeperShapeReadyToRelease(owner) { distributeFromGoalkeeper(owner) }
            else { finishActionTimers(dt: dt); return }
        }
        nudgeExerciseBall()
        guard phase == .playing else { return }
        performAIBallAction()
        guard phase == .playing else { return }
        applyChipInput(dt: dt)
        applyAftertouch(dt: dt)
        advanceBall(dt: dt)
        finishActionTimers(dt: dt)
        if phase == .playing {
            refreshExerciseControl()
            selectRelevantBluePlayer()
        }
    }

    private mutating func moveExerciseFootballer(_ id: Int, stick: Vector2, speedScale: Double, dt: Double) {
        var state = roster[id].state
        let abilities = roster[id].abilities
        let requested = stick * max(0, tuning.playerMaxSpeed * speedScale * abilities.speed)
        let acceleration = stick.length > 0.0001 ? tuning.playerAcceleration * abilities.acceleration : tuning.playerDeceleration
        state.velocity += (requested - state.velocity).clampedLength(max(0, acceleration) * dt)
        if stick.length > 0.0001 {
            let desired = atan2(stick.y, stick.x)
            let current = atan2(state.facing.y, state.facing.x)
            let difference = atan2(sin(desired - current), cos(desired - current))
            let turn = min(abs(difference), max(0, tuning.playerTurnRate) * dt)
            state.facing = state.facing.rotated(by: difference < 0 ? -turn : turn).normalized
        }
        state.position += state.velocity * dt
        roster[id].state = state
        clampFootballer(id)
    }

    private mutating func clampFootballer(_ id: Int) {
        let xLimit = Pitch.width / 2 - Pitch.playerRadius
        let yLimit = penaltyFlight?.goalkeeperID == id ? Pitch.length / 2 : Pitch.length / 2 - Pitch.playerRadius
        if abs(roster[id].state.position.x) > xLimit {
            roster[id].state.position.x = min(xLimit, max(-xLimit, roster[id].state.position.x))
            roster[id].state.velocity.x = 0
        }
        if abs(roster[id].state.position.y) > yLimit {
            roster[id].state.position.y = min(yLimit, max(-yLimit, roster[id].state.position.y))
            roster[id].state.velocity.y = 0
        }
    }

    private mutating func separateFootballers() {
        for first in roster.indices where !roster[first].isUnavailable {
            for second in roster.indices where second > first && !roster[second].isUnavailable {
                let offset = roster[second].state.position - roster[first].state.position
                let distance = offset.length
                let overlap = Pitch.playerRadius * 2 - distance
                guard overlap > 0 else { continue }
                let normal = distance > 0.00001 ? offset / distance : Vector2(x: 1, y: 0)
                let firstWeight = keeperHandsID == first ? 0.0 : keeperHandsID == second ? 1.0 : 0.5
                roster[first].state.position -= normal * (overlap * firstWeight)
                roster[second].state.position += normal * (overlap * (1 - firstWeight))
                clampFootballer(first)
                clampFootballer(second)
            }
        }
    }

    private mutating func refreshExerciseControl(allowAcquisition: Bool = true) {
        let wasIncoming = ball.mode == .pass || (ball.mode == .free && ball.velocity.length > 2)
        let oldOwner = possessionID
        if let id = keeperHandsID, possessionID == id, !roster[id].isUnavailable {
            controlClaim = selectedPlayerID == id
            ball.mode = .controlled
            return
        }
        if let id = possessionID {
            let state = roster[id].state
            if roster[id].isUnavailable || roster[id].isTackling || ball.height > tuning.airborneContactHeight
                || (kickGuards[id] ?? 0) > 0 || (ball.position - state.position).length > controlReleaseDistance(for: id)
                || (ball.velocity - state.velocity).length > controlSpeedLimit(for: id) * 1.25 {
                possessionID = nil
            }
        }

        let candidates = roster.filter { candidate in
            guard allowAcquisition, !candidate.isUnavailable, !candidate.isTackling,
                  !candidate.isGoalkeeper || (mode == .match && !canHandleBall(candidate.id)),
                  queuedPass?.actorID != candidate.id, ball.height <= tuning.airborneContactHeight,
                  (kickGuards[candidate.id] ?? 0) <= 0 else { return false }
            // Existing possession is contested exclusively on advanceBall's swept timeline.
            guard possessionID == nil else { return false }
            return canAcquireLooseBall(with: candidate.state, playerID: candidate.id)
        }.sorted {
            let left = ($0.state.position - ball.position).lengthSquared
            let right = ($1.state.position - ball.position).lengthSquared
            return abs(left - right) < 0.000001 ? $0.id < $1.id : left < right
        }
        if let candidate = candidates.first {
            if penaliseOffsideInvolvement(by: candidate.id) { return }
            if wasIncoming { receiveBall(by: candidate.id); return }
            possessionID = candidate.id
        }
        if possessionID != oldOwner || possessionID == nil { rearPressure.removeAll() }
        controlClaim = possessionID == selectedPlayerID
        if let owner = possessionID {
            ball.mode = .controlled
            if owner != oldOwner {
                recordBallTouch(by: owner, controlled: true)
                if wasIncoming { recentReceiverID = owner; recentReceptionRemaining = 0.45 }
                dribbleCountdown = 0
                activePassTargetID = nil
                aiDecisionCountdown = 0.85
                endAftertouch()
                chipRemaining = 0
                if queuedPass?.actorID != owner { queuedPass = nil }
            }
        } else if ball.mode == .controlled { ball.mode = .free }
        if actionDown, !actionWasTackle, !actionReceiving, !actionHeading, !controlClaim { actionCancelled = true }
    }

    private mutating func nudgeExerciseBall() {
        guard let owner = possessionID, !roster[owner].isTackling, keeperHandsID != owner, queuedPass == nil,
              ball.height <= tuning.airborneContactHeight, dribbleCountdown <= 0 else { return }
        let state = roster[owner].state
        let offset = ball.position - state.position
        let settling = recentReceiverID == owner && recentReceptionRemaining > 0
        let settlingReach = settling ? max(tuning.dribbleReach, tuning.kickReach) : tuning.dribbleReach
        guard offset.length <= (roster[owner].isGoalkeeper ? tuning.keeperFootAcquireDistance : settlingReach) else { return }
        guard !penaliseOffsideInvolvement(by: owner) else { return }
        let speed = state.velocity.length
        recordBallTouch(by: owner, controlled: true)
        let attackingDirection = ends.direction(for: roster[owner].team)
        let preparingAITurn = owner != selectedPlayerID
            && (offset.dot(attackingDirection) < 0.2 || state.velocity.dot(attackingDirection) < -0.2)
        if speed < 0.35 || preparingAITurn {
            // AI cushions a reachable ball before getting behind it; otherwise a chasing defender
            // would repeatedly nudge north while trying to reverse into a southward attack.
            if recentReceiverID == owner, recentReceptionRemaining > 0, offset.length > 1.25,
               !roster[owner].isGoalkeeper {
                ball.velocity = -offset.normalized * min(7, (offset.length - 1.25) * 9)
            } else {
                ball.velocity *= 0.25
            }
        } else {
            let direction = state.velocity.normalized
            let forwardGap = offset.dot(direction)
            let preferredGap = 1.0 + 0.22 * min(1, speed / max(0.1, tuning.playerMaxSpeed))
            // A legal first touch from behind must carry into the runner's next stride.
            // Move the physical ball with a bounded foot touch; never teleport it to the player.
            let catchUp = settling ? 6.0 * roster[owner].abilities.control : 4.5
            let touchSpeed = max(0, speed + min(catchUp, (preferredGap - forwardGap) * 7))
            let correction = roster[owner].isGoalkeeper ? 5.0 : 10.0
            ball.velocity = (direction * touchSpeed - (offset - direction * forwardGap) * correction).clampedLength(speed + catchUp)
        }
        dribbleCountdown = max(0.01, tuning.dribbleTouchInterval)
    }

    private func choosePassTarget(from passer: Int, aim: Vector2, maximumDistance: Double? = nil) -> Int? {
        guard aim.length > 0.0001 else { return nil }
        let offsidePlayers = mode == .match ? OffsideRules.snapshot(actor: passer, ball: ball.position,
            roster: roster, restart: matchRestart?.kind, ends: ends)?.candidates ?? [] : []
        let direction = aim.normalized
        let minimumAlignment = cos(min(85, max(1, tuning.passAssistAngle)) * .pi / 180)
        let origin = roster[passer].state.position
        let team = roster[passer].team
        let range = min(tuning.passAssistRange, maximumDistance ?? tuning.passAssistRange)
        var bestID: Int?
        var bestScore = -Double.infinity
        for candidate in roster where candidate.team == team && candidate.id != passer
            && !candidate.isUnavailable && (!candidate.isGoalkeeper || mode == .match) && !candidate.isTackling
            && candidate.fallProgress <= 0.001 && (recoveryTimers[candidate.id] ?? 0) <= 0 {
            guard !offsidePlayers.contains(candidate.id) else { continue }
            let offset = candidate.state.position - origin
            let distance = offset.length
            guard distance >= 1.8, distance <= range else { continue }
            let alignment = offset.normalized.dot(direction)
            guard alignment >= minimumAlignment else { continue }
            let plan = assistedPassPlan(to: candidate.id, from: passer)
            guard plan.isReachable else { continue }
            let risk = passLaneRisk(to: plan.destination, arrivalTime: plan.flightTime, team: team)
            // Direction expresses the recipient. Lane quality only separates reasonably
            // similar options; an open wide player must not override a clearly straighter aim.
            let score = alignment * 6.0 - distance / max(1, tuning.passAssistRange) * 1.1
                - risk.lane * 0.30 - risk.receiver * 0.15
            if score > bestScore + 0.000001 || (abs(score - bestScore) <= 0.000001 && candidate.id < (bestID ?? .max)) {
                bestScore = score
                bestID = candidate.id
            }
        }
        return bestID
    }

    private func assistedPassSpeed(to target: Int, from passer: Int? = nil) -> Double {
        assistedPassPlan(to: target, from: passer).launchSpeed
    }

    private func ledPassDirection(to target: Int, from passer: Int? = nil) -> Vector2 {
        (assistedPassPlan(to: target, from: passer).destination - ball.position).normalized
    }

    private struct AssistedPassPlan {
        let destination: Vector2
        /// Requested speed before the actual kicker's rating and foot-power modifiers.
        let launchSpeed: Double
        let flightTime: Double
        let isReachable: Bool
    }

    private func assistedPassPlan(to target: Int, from passer: Int? = nil) -> AssistedPassPlan {
        let actor = passer ?? possessionID ?? selectedPlayerID
        let receiver = roster[target]
        // A preview of the receiver's next kick originates at his prospective feet, not at
        // an incoming ball that may still be far away. Actual kicks always use the real ball.
        let actorState = roster[actor].state
        let origin = (ball.position - actorState.position).length > tuning.kickReach
            ? actorState.position + actorState.facing * 1.2 : ball.position
        // A hand throw uses its independent ballistic power profile. Keep its modest lead
        // distinct from a rolling pass's future contact/pace solution.
        if keeperHandsID == actor {
            let distance = (receiver.state.position - ball.position).length
            let time = min(1.3, distance / max(12, tuning.passSpeed))
            let lead = (receiver.state.velocity * time * max(0, tuning.passLead)).clampedLength(4)
            var destination = receiver.state.position + lead
            destination.x = min(Pitch.width / 2 - 1, max(-Pitch.width / 2 + 1, destination.x))
            destination.y = min(Pitch.length / 2 - 1, max(-Pitch.length / 2 + 1, destination.y))
            return AssistedPassPlan(destination: destination, launchSpeed: tuning.passSpeed, flightTime: time, isReachable: true)
        }
        let kicker = roster[actor]
        let humanHandoff = actor == selectedPlayerID && kicker.team == .blue && receiver.team == .blue
        let receiverSpeed = tuning.playerMaxSpeed * receiver.abilities.speed
            * (receiver.isGoalkeeper ? tuning.keeperFootSpeedScale : tuning.offBallSpeedBoost)
        let requestedVelocity: Vector2? = humanHandoff ? validMovement * max(0, receiverSpeed) : nil
        let footScale = kicker.isGoalkeeper ? max(0.1, tuning.keeperFootKickScale) : 1
        let powerScale = max(0.1, kicker.abilities.passPower * footScale)
        let minimumSpeed = (receiver.isGoalkeeper ? 9 : max(1, tuning.passSpeed)) * powerScale
        let arrivalSpeed = (receiver.isGoalkeeper ? 6 : max(1, tuning.passArrivalSpeed)) * powerScale
        let plan = GroundPassPlanner.plan(origin: origin, receiver: receiver.state,
            requestedVelocity: requestedVelocity,
            acceleration: tuning.playerAcceleration * receiver.abilities.acceleration,
            deceleration: tuning.playerDeceleration, minimumSpeed: minimumSpeed,
            arrivalSpeed: arrivalSpeed, friction: tuning.ballFriction,
            maximumSpeed: 44 * min(1, powerScale))
        return AssistedPassPlan(destination: plan.destination, launchSpeed: plan.launchSpeed / powerScale,
                                flightTime: plan.flightTime, isReachable: plan.isReachable)
    }

    private func passLaneRisk(to destination: Vector2, arrivalTime: Double, team: Team) -> (lane: Double, receiver: Double) {
        let travel = destination - ball.position
        let lengthSquared = travel.lengthSquared
        guard lengthSquared > 0.01 else { return (0, 0) }
        var laneRisk = 0.0
        var receiverRisk = 0.0
        for opponent in roster where opponent.team != team && !opponent.isUnavailable {
            let projection = (opponent.state.position - ball.position).dot(travel) / lengthSquared
            if projection > 0.06, projection < 0.94 {
                let projected = opponent.state.position + opponent.state.velocity * min(0.65, max(0, arrivalTime * projection))
                let along = min(0.94, max(0.06, (projected - ball.position).dot(travel) / lengthSquared))
                let gap = (projected - (ball.position + travel * along)).length
                let reach = Pitch.playerRadius + Pitch.ballRadius + min(1.7, arrivalTime * along * 1.2)
                laneRisk = max(laneRisk, max(0, 1 - gap / max(0.1, reach)))
            }
            let receivingOpponent = opponent.state.position + opponent.state.velocity * min(0.65, max(0, arrivalTime))
            receiverRisk = max(receiverRisk, max(0, 1 - (receivingOpponent - destination).length / 4))
        }
        return (laneRisk, receiverRisk)
    }

    private func isIntendedFriendlyPass(to id: Int) -> Bool {
        guard mode != .solo, ball.mode == .pass, activePassTargetID == id,
              !roster[id].isGoalkeeper, !roster[id].isUnavailable,
              let kicker = lastKickerID, roster[kicker].team == roster[id].team else { return false }
        return possessionID == nil || possessionID == id
    }

    private func acquisitionReach(for id: Int?) -> Double {
        guard let id else { return tuning.controlAcquireDistance }
        let base = roster[id].isGoalkeeper ? tuning.keeperFootAcquireDistance : tuning.controlAcquireDistance
        let ordinary = base * (1 + (roster[id].abilities.control - 1) * 0.35)
        guard isIntendedFriendlyPass(to: id) else { return ordinary }
        return max(ordinary, min(ordinary + 0.45, tuning.controlReleaseDistance - 0.2))
    }

    private func acquisitionSpeedLimit(for id: Int?) -> Double {
        guard let id else { return tuning.controlRelativeSpeed }
        let control = roster[id].abilities.control
        if roster[id].isGoalkeeper { return tuning.keeperFootControlSpeed * control }
        guard ball.mode == .pass else { return tuning.controlRelativeSpeed * control }
        if let kicker = lastKickerID, roster[kicker].team != roster[id].team { return tuning.controlRelativeSpeed * control }
        let receiving = tuning.receivingSpeed * (isIntendedFriendlyPass(to: id) ? 1.15 : 1)
        return max(tuning.controlRelativeSpeed, receiving) * control
    }

    private mutating func receiveBall(by id: Int) {
        guard !penaliseOffsideInvolvement(by: id) else { return }
        queuedHeader = nil
        let intendedPass = isIntendedFriendlyPass(to: id)
        keeperHandsID = nil
        throughBallLandingPoint = nil
        recordBallTouch(by: id, controlled: true)
        rearPressure.removeAll()
        let previousOwner = possessionID
        possessionID = id
        controlClaim = id == selectedPlayerID
        recentReceiverID = id
        recentReceptionRemaining = intendedPass ? 1.15 : 0.45
        let residual = (intendedPass ? 0.025 : 0.08) / roster[id].abilities.control
        ball.velocity = ball.velocity * residual + roster[id].state.velocity * (1 - residual)
        ball.verticalVelocity = min(0, max(-1, ball.verticalVelocity))
        ball.mode = .controlled
        dribbleCountdown = intendedPass ? 0 : 0.06
        activePassTargetID = nil
        aiDecisionCountdown = 0.85
        endAftertouch()
        chipRemaining = 0
        if queuedPass?.actorID != id { queuedPass = nil }
        if actionDown, previousOwner != id, id != selectedPlayerID { actionCancelled = true }
    }

    private mutating func advanceRecoveryTimers(dt: Double) {
        if crossFlight != nil {
            crossFlight!.remaining -= dt
            if !isCrossInFlight || crossFlight!.remaining <= 0 {
                crossFlight = nil
            } else if (validMovement - crossFlight!.launchMovement).length > 0.25 {
                crossFlight!.manualSteering = true
            }
        }
        recentKickAimRemaining = max(0, recentKickAimRemaining - dt)
        rememberDeliberateKickAim()
        runningWinProtection = max(0, runningWinProtection - dt)
        receiverControlRemaining = max(0, receiverControlRemaining - dt)
        if receiverControlRemaining > 0, let target = activePassTargetID, ball.mode == .pass {
            unreachablePassElapsed = receiverCanStillMeetPass(target) ? 0 : unreachablePassElapsed + dt
            if unreachablePassElapsed >= 0.2 {
                activePassTargetID = nil
                receiverControlRemaining = 0
                chipRemaining = 0
                kickInputBaseline = nil
            }
        } else { unreachablePassElapsed = 0 }
        recentReceptionRemaining = max(0, recentReceptionRemaining - dt)
        for id in Array(kickGuards.keys) { kickGuards[id] = max(0, (kickGuards[id] ?? 0) - dt) }
        for id in Array(recoveryTimers.keys) { recoveryTimers[id] = max(0, (recoveryTimers[id] ?? 0) - dt) }
    }

    private mutating func finishActionTimers(dt: Double) {
        guard phase == .playing else { return }
        for id in roster.indices {
            if roster[id].goalkeeperReleaseProgress > 0 {
                roster[id].goalkeeperReleaseProgress += dt / 0.3
                if roster[id].goalkeeperReleaseProgress >= 1 {
                    roster[id].goalkeeperReleaseProgress = 0
                    roster[id].goalkeeperReleaseKind = nil
                }
            }
            let heading = max(0, (headingTimers[id] ?? 0) - dt)
            headingTimers[id] = heading
            roster[id].headingProgress = heading > 0 ? max(0.001, 1 - heading / HeadingMechanics.animationDuration) : 0
            tackleTimers[id] = max(0, (tackleTimers[id] ?? 0) - dt)
            roster[id].isTackling = (tackleTimers[id] ?? 0) > 0
            roster[id].isSliding = roster[id].isTackling && tackleKinds[id] == .slide
        }
        if queuedPass != nil {
            queuedPass!.remaining -= dt
            if queuedPass!.remaining <= 0 || roster[queuedPass!.actorID].isUnavailable { queuedPass = nil }
        }
        if let header = queuedHeader {
            queuedHeader!.remaining -= dt
            if queuedHeader!.remaining <= 0 || !eligibleHeader(header.actorID) || keeperHandsID != nil {
                queuedHeader = nil
            }
        }
    }

    private mutating func moveCommittedTackle(_ id: Int, dt: Double) {
        let direction = tackleDirections[id] ?? roster[id].state.facing
        let speed = tackleKinds[id] == .slide ? max(0, tuning.slideSpeed) : 0
        roster[id].state.velocity = direction * speed
        roster[id].state.position += roster[id].state.velocity * dt
        roster[id].state.facing = direction
        clampFootballer(id)
    }

    private mutating func kickBall(by actor: Int, aim: Vector2, speed: Double, isShot: Bool, human: Bool) {
        clearRestartSupport()
        let indirectRestart = matchRestart?.kind == .offside || matchRestart?.kind == .indirectFreeKick
        queuedHeader = nil
        keeperHandsID = nil
        throughBallLandingPoint = nil
        rearPressure.removeAll()
        runningWinProtection = 0
        receiverControlRemaining = 0
        unreachablePassElapsed = 0
        kickInputBaseline = nil
        recordBallTouch(by: actor, deliberate: true)
        if indirectRestart { indirectKickTakerID = actor }
        matchRestart = nil
        ball.velocity = ratedKickVelocity(by: actor, aim: aim, speed: speed, isShot: isShot)
        ball.verticalVelocity = 0
        ball.height = 0
        ball.mode = isShot ? .shot : .pass
        if human {
            kickCount += 1
            lastKick = ball.mode
        }
        controlClaim = false
        possessionID = nil
        lastKickerID = actor
        recentReceiverID = nil
        recentReceptionRemaining = 0
        kickGuards[actor] = max(0, tuning.reacquisitionDelay)
        releaseReturningReceiverGuard(from: actor, isShot: isShot)
        reacquisitionCountdown = max(0, tuning.reacquisitionDelay)
        dribbleCountdown = 0
        freeKickReadyTeam = nil
        endAftertouch()
        chipRemaining = human ? max(0, tuning.chipWindowDuration) : 0
        let executedAim = roster[actor].clubPlayer == nil ? aim.normalized : ball.velocity.normalized
        originalKickDirection = executedAim
        if human, isShot, tuning.aftertouchDuration > 0, speed > 0.1 {
            kickInputBaseline = validMovement
            originalShotDirection = executedAim
            curveAngle = 0
            curveRemaining = tuning.aftertouchDuration
        }
        if human, !isShot, mode != .solo, let receiver = activePassTargetID,
           roster[receiver].team == .blue, !roster[receiver].isUnavailable, !roster[receiver].isGoalkeeper || mode == .match {
            // An assisted pass deliberately hands joystick control to its intended receiver now,
            // while the independently moving ball is still in flight.
            selectBlue(receiver)
            receiverControlRemaining = 4.0
            kickInputBaseline = validMovement
            if tuning.passEarlyAdjustmentEnabled, lastKickKind == "pass" {
                earlyPassAdjustment = EarlyPassAdjustment.State(receiverID: receiver,
                    originalDirection: ball.velocity.normalized, launchMovement: validMovement)
            }
        }
    }

    /// A fresh return from a teammate is not the recipient collecting their own kick again.
    /// Release that intended recipient only; keep the new kicker and unrelated contact guards.
    private mutating func releaseReturningReceiverGuard(from actor: Int, isShot: Bool) {
        guard !isShot, let receiver = activePassTargetID, receiver != actor,
              roster.indices.contains(receiver), roster[receiver].team == roster[actor].team else { return }
        kickGuards[receiver] = 0
    }

    private mutating func applyEarlyPassAdjustment(dt: Double) {
        guard var pending = earlyPassAdjustment else { return }
        guard tuning.passEarlyAdjustmentEnabled, pending.remaining > 0, phase == .playing,
              possessionID == nil, ball.mode == .pass, isControllingPassReceiver,
              selectedPlayerID == pending.receiverID, activePassTargetID == pending.receiverID,
              !actionDown, queuedPass == nil, queuedHeader == nil,
              !roster[pending.receiverID].isTackling, !roster[pending.receiverID].isUnavailable else {
            earlyPassAdjustment = nil
            return
        }
        let receiver = roster[pending.receiverID]
        let opponents = roster.filter { $0.team != receiver.team && !$0.isUnavailable }.map { opponent in
            EarlyPassAdjustment.Opponent(position: opponent.state.position,
                maximumSpeed: max(opponent.state.velocity.length,
                    tuning.playerMaxSpeed * tuning.offBallSpeedBoost * opponent.abilities.speed),
                reach: max(tuning.controlAcquireDistance, tuning.passiveControlReach) * opponent.abilities.control)
        }
        let decision = EarlyPassAdjustment.evaluate(ball: ball, receiver: receiver.state,
            movement: validMovement, launchMovement: pending.launchMovement,
            originalDirection: pending.originalDirection,
            receiverSpeed: tuning.playerMaxSpeed * receiver.abilities.speed
                * (receiver.isGoalkeeper ? tuning.keeperFootSpeedScale : tuning.offBallSpeedBoost),
            acceleration: tuning.playerAcceleration * receiver.abilities.acceleration,
            deceleration: tuning.playerDeceleration, friction: tuning.ballFriction, opponents: opponents)
        switch decision {
        case .wait:
            pending.remaining -= dt
            earlyPassAdjustment = pending.remaining > 0 ? pending : nil
        case .veto:
            earlyPassAdjustment = nil
        case .correction(let velocity, let angle):
            earlyPassAdjustment = nil
            ball.velocity = velocity
            if abs(angle) > 0.000001 {
                earlyPassAdjustmentCount += 1
                lastEarlyPassAdjustmentAngle = angle
            }
        }
    }

    /// Small, deterministic execution error preserves the requested aim and remains reproducible.
    /// Both human and autonomous kicks use the same rating conversion and error distribution.
    private mutating func ratedKickVelocity(by actor: Int, aim: Vector2, speed: Double, isShot: Bool) -> Vector2 {
        guard roster[actor].clubPlayer != nil else { return aim.normalized * max(0, speed) }
        let abilities = roster[actor].abilities
        abilityKickSequence += 1
        let phase = Double(abilityKickSequence) * 2.399963229728653 + Double(actor) * 0.754877666
        let error = sin(phase) * (isShot ? abilities.shotErrorRadians : abilities.passErrorRadians)
        let power = isShot ? abilities.shotPower : abilities.passPower
        return aim.normalized.rotated(by: error) * max(0, speed * power)
    }

    private mutating func acceptsFreshKickInput() -> Bool {
        guard let baseline = kickInputBaseline else { return true }
        guard (validMovement - baseline).length > 0.2 else { return false }
        kickInputBaseline = nil
        return true
    }

    private mutating func applyChipInput(dt: Double) {
        guard chipRemaining > 0 else { return }
        guard acceptsFreshKickInput() else { chipRemaining = max(0, chipRemaining - dt); return }
        if validMovement.dot(originalKickDirection) <= -0.7, ball.velocity.length > 0.1,
           tuning.chipLiftSpeed > 0 {
            // Fresh pull-back can add lift during the launch window, including a powered shot
            // already above the turf. It never lowers an overhit shot into a safer trajectory.
            earlyPassAdjustment = nil
            ball.verticalVelocity = max(ball.verticalVelocity, tuning.chipLiftSpeed)
            chipCount += 1
            chipRemaining = 0
        } else { chipRemaining = max(0, chipRemaining - dt) }
    }

    private var ballNeedsBoundaryRescue: Bool {
        let nearEdge = abs(ball.position.x) > Pitch.width / 2 - 2 || abs(ball.position.y) > Pitch.length / 2 - 2
        let travellingOut = (abs(ball.position.x) > Pitch.width / 2 - 2 && ball.velocity.x * ball.position.x > 0.5)
            || (abs(ball.position.y) > Pitch.length / 2 - 2 && ball.velocity.y * ball.position.y > 0.5)
        return travellingOut || (nearEdge && ball.mode == .free && ball.velocity.length < 4)
    }

    private func ballIsStillInPlay() -> Bool {
        abs(ball.position.x) <= Pitch.width / 2 + Pitch.ballRadius
            && abs(ball.position.y) <= Pitch.length / 2 + Pitch.ballRadius
    }

    private func eligibleReceiver(_ id: Int) -> Bool {
        !roster[id].isUnavailable && (!roster[id].isGoalkeeper || mode == .match) && !roster[id].isTackling
            && (recoveryTimers[id] ?? 0) <= 0 && (kickGuards[id] ?? 0) <= 0
    }

    private func eligibleHeader(_ id: Int) -> Bool {
        roster.indices.contains(id) && !roster[id].isGoalkeeper && !roster[id].isUnavailable
            && !roster[id].isTackling && roster[id].fallProgress <= 0.001
            && (recoveryTimers[id] ?? 0) <= 0 && (kickGuards[id] ?? 0) <= 0
            && (headingTimers[id] ?? 0) <= 0
    }

    private func headerArrival(for actor: Int, window: Double) -> Double? {
        let state = roster[actor].state
        guard (ball.position - state.position).length <= 8 else { return nil }
        return HeadingMechanics.contactFraction(ball: ball, relativeOffset: ball.position - state.position,
            relativeTravel: (ball.velocity - state.velocity) * window, duration: window,
            gravity: tuning.ballGravity).map { $0 * window }
    }

    private mutating func armHeader(for actor: Int, aim: Vector2, goalDirected: Bool = false) {
        guard phase == .playing, eligibleHeader(actor), keeperHandsID == nil, ballIsStillInPlay(),
              ball.height > tuning.airborneContactHeight,
              headerArrival(for: actor, window: HeadingMechanics.prepareWindow) != nil else { return }
        queuedPass = nil
        queuedHeader = QueuedHeader(actorID: actor,
            aim: aim.length > 0.0001 ? aim.normalized : roster[actor].state.facing,
            goalDirected: goalDirected,
            remaining: HeadingMechanics.prepareWindow)
        if (ball.position - roster[actor].state.position).length <= HeadingMechanics.reach,
           ball.height >= HeadingMechanics.minimumHeight, ball.height <= HeadingMechanics.maximumHeight {
            performHeader(by: actor, aim: queuedHeader!.aim, human: true)
        }
    }

    private mutating func performHeader(by actor: Int, aim: Vector2, human: Bool, preparedFor: Double = 0) {
        guard eligibleHeader(actor), ballIsStillInPlay(), !penaliseOffsideInvolvement(by: actor) else { return }
        let contactHeight = ball.height
        let speed = min(28, max(16, 14 + ball.velocity.length * 0.35))
        let attacking = isAttackingCross(for: actor) && (!human || queuedHeader?.goalDirected == true)
        var contactPlayer = roster[actor]
        if let positions = offsideTouchPositions, positions.indices.contains(actor) {
            contactPlayer.state.position = positions[actor]
        }
        let finish = attacking ? HeadingMechanics.attackingHeader(ball: ball, player: contactPlayer,
            preparedFor: preparedFor, tuning: tuning, ends: ends,
            variation: sin(Double(abilityKickSequence + 1) * 2.399963229728653 + Double(actor) * 0.754877666)) : nil
        queuedHeader = nil
        queuedPass = nil
        activePassTargetID = nil
        let goalDirection = (ends.direction(for: roster[actor].team) * (Pitch.length / 2) - ball.position).normalized
        let direction = finish?.direction ?? (attacking ? goalDirection : aim.normalized)
        roster[actor].state.facing = direction
        kickBall(by: actor, aim: direction, speed: finish?.speed ?? speed, isShot: finish != nil, human: human)
        if let finish { ball.velocity = finish.direction * finish.speed }
        // A deliberate header is a new offside snapshot, but is not a foot backpass.
        handlingRestrictedTeam = nil
        ball.height = contactHeight
        ball.verticalVelocity = finish?.verticalVelocity ?? 1.5
        chipRemaining = 0
        endAftertouch()
        kickInputBaseline = nil
        kickGuards[actor] = max(0.4, tuning.reacquisitionDelay)
        reacquisitionCountdown = max(0.4, tuning.reacquisitionDelay)
        headingTimers[actor] = HeadingMechanics.animationDuration
        roster[actor].headingProgress = 0.001
        lastHeaderPlayerID = actor
        if human { headerCount += 1; lastKickKind = "header" }
    }

    private func incomingArrival(for actor: Int) -> Double? {
        let state = roster[actor].state
        let offset = ball.position - state.position
        let distance = offset.length
        guard distance <= tuning.queuedPassMaxDistance else { return nil }
        if actor == activePassTargetID, ball.mode == .pass {
            return neutralReceivingMeeting(for: actor, reach: tuning.queuedPassReach,
                horizon: max(0.01, tuning.queuedPassDuration))?.time
        }
        let relativeVelocity = ball.velocity - state.velocity
        // A stationary loose ball is a receiving context only while the footballer is actually
        // arriving at it; pointing a kick direction toward a far ball does not manufacture one.
        guard distance <= tuning.queuedPassReach || relativeVelocity.dot(offset.normalized) < -0.5 else { return nil }
        let window = max(0.01, tuning.queuedPassDuration)
        let time: Double
        if distance <= tuning.queuedPassReach { time = 0 }
        else {
            guard let fraction = sweptCircle(from: offset, by: relativeVelocity * window,
                                              center: .zero, radius: tuning.queuedPassReach) else { return nil }
            time = fraction * window
        }
        guard BallFlight.height(after: time, ball: ball, gravity: tuning.ballGravity) <= tuning.airborneContactHeight else { return nil }
        return time
    }

    private mutating func armQueuedKick(for actor: Int, aim: Vector2, heldFor duration: Double, receiving: Bool,
                                       passIntent: PassIntent? = nil) -> Bool {
        guard eligibleReceiver(actor), ballIsStillInPlay(),
              possessionID == nil || possessionID == actor else { return false }
        let state = roster[actor].state
        let offset = ball.position - state.position
        let distance = offset.length
        guard distance <= tuning.queuedPassMaxDistance else { return false }
        if receiving {
            guard incomingArrival(for: actor) != nil else { return false }
        } else {
            let movingTowardBall = aim.dot(offset.normalized) > 0.5
            let requestedClosingSpeed = movingTowardBall ? tuning.playerMaxSpeed * tuning.offBallSpeedBoost * 0.8 : 0
            let closingSpeed = max(state.velocity.dot(offset.normalized), requestedClosingSpeed)
                - ball.velocity.dot(offset.normalized)
            let estimatedArrival = max(0, distance - tuning.queuedPassReach) / max(0.001, closingSpeed)
            guard distance <= tuning.queuedPassReach || (closingSpeed > 0 && estimatedArrival <= tuning.queuedPassDuration) else { return false }
        }
        queuedPass = QueuedPass(actorID: actor, aim: aim, heldFor: max(0, duration),
                                passIntent: passIntent,
                                remaining: max(0.01, tuning.queuedPassDuration))
        queuedPassCount += 1
        if distance <= tuning.queuedPassReach, ball.height <= tuning.airborneContactHeight {
            executeQueuedPass(by: actor)
        }
        return true
    }

    private mutating func executeQueuedPass(by actor: Int) {
        guard let queued = queuedPass, queued.actorID == actor else { return }
        guard !penaliseOffsideInvolvement(by: actor) else { return }
        queuedPass = nil
        performHumanKick(by: actor, aim: queued.aim, heldFor: queued.heldFor, clearingBoundary: true,
                         passIntent: queued.passIntent)
        // Movement used to meet the arrival is not a fresh chip or curve command.
        kickInputBaseline = validMovement
    }

    private func clearanceDirection(_ requested: Vector2) -> Vector2 {
        var aim = requested
        if abs(ball.position.x) > Pitch.width / 2 - 1.8, aim.x * ball.position.x > 0 { aim.x = -aim.x }
        let outsideMouth = abs(ball.position.x) > Pitch.goalWidth / 2 - Pitch.postRadius - Pitch.ballRadius
        if outsideMouth, abs(ball.position.y) > Pitch.length / 2 - 1.8, aim.y * ball.position.y > 0 { aim.y = -aim.y }
        return aim.normalized
    }

    private mutating func performStandingTackle(by actor: Int) {
        let state = roster[actor].state
        let direction = validMovement.length > 0.001 && actor == selectedPlayerID ? validMovement.normalized : state.facing
        guard startTackle(id: actor, direction: direction, kind: .standing) else { return }
        if actor == selectedPlayerID {
            standingTackleCount += 1
            tackleCount += 1
        }
        let offset = ball.position - state.position
        let canTouchBall = ballIsStillInPlay() && ball.height <= tuning.airborneContactHeight
            && offset.length <= tuning.tackleReach * roster[actor].abilities.defending && offset.normalized.dot(direction) >= 0.45
        let footTravel = direction * max(0.01, tuning.tackleReach * roster[actor].abilities.defending)
        let ballFraction = canTouchBall ? sweptCircle(from: state.position, by: footTravel,
                                                    center: ball.position, radius: Pitch.ballRadius) : nil
        let opponents = roster.filter { !$0.isUnavailable && $0.team != roster[actor].team }.compactMap { opponent -> (Int, Double)? in
            guard let time = sweptCircle(from: state.position, by: footTravel, center: opponent.state.position,
                                         radius: Pitch.playerRadius * 0.65) else { return nil }
            return (opponent.id, time)
        }.sorted { $0.1 < $1.1 }
        if let (victim, time) = opponents.first {
            let behind = (state.position - roster[victim].state.position).normalized.dot(roster[victim].state.facing) < -0.4
            let decision = TackleRules.assess(kind: .standing, ballContactFraction: ballFraction,
                                              opponentContactFraction: time, approachFromBehind: behind,
                                              relativeSpeed: (state.velocity - roster[victim].state.velocity).length,
                                              randomUnit: nextRandomUnit())
            if decision.foul { commitFoul(offender: actor, victim: victim, decision: decision); return }
        }
        if canTouchBall { knockBallFromTackle(by: actor) }
    }

    private mutating func knockBallFromTackle(by actor: Int) {
        guard !penaliseOffsideInvolvement(by: actor) else { return }
        recordBallTouch(by: actor, deliberate: true)
        if actor == selectedPlayerID || possessionID == selectedPlayerID {
            challengeContactCount += 1
            lastChallengeWasSlide = tackleKinds[actor] == .slide
        }
        let direction = clearanceDirection(tackleDirections[actor] ?? roster[actor].state.facing)
        ball.velocity = direction * max(0, tuning.tackleBallSpeed)
        ball.mode = .free
        controlClaim = false
        possessionID = nil
        activePassTargetID = nil
        kickGuards[actor] = max(0.2, tuning.reacquisitionDelay)
        if mode == .solo { reacquisitionCountdown = max(0.2, tuning.reacquisitionDelay) }
        tackleHits.insert(actor)
        if actionDown, !actionWasTackle { actionCancelled = true }
        endAftertouch()
        chipRemaining = 0
    }

    private mutating func nextRandomUnit() -> Double {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(randomState >> 11) / Double(UInt64(1) << 53)
    }

    private func replacements(for id: Int) -> [ClubPlayer] {
        let team = roster[id].team
        let squad: [ClubPlayer]
        if let configuration {
            squad = (team == .blue ? configuration.home : configuration.away).team.players
        } else {
            squad = (1...5).map { index in
                let identity = "reserve-\(team.rawValue)-\(index)"
                return ClubPlayer(id: identity, name: "Reserve \(index)", position: index == 1 ? "G" : "M",
                    jerseyNumber: 10 + index, appearance: .generated(for: identity))
            }
        }
        let used = Set(roster.filter { $0.team == team }.compactMap { $0.clubPlayer?.id })
        return squad.filter {
            !used.contains($0.id) && !unavailableSquadIDs.contains($0.id)
                && (($0.role == "G") == roster[id].isGoalkeeper)
        }.sorted {
            $0.effectiveRating == $1.effectiveRating ? $0.id < $1.id : $0.effectiveRating > $1.effectiveRating
        }
    }

    private mutating func resolveFoulInjury() {
        guard mode == .match, let foul = lastFoul else { return }
        // Independent sequence: injuries never change existing card/kick randomness.
        injuryRandomState = injuryRandomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let roll = Double(injuryRandomState >> 11) / Double(UInt64(1) << 53)
        guard roll < min(1, max(0, tuning.foulInjuryChance)) else { return }
        let id = foul.victimID
        roster[id].isInjured = true
        substitutionNotice = "\(roster[id].clubPlayer?.displayName ?? "Player \(id + 1)") leaves injured"
        substitutionNoticeRemaining = 7
        if let identity = roster[id].clubPlayer?.id { unavailableSquadIDs.insert(identity) }
        accountForStoppage(6) // Treatment allowance; time spent browsing the squad is paused.
        cancelInput()
        if roster[id].team == .blue {
            pendingInjuryID = id
        } else if let replacement = replacements(for: id).first {
            replaceInjuredPlayer(id, with: replacement)
        }
    }

    @discardableResult
    mutating func substituteInjuredPlayer(with playerID: String) -> Bool {
        guard let id = pendingInjuryID, roster[id].isInjured, !roster[id].isSentOff,
              let replacement = replacements(for: id).first(where: { $0.id == playerID }),
              let foul = lastFoul else { return false }
        replaceInjuredPlayer(id, with: replacement)
        pendingInjuryID = nil
        prepareFreeKick(for: foul.awardedTeam)
        return true
    }

    mutating func continueWithoutInjuryReplacement() {
        guard pendingInjuryID != nil, injuryReplacements.isEmpty, let foul = lastFoul else { return }
        pendingInjuryID = nil
        prepareFreeKick(for: foul.awardedTeam)
    }

    private mutating func replaceInjuredPlayer(_ id: Int, with replacement: ClubPlayer) {
        let outgoing = roster[id]
        substitutionNotice = "\(replacement.displayName) on for injured \(outgoing.clubPlayer?.displayName ?? "player \(id + 1)")"
        substitutionNoticeRemaining = 7
        if let identity = outgoing.clubPlayer?.id { unavailableSquadIDs.insert(identity) }
        roster[id] = Footballer(id: id, team: outgoing.team,
            state: PlayerState(position: outgoing.state.position, facing: outgoing.state.facing))
        roster[id].isGoalkeeper = outgoing.isGoalkeeper
        roster[id].clubPlayer = replacement
        keeperStates[id] = nil
        keeperIntents[id] = nil
        kickGuards[id] = nil
        recoveryTimers[id] = nil
        tackleTimers[id] = nil
        rearPressure.removeAll()
    }

    func aiMovementScale(for id: Int) -> Double {
        tuning.aiSpeedScale * (roster[id].team == .red ? tuning.difficulty.speedMultiplier : 1)
    }

    /// Hard opponents assess lane clearance, receiver space and forward progress.
    /// Easier levels retain the familiar directional pass selection.
    func intelligentOpponentPassTarget(from owner: Int) -> Int? {
        guard tuning.difficulty == .hard else { return choosePassTarget(from: owner, aim: ends.direction(for: roster[owner].team)) }
        let origin = roster[owner].state.position
        let offside = OffsideRules.snapshot(actor: owner, ball: ball.position, roster: roster, ends: ends)?.candidates ?? []
        let candidates = roster.filter {
            $0.team == .red && $0.id != owner && !$0.isUnavailable && !$0.isGoalkeeper
                && !offside.contains($0.id) && ($0.state.position - origin).length < tuning.passAssistRange
                && ($0.state.position - origin).length > 4
        }
        let opponents = roster.filter { $0.team == .blue && !$0.isUnavailable }
        return candidates.compactMap { candidate -> (Int, Double)? in
            let offset = candidate.state.position - origin
            let clearance = opponents.map { opponent -> Double in
                let projection = min(1, max(0, (opponent.state.position - origin).dot(offset) / max(0.01, offset.lengthSquared)))
                return (opponent.state.position - (origin + offset * projection)).length
            }.min() ?? 20
            guard clearance > 2.2 else { return nil }
            let progress = (candidate.state.position.y - origin.y) * ends.attackSign(for: roster[owner].team)
            let space = opponents.map { ($0.state.position - candidate.state.position).length }.min() ?? 20
            return (candidate.id, progress * 0.7 + min(space, 12) + min(clearance, 8) - offset.length * 0.12)
        }.max { $0.1 < $1.1 }?.0
    }

    private mutating func commitFoul(offender: Int, victim: Int, decision: TackleDecision) {
        keeperHandsID = nil
        throughBallLandingPoint = nil
        guard phase == .playing, decision.foul else { return }
        resetOffsideForRestart()
        foulCount += 1
        let awarded = roster[victim].team
        pendingFoul = FoulEvent(id: foulCount, offenderID: offender, victimID: victim,
                                awardedTeam: awarded, position: roster[victim].state.position, card: decision.card)
        foulContactElapsed = 0
        foulOffenderWasSliding = roster[offender].isSliding
        let impact = tackleDirections[offender] ?? roster[offender].state.facing
        let victimVelocity = (roster[victim].state.velocity * 0.2 + impact * 4.5).clampedLength(6)
        let offenderVelocity = roster[offender].state.velocity * (foulOffenderWasSliding ? 0.65 : 0.2)
        phase = .foulContact(team: awarded)
        matchRestart = nil
        possessionID = nil
        controlClaim = false
        activePassTargetID = nil
        freeKickReadyTeam = nil
        ball.height = 0
        ball.verticalVelocity = 0
        ball.mode = .free
        if (ball.position - roster[victim].state.position).length <= 4 {
            ball.velocity = (ball.velocity * 0.35 + impact * 4.5).clampedLength(10)
        }
        for id in roster.indices { roster[id].state.velocity = .zero }
        cancelInput()
        roster[victim].fallDirection = victimVelocity.length > 0.01 ? victimVelocity.normalized : impact
        roster[victim].fallProgress = 0.01
        roster[victim].recoveryProgress = 0
        roster[offender].recoveryProgress = 0
        roster[victim].state.velocity = victimVelocity
        roster[offender].state.velocity = offenderVelocity
        roster[offender].isSliding = foulOffenderWasSliding
    }

    private mutating func advanceFoulAftermath(dt: Double) {
        guard let foul = pendingFoul else { return }
        let duration = max(0.1, tuning.foulContactDuration)
        let elapsed = min(dt, max(0, duration - foulContactElapsed))
        foulContactElapsed += elapsed
        for id in [foul.offenderID, foul.victimID] {
            let speed = roster[id].state.velocity.length
            let deceleration = id == foul.victimID ? 12.0 : 24.0
            let time = min(elapsed, speed / deceleration)
            roster[id].state.position += roster[id].state.velocity.normalized
                * max(0, speed * time - 0.5 * deceleration * time * time)
            roster[id].state.velocity = roster[id].state.velocity.normalized * max(0, speed - deceleration * elapsed)
            clampFootballer(id)
        }
        roster[foul.victimID].fallProgress = min(1, foulContactElapsed / duration)
        roster[foul.offenderID].isSliding = foulOffenderWasSliding
        let speed = ball.velocity.length
        let friction = max(1, tuning.ballFriction)
        let rollTime = min(elapsed, speed / friction)
        ball.position += ball.velocity.normalized * max(0, speed * rollTime - 0.5 * friction * rollTime * rollTime)
        ball.velocity = ball.velocity.normalized * max(0, speed - friction * elapsed)
        // Play has already stopped for contact: a rolling ball can never add a late goal or out event.
        ball.position.x = min(Pitch.width / 2 + Pitch.ballRadius, max(-Pitch.width / 2 - Pitch.ballRadius, ball.position.x))
        ball.position.y = min(Pitch.length / 2 + Pitch.ballRadius, max(-Pitch.length / 2 - Pitch.ballRadius, ball.position.y))
        if foulContactElapsed + 0.0000001 >= duration { whistleForPendingFoul() }
    }

    private mutating func whistleForPendingFoul() {
        guard let foul = pendingFoul else { return }
        var card = foul.card
        if card == .yellow {
            roster[foul.offenderID].yellowCards += 1
            if roster[foul.offenderID].yellowCards >= 2 { card = .red }
        }
        if card == .red { roster[foul.offenderID].isSentOff = true }
        lastFoul = FoulEvent(id: foul.id, offenderID: foul.offenderID, victimID: foul.victimID,
                             awardedTeam: foul.awardedTeam, position: foul.position, card: card)
        pendingFoul = nil
        phase = .freeKick(team: foul.awardedTeam)
        restartCountdown = max(0, tuning.freeKickDelay)
        roster[foul.victimID].fallProgress = 1
        for id in roster.indices {
            roster[id].state.velocity = .zero
            roster[id].isSliding = id == foul.offenderID && foulOffenderWasSliding
        }
        ball.velocity = .zero
        // Discipline takes effect at the whistle, while the visible recovery
        // finishes before a dismissal can end the exercise or place the kick.
    }

    private mutating func advanceFreeKickAftermath(for team: Team, dt: Double) {
        restartCountdown = max(0, restartCountdown - dt)
        if let foul = lastFoul {
            let duration = max(0.01, tuning.freeKickDelay)
            let progress = min(1, max(0, 1 - restartCountdown / duration))
            // Leave the victim on the turf after the whistle, then let both
            // players visibly plant their hands/knee and stand before placement.
            roster[foul.victimID].recoveryProgress = min(1, max(0, (progress - 0.23) / 0.67))
            if foulOffenderWasSliding {
                roster[foul.offenderID].recoveryProgress = min(1, max(0, (progress - 0.10) / 0.63))
            }
        }
        if restartCountdown <= 0 {
            resolveFoulInjury()
            if pendingInjuryID == nil { prepareFreeKick(for: team) }
        }
    }

    @discardableResult
    private mutating func checkPracticeCanContinue() -> Bool {
        guard mode != .solo else { return true }
        for team in [Team.blue, Team.red] {
            if !roster.contains(where: { $0.team == team && !$0.isUnavailable && !$0.isGoalkeeper }) {
                phase = .practiceEnded(losingTeam: team)
                ball.velocity = .zero
                ball.verticalVelocity = 0
                possessionID = nil
                controlClaim = false
                for id in roster.indices { roster[id].state.velocity = .zero }
                cancelInput()
                return false
            }
        }
        return true
    }

    private mutating func automaticReset() {
        if mode == .match {
            if let matchRestart { prepareMatchRestart(matchRestart) }
            return
        }
        let discipline = roster.map { ($0.yellowCards, $0.isSentOff, $0.isGoalkeeper) }
        let savedRandom = randomState
        let savedFoul = lastFoul
        reset()
        randomState = savedRandom
        lastFoul = savedFoul
        for id in roster.indices where id < discipline.count {
            roster[id].yellowCards = discipline[id].0
            roster[id].isSentOff = discipline[id].1
            roster[id].isGoalkeeper = discipline[id].2
        }
        guard checkPracticeCanContinue() else { return }
        if mode != .solo, roster[selectedPlayerID].isUnavailable || roster[selectedPlayerID].isGoalkeeper {
            selectedPlayerID = nearestFootballer(team: .blue, to: ball.position)
            ball.position = player.position + .up * 1.25
            possessionID = selectedPlayerID
            controlClaim = true
        }
    }

    private mutating func prepareFreeKick(for team: Team) {
        clearRestartSupport()
        keeperHandsID = nil
        throughBallLandingPoint = nil
        guard checkPracticeCanContinue(), let foul = lastFoul else { return }
        if mode == .match, PenaltyRules.awardsPenalty(at: foul.position,
            offender: roster[foul.offenderID].team, awarded: team, ends: ends) {
            prepareMatchRestart(MatchRestart(kind: .penalty, team: team,
                position: PenaltyRules.mark(for: team, ends: ends), takerID: nil))
            return
        }
        penaltyFlight = nil
        penaltySecondTouchTakerID = nil
        cancelInput()
        keeperStates.removeAll()
        keeperIntents.removeAll()
        ball = BallState()
        ball.position = Vector2(x: min(Pitch.width / 2 - 0.5, max(-Pitch.width / 2 + 0.5, foul.position.x)),
                                y: min(Pitch.length / 2 - 0.5, max(-Pitch.length / 2 + 0.5, foul.position.y)))
        let kicker = nearestFootballer(team: team, to: ball.position)
        let attack = ends.direction(for: team)
        for id in roster.indices {
            roster[id].state.velocity = .zero
            roster[id].fallProgress = 0
            roster[id].recoveryProgress = 0
            roster[id].fallDirection = .up
            roster[id].isSliding = false
            roster[id].goalkeeperDiveProgress = 0
            guard !roster[id].isUnavailable else { continue }
            if id == kicker {
                roster[id].state.position = ball.position - attack * 1.2
                roster[id].state.facing = attack
            } else {
                let clearance = roster[id].team == team ? 3.0 : tuning.freeKickStandBack
                let offset = roster[id].state.position - ball.position
                if offset.length < clearance {
                    let away = offset.length > 0.01 ? offset.normalized : Vector2(x: id.isMultiple(of: 2) ? 1 : -1, y: 0)
                    var candidate = ball.position + away * clearance
                    candidate.x = min(Pitch.width / 2 - Pitch.playerRadius, max(-Pitch.width / 2 + Pitch.playerRadius, candidate.x))
                    candidate.y = min(Pitch.length / 2 - Pitch.playerRadius, max(-Pitch.length / 2 + Pitch.playerRadius, candidate.y))
                    if (candidate - ball.position).length < clearance - 0.01 {
                        candidate = ball.position + (-ball.position).normalized * clearance
                    }
                    roster[id].state.position = candidate
                }
            }
            clampFootballer(id)
        }
        possessionID = kicker
        if team == .blue { selectBlue(kicker) }
        else { selectedPlayerID = nearestFootballer(team: .blue, to: ball.position) }
        controlClaim = selectedPlayerID == kicker
        ball.mode = .controlled
        kickGuards.removeAll()
        recoveryTimers.removeAll()
        dribbleCountdown = 0
        freeKickReadyTeam = team
        freeKickKickCountdown = 0.65
        if mode == .match {
            matchRestart = MatchRestart(kind: .freeKick, team: team, position: ball.position, takerID: kicker)
        }
        phase = .playing
        refreshRestartSupport()
        enforceRestartClearance()
        resetGeneration += 1
    }

    private mutating func clearRestartSupport() {
        restartOutletIDs.removeAll(keepingCapacity: true)
        restartOutletTargets.removeAll(keepingCapacity: true)
        restartSupportElapsed = 0
    }

    private var readyRestartOutletID: Int? {
        let readyDistance = restartSupportContext?.kind == .goalKick
            ? RestartSupport.goalAreaHalfWidth * 2 + 0.5 : 9.5
        return restartShortOutletIDs.first { (roster[$0].state.position - ball.position).length <= readyDistance }
    }

    private func eligibleRestartOutlet(_ id: Int) -> Bool {
        guard let restart = restartSupportContext, roster.indices.contains(id) else { return false }
        let player = roster[id]
        return player.team == restart.team && id != restart.takerID && !player.isGoalkeeper
            && !player.isUnavailable && !player.isTackling && !player.isSliding
            && player.fallProgress <= 0.001 && player.recoveryProgress <= 0.001
            && (recoveryTimers[id] ?? 0) <= 0
    }

    private mutating func refreshRestartSupport() {
        guard let context = restartSupportContext else { clearRestartSupport(); return }
        let available = roster.indices.filter { eligibleRestartOutlet($0) }
        let expectedCount = min(context.kind == .goalKick ? 1 : 2, available.count)
        // Keep the destinations as well as the identities stable throughout each run.
        guard restartOutletIDs.count != expectedCount
            || restartOutletIDs.contains(where: { !eligibleRestartOutlet($0) })
            || restartOutletTargets.count != restartOutletIDs.count else { return }
        let unavailable = Set(recoveryTimers.filter { $0.value > 0 }.map(\.key))
        let layout = RestartSupport.layout(for: context, roster: roster, unavailableIDs: unavailable,
            previousOutletIDs: restartOutletIDs, freeKickStandBack: tuning.freeKickStandBack, ends: ends)
        restartOutletIDs = layout.outletIDs
        restartOutletTargets = layout.outletTargets
    }

    private mutating func advanceRestartSupport(dt: Double) {
        guard let context = restartSupportContext else { return }
        restartSupportElapsed += dt
        refreshRestartSupport()
        for id in restartOutletIDs {
            guard let target = restartOutletTargets[id] else { continue }
            let offset = target - roster[id].state.position
            if context.kind == .goalKick || offset.length < 0.25 {
                roster[id].state.position = target
                roster[id].state.velocity = .zero
                roster[id].state.facing = (ball.position - roster[id].state.position).normalized
            } else {
                moveExerciseFootballer(id, stick: offset / max(1.5, offset.length),
                    speedScale: max(0, aiMovementScale(for: id)) * max(1, tuning.offBallSpeedBoost), dt: dt)
            }
        }
        if tuning.aiSpeedScale > 0 {
            // Only the supporting runners yield around stationary players. Moving the whole
            // roster here would disturb the taker's aim and the stationary restart ball.
            for _ in 0..<2 {
                for id in restartOutletIDs {
                    for other in roster.indices where other != id && !roster[other].isUnavailable {
                        let offset = roster[id].state.position - roster[other].state.position
                        let distance = offset.length
                        let spacing = Pitch.playerRadius * 2 + 0.05
                        if distance < spacing {
                            let away = distance > 0.0001 ? offset / distance : Vector2(x: id < other ? -1 : 1, y: 0)
                            roster[id].state.position += away * (spacing - distance)
                            clampFootballer(id)
                        }
                    }
                }
            }
        }
        enforceRestartClearance()
    }

    private mutating func enforceRestartClearance() {
        guard let context = restartSupportContext else { return }
        var occupied: [Vector2] = []
        for id in roster.indices where roster[id].team != context.team && !roster[id].isUnavailable {
            let target = RestartSupport.legalOpponentTarget(from: roster[id].state.position,
                team: roster[id].team, restart: context, occupied: occupied,
                freeKickStandBack: tuning.freeKickStandBack, ends: ends)
            roster[id].state.position = target
            roster[id].state.velocity = .zero
            occupied.append(target)
        }
    }

    private mutating func launchRedFreeKick() {
        guard let kicker = possessionID, roster[kicker].team == .red else { return }
        let goal = ends.direction(for: roster[kicker].team) * (Pitch.length / 2)
        let isShot = (goal - ball.position).length < 27
        var aim = (goal - ball.position).normalized
        activePassTargetID = isShot ? nil : readyRestartOutletID ?? choosePassTarget(from: kicker, aim: aim)
        if let target = activePassTargetID { aim = ledPassDirection(to: target, from: kicker) }
        let passSpeed = activePassTargetID.map { assistedPassSpeed(to: $0, from: kicker) } ?? tuning.passSpeed
        kickBall(by: kicker, aim: aim, speed: isShot ? tuning.shotMinSpeed * 1.25 : passSpeed,
                 isShot: isShot, human: false)
    }

    private mutating func startTackle(id: Int, direction: Vector2, kind: TackleKind) -> Bool {
        guard !roster[id].isUnavailable, !roster[id].isGoalkeeper, (recoveryTimers[id] ?? 0) <= 0 else { return false }
        rearPressure.removeValue(forKey: id)
        let duration = kind == .slide ? tuning.slideDuration : tuning.tackleDuration
        let recovery = kind == .slide ? tuning.slideRecovery : tuning.tackleRecovery
        tackleTimers[id] = max(0.01, duration)
        recoveryTimers[id] = max(0.01, duration) + max(0, recovery) / roster[id].abilities.defending
        tackleDirections[id] = direction.length > 0.0001 ? direction.normalized : roster[id].state.facing
        tackleKinds[id] = kind
        tackleHits.remove(id)
        roster[id].isTackling = true
        roster[id].isSliding = kind == .slide
        return true
    }

    private var selectionPinned: Bool {
        guard !roster[selectedPlayerID].isUnavailable else { return false }
        if isControllingGoalkeeper { return true }
        return curveRemaining > 0 || chipRemaining > 0 || isTackling
            || isControllingPassReceiver
            || ((recoveryTimers[selectedPlayerID] ?? 0) > 0 && selectionStick.length == 0)
            || freeKickReadyTeam != nil
            || (actionDown && !actionCancelled && !actionCommittedSlide)
            || (queuedPass?.actorID == selectedPlayerID && queuedPassRemaining > 0)
            || (queuedHeader?.actorID == selectedPlayerID)
            || (headingTimers[selectedPlayerID] ?? 0) > 0
    }

    /// Values inside this small selection dead zone cannot chatter between nearly tied players.
    /// Movement itself still uses the touch controller's ordinary joystick dead zone.
    private var selectionStick: Vector2 {
        validMovement.length >= max(0.15, tuning.joystickDeadZone) ? validMovement.normalized : .zero
    }

    /// The touch controller has already applied the joystick dead zone. Any remaining
    /// input belongs to the receiver immediately, including the aim held through release.
    /// Only a neutral stick asks the receiver to meet the physical flight line automatically.
    private func receivingMovementIntent() -> Vector2 {
        if isCrossInFlight, let cross = crossFlight, selectedPlayerID == cross.receiverID,
           !cross.manualSteering || validMovement.length <= 0.0001 {
            let target = crossMeeting(for: selectedPlayerID)?.position ?? cross.destination
            let offset = target - player.position
            return offset / max(0.75, offset.length)
        }
        guard isControllingPassReceiver else { return validMovement }
        guard validMovement.length <= 0.0001 else { return validMovement }
        guard (ball.position - player.position).length <= tuning.passAssistRange + 8 else { return .zero }
        let reach = queuedPass?.actorID == selectedPlayerID ? tuning.queuedPassReach : acquisitionReach(for: selectedPlayerID)
        let meeting = neutralReceivingMeeting(for: selectedPlayerID, reach: reach, horizon: 2.5,
            maximumRelativeSpeed: queuedPass?.actorID == selectedPlayerID ? nil : acquisitionSpeedLimit(for: selectedPlayerID))
        let target = meeting?.position ?? ball.position
        let offset = target - player.position
        return offset / max(0.75, offset.length)
    }

    private func neutralReceivingMeeting(for actor: Int, reach: Double, horizon: Double,
                                         maximumRelativeSpeed: Double? = nil) -> ReceiverInterception.Meeting? {
        let footballer = roster[actor]
        let speed = tuning.playerMaxSpeed * footballer.abilities.speed
            * (footballer.isGoalkeeper ? tuning.keeperFootSpeedScale : tuning.offBallSpeedBoost)
        return ReceiverInterception.meeting(ball: ball, receiver: footballer.state, speed: speed,
            acceleration: tuning.playerAcceleration * footballer.abilities.acceleration,
            deceleration: tuning.playerDeceleration, reach: reach, friction: tuning.ballFriction,
            gravity: tuning.ballGravity, maximumHeight: tuning.airborneContactHeight,
            horizon: horizon, maximumRelativeSpeed: maximumRelativeSpeed)
    }

    private func crossMeeting(for actor: Int) -> ReceiverInterception.Meeting? {
        let receiver = roster[actor]
        return ReceiverInterception.meeting(ball: ball, receiver: receiver.state,
            speed: tuning.playerMaxSpeed * tuning.offBallSpeedBoost * receiver.abilities.speed,
            acceleration: tuning.playerAcceleration * receiver.abilities.acceleration,
            deceleration: tuning.playerDeceleration, reach: 0.65, friction: tuning.ballFriction,
            gravity: tuning.ballGravity, maximumHeight: HeadingMechanics.maximumHeight,
            horizon: min(2.5, crossFlight?.remaining ?? 0))
    }

    /// Keep a recipient only while a normal run could still meet the real ball. This is
    /// deliberately independent of requested steering: the player remains free to change course.
    private func receiverCanStillMeetPass(_ id: Int) -> Bool {
        guard eligibleReceiver(id), ballIsStillInPlay() else { return false }
        if isCrossInFlight, crossFlight?.receiverID == id { return crossMeeting(for: id) != nil }
        let state = roster[id].state
        let speed = ball.velocity.length
        let friction = max(0, tuning.ballFriction)
        let runSpeed = max(0, tuning.playerMaxSpeed * tuning.offBallSpeedBoost * roster[id].abilities.speed)
        let reach = acquisitionReach(for: id)
        for frame in 0...20 {
            let time = Double(frame) * 0.1
            let rollingTime = friction > 0.001 ? min(time, speed / friction) : time
            let distance = max(0, speed * rollingTime - friction * rollingTime * rollingTime * 0.5)
            let point = ball.position + ball.velocity.normalized * distance
            if abs(point.x) > Pitch.width / 2 || abs(point.y) > Pitch.length / 2 { break }
            if (point - state.position).length <= reach + runSpeed * time { return true }
        }
        return false
    }

    private var selectableBluePlayers: [Footballer] {
        let eligible = roster.filter { $0.team == .blue && !$0.isUnavailable && !$0.isGoalkeeper }
        let ready = eligible.filter { !$0.isTackling && $0.fallProgress <= 0.001
            && (recoveryTimers[$0.id] ?? 0) <= 0 }
        return ready.isEmpty ? eligible : ready
    }

    private struct BlueSelection {
        let id: Int
        let advantage: Double
        let immediate: Bool
    }

    /// Nearby options are ranked by the run requested by the stick. Short path prediction lets
    /// a defender block a carrier or meet a moving ball, without promoting a remote aligned player.
    private func preferredBlueSelection(manual: Bool = false) -> BlueSelection {
        if let owner = possessionID, roster[owner].team == .blue, !roster[owner].isUnavailable,
           !roster[owner].isGoalkeeper || mode == .match {
            return BlueSelection(id: owner, advantage: .infinity, immediate: true)
        }
        let candidates = selectableBluePlayers
        guard !candidates.isEmpty else { return BlueSelection(id: selectedPlayerID, advantage: 0, immediate: false) }
        if let owner = possessionID, roster[owner].team == .blue,
           candidates.contains(where: { $0.id == owner }) {
            return BlueSelection(id: owner, advantage: .infinity, immediate: true)
        }
        let nearest = candidates.min {
            let a = ($0.state.position - ball.position).lengthSquared
            let b = ($1.state.position - ball.position).lengthSquared
            return abs(a - b) < 0.000001 ? $0.id < $1.id : a < b
        }!
        let currentEligible = candidates.contains { $0.id == selectedPlayerID }
        let stick = selectionStick
        if stick.length == 0 {
            let currentDistance = (player.position - ball.position).length
            let nearestDistance = (nearest.state.position - ball.position).length
            let clearlyRemote = currentDistance > nearestDistance + 3
                || (currentDistance > 16 && currentDistance > nearestDistance + 1.5)
            let chooseNearest = manual || !currentEligible || clearlyRemote
            return BlueSelection(id: chooseNearest ? nearest.id : selectedPlayerID,
                                 advantage: chooseNearest ? .infinity : 0, immediate: chooseNearest)
        }

        if isPressingFromBehind, let owner = possessionID, currentEligible {
            let toCarrier = roster[owner].state.position - player.position
            if toCarrier.length <= tuning.rearPressureBodyReach + 0.35,
               stick.dot(toCarrier.normalized) > 0.35 {
                return BlueSelection(id: selectedPlayerID, advantage: 0, immediate: false)
            }
        }
        let prediction = max(0, tuning.switchPredictionTime)
        var targets = [(ball.position, 0.0)]
        let predictedBall = ball.position + (ball.velocity * prediction).clampedLength(6)
        if (predictedBall - ball.position).length > 0.2 { targets.append((predictedBall, 0.10)) }
        if let owner = possessionID, roster[owner].team == .red {
            let state = roster[owner].state
            let path = state.velocity.length > 1 ? state.velocity * prediction : state.facing * 3
            targets.append((state.position + path.clampedLength(6), 0.08))
        }
        let distanceToThreat: (Footballer) -> Double = { footballer in
            targets.map { (footballer.state.position - $0.0).length }.min() ?? .infinity
        }
        let nearestThreat = candidates.map(distanceToThreat).min() ?? 0
        let nearestBall = (nearest.state.position - ball.position).length
        let extraReach = max(0, tuning.switchMaxExtraDistance)
        let nearby = candidates.filter {
            distanceToThreat($0) <= nearestThreat + extraReach
                && ($0.state.position - ball.position).length <= nearestBall + extraReach + 4
        }
        let runSpeed = max(1, tuning.playerMaxSpeed * tuning.offBallSpeedBoost)
        func score(_ footballer: Footballer) -> Double {
            let state = footballer.state
            var best = Double.infinity
            for (target, bias) in targets {
                let offset = target - state.position
                let alignment = offset.length > 0.1 ? stick.dot(offset.normalized) : 1
                // Alignment outweighs small distance differences but cannot bypass the nearby gate.
                var cost = offset.length / runSpeed + (1 - alignment) * 1.6 + bias
                cost -= max(0, state.velocity.dot(stick)) / runSpeed * 0.12
                if footballer.id == selectedPlayerID {
                    cost -= 0.22
                    if (state.position - ball.position).length < 3.2, alignment > 0.45 { cost -= 0.25 }
                }
                best = min(best, cost)
            }
            return best
        }
        let ranked = nearby.map { ($0.id, score($0)) }.sorted {
            abs($0.1 - $1.1) < 0.000001 ? $0.0 < $1.0 : $0.1 < $1.1
        }
        guard let best = ranked.first else { return BlueSelection(id: nearest.id, advantage: .infinity, immediate: true) }
        let currentNearby = nearby.contains { $0.id == selectedPlayerID }
        let currentScore = currentNearby ? score(roster[selectedPlayerID]) : .infinity
        let advantage = currentScore - best.1
        // Very similar options retain the current run. Clear new intent never waits for a cooldown.
        let change = best.0 != selectedPlayerID && (!currentNearby || advantage > 0.12)
        return BlueSelection(id: change ? best.0 : selectedPlayerID, advantage: advantage,
                             immediate: !currentNearby || advantage >= max(0.12, tuning.switchAdvantage))
    }

    private mutating func switchToNearestBlueImmediately() -> Bool {
        guard mode != .solo, !isTackling, freeKickReadyTeam == nil else { return false }
        // A neutral tap remains an explicit nearest-player fallback. With an active stick it must
        // agree with the same directional inference used before ACTION captured its actor.
        let candidate = preferredBlueSelection(manual: true).id
        guard candidate != selectedPlayerID else { return false }
        endAftertouch()
        chipRemaining = 0
        queuedPass = nil
        selectBlue(candidate)
        return true
    }

    private mutating func selectRelevantBluePlayer(dt: Double = 0) {
        guard phase == .playing, mode != .solo else { return }
        let selection = preferredBlueSelection()
        let candidate = selection.id
        guard !roster[candidate].isUnavailable else { return }
        if roster[selectedPlayerID].isUnavailable || (roster[selectedPlayerID].isGoalkeeper && !isControllingGoalkeeper) {
            selectBlue(candidate)
            return
        }
        guard !selectionPinned, candidate != selectedPlayerID else {
            switchCandidateID = nil
            switchCandidateElapsed = 0
            return
        }
        if selection.immediate { selectBlue(candidate); return }
        if switchCandidateID != candidate {
            switchCandidateID = candidate
            switchCandidateElapsed = 0
        }
        switchCandidateElapsed += dt
        if switchCountdown <= 0,
           switchCandidateElapsed + 0.0000001 >= max(0, tuning.switchCandidateDuration) {
            selectBlue(candidate)
        }
    }

    private mutating func selectBlue(_ id: Int) {
        guard roster[id].team == .blue, !roster[id].isUnavailable,
              !roster[id].isGoalkeeper || (mode == .match && (possessionID == id || activePassTargetID == id)),
              id != selectedPlayerID else { return }
        rearPressure.removeAll()
        selectedPlayerID = id
        receiverControlRemaining = 0
        switchCandidateID = nil
        switchCandidateElapsed = 0
        controlClaim = possessionID == id
        switchCountdown = max(0, tuning.switchCooldown)
        switchCount += 1
        if actionDown { actionCancelled = true }
        if let queued = queuedPass, queued.actorID != id { queuedPass = nil }
        if let queued = queuedHeader, queued.actorID != id { queuedHeader = nil }
    }

    private func nearestFootballer(team: Team, to target: Vector2) -> Int {
        roster.filter { $0.team == team && !$0.isUnavailable && !$0.isGoalkeeper }.min {
            let a = ($0.state.position - target).lengthSquared
            let b = ($1.state.position - target).lengthSquared
            return abs(a - b) < 0.000001 ? $0.id < $1.id : a < b
        }?.id ?? selectedPlayerID
    }

    private mutating func updateAttackingSupport() {
        attackingTargets.removeAll(keepingCapacity: true)
        guard mode == .match, keeperHandsID == nil else { return }
        // Untargeted loose balls keep the ordinary chaser; support roles must not
        // prevent the team from pursuing a restart or pass with no named receiver.
        let carrier = possessionID ?? (ball.mode == .pass && activePassTargetID != nil ? lastKickerID : nil)
        guard let carrier, !roster[carrier].isUnavailable else { return }
        let team = roster[carrier].team
        let bases = Dictionary(uniqueKeysWithValues: roster.filter { $0.team == team && !$0.isUnavailable && !$0.isGoalkeeper }
            .map { ($0.id, matchFormationTarget(for: $0.id, inPossession: true)) })
        let released: AttackingSupport.ReleasedPass?
        if possessionID == nil, let receiver = activePassTargetID, roster[receiver].team == team {
            released = AttackingSupport.ReleasedPass(receiverID: receiver,
                destination: throughBallLandingPoint ?? roster[receiver].state.position)
        } else { released = nil }
        attackingTargets = AttackingSupport.targets(roster: roster, team: team, carrierID: carrier,
            ball: ball, baseTargets: bases, releasedPass: released,
            offsideLine: OffsideRules.line(team: team, ball: ball.position, roster: roster, ends: ends), ends: ends)
        // A wide carrier invites near-post, central and far-post runs before releasing.
        // After release those runs can cross the old line; Law 11 still uses the kick snapshot.
        let boxRuns = CrossingMechanics.supportTargets(crosser: roster[carrier], roster: roster,
            offsideLine: possessionID != nil
                ? OffsideRules.line(team: team, ball: ball.position, roster: roster, ends: ends) : nil, ends: ends)
        for (id, target) in boxRuns where id != activePassTargetID { attackingTargets[id] = target }
    }

    private func aiTarget(for id: Int) -> Vector2 {
        let footballer = roster[id]
        guard !footballer.isUnavailable, !footballer.isGoalkeeper else { return footballer.state.position }
        if let regroup = keeperRegroupTarget(for: id) { return regroup }
        let team = footballer.team
        let attack = ends.attackSign(for: team)
        let members = roster.filter { $0.team == team && !$0.isGoalkeeper }.map(\.id)
        let slot = members.firstIndex(of: id) ?? 0
        let lane = mode == .match ? (slot.isMultiple(of: 2) ? -13.0 : 13.0)
            : (team == .blue ? [0.0, -12, 12][slot % 3] : [-12.0, 12, 0][slot % 3])
        let friendlyPassTravelling = ball.mode == .pass && activePassTargetID != nil
            && lastKickerID.map { roster[$0].team == team } == true
        var target: Vector2
        if possessionID == id {
            let attackingDirection = Vector2.up * attack
            if (ball.position - footballer.state.position).dot(attackingDirection) < 0.2 {
                let side = id.isMultiple(of: 2) ? 1.0 : -1.0
                target = ball.position - attackingDirection * 1.2 + Vector2(x: side * 0.85, y: 0)
            } else {
                let nearestOpponent = nearestFootballer(team: team == .blue ? .red : .blue, to: footballer.state.position)
                let separation = footballer.state.position - roster[nearestOpponent].state.position
                let evade = separation.length < 5 ? separation.normalized.x * 5 : 0
                target = footballer.state.position + Vector2(x: evade - footballer.state.position.x * 0.12, y: attack * 14)
            }
        } else if isCrossInFlight, crossFlight?.receiverID == id {
            target = crossMeeting(for: id)?.position ?? crossFlight!.destination
        } else if activePassTargetID == id, let landing = throughBallLandingPoint {
            target = landing
        } else if activePassTargetID == id {
            let distance = (footballer.state.position - ball.position).length
            target = ball.position + ball.velocity * min(0.45, distance / max(8, ball.velocity.length))
        } else if let support = attackingTargets[id] {
            target = support
        } else if possessionTeam == team || friendlyPassTravelling {
            let anchorID = possessionTeam == team ? possessionID : activePassTargetID
            let anchor = anchorID.map { roster[$0].state.position } ?? ball.position
            let sideOffset = footballer.state.position.x - anchor.x
            let side = abs(sideOffset) > 1 ? (sideOffset > 0 ? 1.0 : -1.0) : (id.isMultiple(of: 2) ? 1.0 : -1.0)
            let offeringReturn = lastKickerID == id
            // The passer moves into a short return lane rather than chasing their own pass.
            target = anchor + Vector2(x: side * (offeringReturn ? 8 : 11), y: attack * (offeringReturn ? 5 : 8))
        } else if nearestFootballer(team: team, to: ball.position) == id {
            target = ball.position + ball.velocity * (team == .red ? tuning.difficulty.anticipation : 0.16)
        } else {
            target = mode == .match ? matchFormationTarget(for: id, inPossession: false)
                : Vector2(x: lane + ball.position.x * 0.2, y: ball.position.y - attack * (id % 2 == 0 ? 13 : 21))
        }
        let chasing = possessionID == id || activePassTargetID == id
            || (possessionTeam != team && nearestFootballer(team: team, to: ball.position) == id)
        let inset = chasing ? Pitch.playerRadius : 6.0
        target.x = min(Pitch.width / 2 - inset, max(-Pitch.width / 2 + inset, target.x))
        target.y = min(Pitch.length / 2 - inset, max(-Pitch.length / 2 + inset, target.y))
        return target
    }

    private mutating func prepareAITackles() {
        guard let owner = possessionID, keeperHandsID != owner,
              !(runningWinProtection > 0 && runningWinOwnerID == owner) else { return }
        for id in roster.indices where id != selectedPlayerID && roster[id].team != roster[owner].team
            && !roster[id].isUnavailable && !roster[id].isGoalkeeper {
            let offset = ball.position - roster[id].state.position
            if offset.length <= tuning.tackleReach * roster[id].abilities.defending,
               offset.normalized.dot(roster[id].state.facing) >= 0.45,
               nearestFootballer(team: roster[id].team, to: ball.position) == id {
                performStandingTackle(by: id)
                if phase != .playing { return }
            }
        }
    }

    private mutating func performAIBallAction() {
        guard let owner = possessionID, !roster[owner].isUnavailable, keeperHandsID != owner, roster[owner].team == .red,
              ball.height <= tuning.airborneContactHeight, aiDecisionCountdown <= 0,
              (ball.position - roster[owner].state.position).length <= tuning.kickReach else { return }
        guard !penaliseOffsideInvolvement(by: owner) else { return }
        let state = roster[owner].state
        let goal = ends.direction(for: roster[owner].team) * (Pitch.length / 2)
        let distanceToGoal = (goal - ball.position).length
        let opponent = nearestFootballer(team: .blue, to: state.position)
        let underPressure = (roster[opponent].state.position - state.position).length < (tuning.difficulty == .hard ? 8 : 5)
        let smartTarget = intelligentOpponentPassTarget(from: owner)
        if crossingOpportunity(for: owner) != nil,
           let plan = CrossingMechanics.plan(origin: ball.position, crosser: roster[owner], roster: roster,
                heldFor: tuning.holdThreshold + tuning.fullChargeDuration * (0.62 + nextRandomUnit() * 0.3),
                tuning: tuning, ends: ends, sequence: abilityKickSequence,
                excludedReceiverIDs: crossingExclusions(for: owner)) {
            launchCross(by: owner, plan: plan, human: false)
            aiDecisionCountdown = 1
            return
        }
        var direction: Vector2
        var speed: Double
        if distanceToGoal < 24 {
            direction = (goal - ball.position).normalized
            speed = tuning.shotMinSpeed + (tuning.shotMaxSpeed - tuning.shotMinSpeed) * 0.45
            ball.mode = .shot
            activePassTargetID = nil
        } else if underPressure || roster[owner].isGoalkeeper || (tuning.difficulty == .hard && smartTarget != nil),
                  let target = smartTarget {
            direction = ledPassDirection(to: target, from: owner)
            speed = assistedPassSpeed(to: target, from: owner)
            ball.mode = .pass
            activePassTargetID = target
        } else {
            aiDecisionCountdown = 0.35
            return
        }
        if tuning.difficulty.kickError > 0 {
            direction = direction.rotated(by: (nextRandomUnit() * 2 - 1) * tuning.difficulty.kickError)
        }
        recordBallTouch(by: owner, deliberate: true)
        ball.velocity = ratedKickVelocity(by: owner, aim: direction,
            speed: speed * (roster[owner].isGoalkeeper ? tuning.keeperFootKickScale : 1), isShot: ball.mode == .shot)
        possessionID = nil
        controlClaim = false
        lastKickerID = owner
        kickGuards[owner] = max(0, tuning.reacquisitionDelay)
        releaseReturningReceiverGuard(from: owner, isShot: ball.mode == .shot)
        aiDecisionCountdown = 1
        endAftertouch()
    }
}
