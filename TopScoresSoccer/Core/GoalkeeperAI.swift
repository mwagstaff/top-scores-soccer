import Foundation

/// Deterministic arcade decisions. The simulation owns movement and the shared swept contact
/// timeline; this helper never moves, attracts or acquires the ball ahead of physical contact.
enum GoalkeeperAI {
    struct Configuration: Equatable, Sendable {
        var ends = MatchEnds()
        var boxHalfWidth = 20.0
        var boxDepth = 16.5
        var homeDepth = 2.2
        var maximumPositioningDepth = 4.5
        var movementSpeed = 6.2
        var acceleration = 28.0
        var collectionSpeedLimit = 14.0
        var collectionHeight = 1.0
        var standingReach = 1.15
        var standingSaveHeight = 2.15
        var catchSpeedLimit = 18.0
        var catchHeight = 1.8
        var diveLookAhead = 0.42
        var minimumDiveOffset = 0.75
        var maximumDiveOffset = 4.8
        var diveSpeed = 10.5
        var diveDuration = 0.28
        var diveReach = 1.85
        var diveSaveHeight = 1.0       // A stretched low dive trades upright height for horizontal reach.
        var diveCatchSpeedLimit = 14.0
        var recoveryDuration = 0.65
        var recoverySpeedScale = 0.35
        var recoveryReach = 0.8
        var recoverySaveHeight = 0.9
        var distributionDelay = 0.65
        var gravity = 18.0
        static let defaults = Configuration()
    }

    struct State: Equatable, Sendable {
        var diveRemaining = 0.0
        var recoveryRemaining = 0.0
        var diveDirection = Vector2.zero
        var recoveryPoseExtent = 0.0
        var holdingElapsed = 0.0
    }

    struct ContactProfile: Equatable, Sendable {
        let reach: Double
        let maximumHeight: Double
    }

    struct Intent: Equatable, Sendable {
        let velocity: Vector2
        let facing: Vector2
        let isDiving: Bool
        let diveProgress: Double
        let saveReach: Double
        let maxSaveHeight: Double
        let shouldDistribute: Bool
    }

    enum SaveOutcome: Equatable, Sendable {
        case catchBall
        case parry(velocity: Vector2, verticalVelocity: Double)
    }

    static func isInOwnBox(_ position: Vector2, team: Team,
                           configuration: Configuration = .defaults) -> Bool {
        guard position.x.isFinite, position.y.isFinite else { return false }
        let depth = Pitch.length / 2 + position.y * configuration.ends.attackSign(for: team)
        return abs(position.x) <= configuration.boxHalfWidth && depth >= 0 && depth <= configuration.boxDepth
    }

    static func contactProfile(state: State, configuration: Configuration = .defaults) -> ContactProfile {
        if state.diveRemaining > 0 {
            return ContactProfile(reach: configuration.diveReach, maximumHeight: configuration.diveSaveHeight)
        }
        if state.recoveryRemaining > 0 {
            return ContactProfile(reach: configuration.recoveryReach, maximumHeight: configuration.recoverySaveHeight)
        }
        return ContactProfile(reach: configuration.standingReach, maximumHeight: configuration.standingSaveHeight)
    }

    static func effectiveSaveReach(ball: BallState, team: Team, state: State,
                                   configuration: Configuration = .defaults) -> Double {
        let reach = contactProfile(state: state, configuration: configuration).reach
        guard ball.mode == .shot else { return reach }
        let postLimit = Pitch.goalWidth / 2 - Pitch.ballRadius
        let ownGoalY = -configuration.ends.attackSign(for: team) * Pitch.length / 2
        let lineTime = abs(ball.velocity.y) > 0.001
            ? (ownGoalY - ball.position.y) / ball.velocity.y : -1
        let goalLineX = lineTime >= 0
            ? ball.position.x + ball.velocity.x * lineTime : ball.position.x
        let widthFraction = abs(goalLineX) / max(0.1, postLimit)
        // The central 45% keeps the ordinary physical reach. Only genuinely post-bound
        // placement tapers the useful contact area, increasingly toward the corner.
        let postProximity = min(1, max(0, (widthFraction - 0.45) / 0.55))
        return reach * (1 - 0.25 * pow(postProximity, 2))
    }

    /// Pose extent, not an animation clock: spread out during the dive, then get upright.
    private static func divePoseExtent(state: State, configuration: Configuration) -> Double {
        if state.diveRemaining > 0 {
            let elapsed = configuration.diveDuration - state.diveRemaining
            return min(1, max(0.001, elapsed / max(0.001, configuration.diveDuration * 0.55)))
        }
        return state.recoveryPoseExtent
            * min(1, max(0, state.recoveryRemaining / max(0.001, configuration.recoveryDuration)))
    }

    static func step(state: inout State, keeper: PlayerState, team: Team, ball: BallState,
                     ownsBall: Bool, dt: Double, handlingAllowed: Bool = true, configuration: Configuration = .defaults) -> Intent {
        let attack = configuration.ends.attackSign(for: team)
        let upfield = Vector2.up * attack
        guard dt.isFinite, dt > 0 else {
            let profile = contactProfile(state: state, configuration: configuration)
            return Intent(velocity: .zero, facing: keeper.facing, isDiving: state.diveRemaining > 0,
                          diveProgress: divePoseExtent(state: state, configuration: configuration),
                          saveReach: profile.reach, maxSaveHeight: profile.maximumHeight, shouldDistribute: false)
        }
        state.diveRemaining = max(0, state.diveRemaining - dt)
        state.recoveryRemaining = max(0, state.recoveryRemaining - dt)
        let goalwardShot = ball.mode == .shot && ball.velocity.y * attack < -5
        if ownsBall {
            state.diveRemaining = 0
            state.holdingElapsed += dt
            let pose = divePoseExtent(state: state, configuration: configuration)
            return Intent(velocity: .zero, facing: pose > 0 ? state.diveDirection : upfield,
                          isDiving: false, diveProgress: pose, saveReach: 0,
                          maxSaveHeight: 0,
                          shouldDistribute: state.holdingElapsed + 0.0000001 >= configuration.distributionDelay
                            && state.recoveryRemaining <= 0.0000001)
        }
        state.holdingElapsed = 0

        let goalY = -attack * Pitch.length / 2
        let ballDepth = max(0, (ball.position.y - goalY) * attack)
        let positioningDepth = min(configuration.maximumPositioningDepth,
                                   configuration.homeDepth + max(0, 25 - ballDepth) * 0.10)
        let trackingX = ball.position.x * positioningDepth / max(positioningDepth, ballDepth)
        var target = Vector2(x: min(Pitch.goalWidth / 2, max(-Pitch.goalWidth / 2, trackingX)),
                             y: goalY + attack * positioningDepth)

        // A keeper has time to set behind a distant, straight goal-bound shot. Predict only
        // from its current velocity: late aftertouch changes that line and can still wrong-foot
        // the keeper. Close shots provide too little travel time for this positioning to become
        // a disguised teleport across the goal mouth.
        if goalwardShot {
            let crossingTime = (keeper.position.y - ball.position.y) / ball.velocity.y
            if crossingTime > 0, crossingTime <= 1.6 {
                let crossingX = ball.position.x + ball.velocity.x * crossingTime
                let goalLimit = Pitch.goalWidth / 2 - Pitch.ballRadius
                let arrivalHeight = BallFlight.height(after: crossingTime, ball: ball,
                    gravity: configuration.gravity)
                if abs(crossingX) <= goalLimit + configuration.diveReach,
                   arrivalHeight <= configuration.standingSaveHeight + 0.25 {
                    let read = min(0.82, max(0.18, (crossingTime - 0.08) / 0.82))
                    target.x = min(goalLimit, max(-goalLimit,
                        target.x * (1 - read) + crossingX * read))
                }
            }
        }

        if isInOwnBox(ball.position, team: team, configuration: configuration),
           ball.velocity.length <= configuration.collectionSpeedLimit,
           ball.height <= configuration.collectionHeight {
            target = ball.position
        }

        // Commit to a reachable low shot once it approaches the keeper's plane. A distant
        // perfectly placed shot is not an excuse to teleport across the goal mouth.
        if handlingAllowed, state.diveRemaining <= 0, state.recoveryRemaining <= 0,
           ball.velocity.y * attack < -5,
           isInOwnBox(keeper.position, team: team, configuration: configuration) {
            let crossingTime = (keeper.position.y - ball.position.y) / ball.velocity.y
            let crossingX = ball.position.x + ball.velocity.x * crossingTime
            let lateral = crossingX - keeper.position.x
            if crossingTime >= 0, crossingTime <= configuration.diveLookAhead,
               abs(crossingX) <= Pitch.goalWidth / 2 + configuration.standingReach,
               abs(lateral) >= configuration.minimumDiveOffset,
               abs(lateral) <= configuration.maximumDiveOffset,
               BallFlight.height(after: crossingTime, ball: ball,
                                 gravity: configuration.gravity) <= configuration.diveSaveHeight {
                state.diveRemaining = configuration.diveDuration
                state.recoveryRemaining = configuration.diveDuration + configuration.recoveryDuration
                state.diveDirection = Vector2(x: lateral > 0 ? 1 : -1, y: 0)
                state.recoveryPoseExtent = 1
            }
        }

        let diving = state.diveRemaining > 0
        let speed = diving ? configuration.diveSpeed : configuration.movementSpeed
            * (state.recoveryRemaining > 0 ? configuration.recoverySpeedScale : 1)
        let desired = diving ? state.diveDirection * speed
            : (target - keeper.position).clampedLength(speed * dt) / dt
        let velocity = diving ? desired
            : (keeper.velocity + (desired - keeper.velocity).clampedLength(configuration.acceleration * dt)).clampedLength(speed)
        let next = keeper.position + velocity * dt
        let inset = Pitch.playerRadius
        let clamped = Vector2(x: min(configuration.boxHalfWidth - inset, max(-configuration.boxHalfWidth + inset, next.x)),
                              y: goalY + attack * min(configuration.boxDepth - inset,
                                                      max(inset, (next.y - goalY) * attack)))
        let boundedVelocity = (clamped - keeper.position).clampedLength(speed * dt) / dt
        let toBall = ball.position - keeper.position
        let profile = contactProfile(state: state, configuration: configuration)
        let pose = divePoseExtent(state: state, configuration: configuration)
        return Intent(velocity: boundedVelocity,
                      facing: pose > 0 ? state.diveDirection : toBall.length > 0.001 ? toBall.normalized : upfield,
                      isDiving: diving,
                      diveProgress: pose,
                      saveReach: profile.reach, maxSaveHeight: profile.maximumHeight,
                      shouldDistribute: false)
    }

    /// Call only for the selected swept contact, using ball and keeper positions at that
    /// contact time. The explicit reach check also makes accidental distant catches impossible.
    static func saveOutcome(ball: BallState, keeper: PlayerState, team: Team, state: State,
                            configuration: Configuration = .defaults) -> SaveOutcome? {
        let profile = contactProfile(state: state, configuration: configuration)
        // At full stretch beside a post the keeper has less useful contact area than through
        // the middle. Long shots can still be covered by earlier positioning; a close corner
        // finish cannot be erased by the same generous reach as a central shot.
        let effectiveReach = effectiveSaveReach(ball: ball, team: team, state: state,
                                                configuration: configuration)
        guard isInOwnBox(keeper.position, team: team, configuration: configuration),
              isInOwnBox(ball.position, team: team, configuration: configuration),
              ball.height.isFinite, ball.height >= 0, ball.height <= profile.maximumHeight,
              ball.velocity.x.isFinite, ball.velocity.y.isFinite,
              (ball.position - keeper.position).length <= effectiveReach + 0.00001 else { return nil }
        let relativeSpeed = (ball.velocity - keeper.velocity).length
        let catchSpeed = state.diveRemaining > 0 ? configuration.diveCatchSpeedLimit : configuration.catchSpeedLimit
        if relativeSpeed <= catchSpeed, ball.height <= configuration.catchHeight {
            return .catchBall
        }
        let offset = ball.position.x - keeper.position.x
        let side = abs(offset) > 0.05 ? (offset > 0 ? 1.0 : -1.0)
            : abs(ball.velocity.x) > 0.05 ? (ball.velocity.x > 0 ? 1.0 : -1.0)
            : configuration.ends.attackSign(for: team)
        let direction = Vector2(x: side * 0.8, y: configuration.ends.attackSign(for: team) * 0.6)
        let speed = min(24, max(8, ball.velocity.length * 0.58))
        return .parry(velocity: direction * speed, verticalVelocity: min(3, 0.8 + ball.height * 0.4))
    }

    /// A selected contact starts the save's recovery; ownership itself remains in the simulation.
    static func recordSave(state: inout State, outcome: SaveOutcome,
                           configuration: Configuration = .defaults) {
        state.holdingElapsed = 0
        if case .catchBall = outcome {
            let pose = divePoseExtent(state: state, configuration: configuration)
            state.diveRemaining = 0
            state.recoveryRemaining = pose > 0 ? configuration.recoveryDuration : 0
            state.recoveryPoseExtent = pose
        } else {
            state.recoveryRemaining = max(state.recoveryRemaining,
                                          state.diveRemaining + configuration.recoveryDuration)
        }
    }
}
