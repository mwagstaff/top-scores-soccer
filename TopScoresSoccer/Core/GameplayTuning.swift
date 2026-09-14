import Foundation

/// Pitch distances are metres; time is seconds; angles are radians unless named otherwise.
struct GameplayTuning: Equatable, Sendable {
    var difficulty: GameDifficulty = .medium
    var foulInjuryChance = 0.04        // per foul; separate from card severity and difficulty
    var playerAcceleration = 42.0       // m/s², response toward requested speed
    var playerMaxSpeed = 10.5           // m/s
    var offBallSpeedBoost = 1.12        // multiplier; dribbling keeps normal running speed
    var playerDeceleration = 30.0       // m/s², neutral stick and aftertouch coasting
    var playerTurnRate = 12.0           // radians/s, facing at full running speed
    var ballFriction = 5.0              // m/s², ground rolling resistance
    var passSpeed = 21.0                // m/s, minimum speed for an assisted teammate pass
    var passArrivalSpeed = 12.0         // m/s, intended arrival speed for distance-adjusted passes
    var knockAheadSpeed = 9.0           // m/s, stationary untargeted tap
    var knockAheadSpeedBonus = 3.0      // m/s added to forward running speed for a chaseable tap
    var shotAssistAngle = 50.0          // degrees, half-cone around the opposition goal
    var shotAssistRange = 140.0         // m, covers the whole practice pitch for goal-directed holds
    var shotMinSpeed = 25.0             // m/s
    var shotMaxSpeed = 47.0             // m/s
    var shootingRange = 35.0           // m from goal centre, independent of facing and teammates
    var shortPassRange = 22.0          // m; the dedicated pass button never selects a long outlet
    var shotChargeDuration = 0.95      // seconds from button-down to full power
    var joystickDeadZone = 0.12         // fraction of joystick radius
    var holdThreshold = 0.26            // seconds; forgiving short releases pass
    var fullChargeDuration = 0.65       // seconds beyond the hold threshold
    var dribbleTouchInterval = 0.075     // seconds between nudges
    var dribbleReach = 2.5              // m, reachable for a new nudge
    var controlAcquireDistance = 2.4   // m
    var controlReleaseDistance = 3.5    // m, wider than acquisition
    var controlRelativeSpeed = 18.0     // m/s, acquisition limit
    var kickReach = 3.4                 // m, covers ordinary dribble gaps
    var reacquisitionDelay = 0.28       // seconds after striking the ball
    var aftertouchDuration = 0.70       // seconds of diminishing directional influence
    var aftertouchStrength = 0.72       // radians/s at full lateral stick before decay
    var aftertouchDecay = 1.7           // unitless exponent; higher values fade curve sooner
    var aftertouchMaxAngle = 9.0        // realistic cap from the initial shot direction
    var cameraSmoothing = 9.0           // response rate, 1/s
    var cameraLookAhead = 0.28          // seconds of ball velocity
    var restartDelay = 1.1              // seconds of goal/out feedback
    var passAssistAngle = 75.0          // degrees, forgiving half-angle of directional teammate cone
    var passAssistRange = 42.0          // m, maximum assisted teammate selection distance
    var kickAimStickThreshold = 0.28    // joystick fraction required to deliberately change the kick aim
    var kickAimMemoryDuration = 0.22    // seconds to retain a deliberate direction after the stick lifts
    var passLead = 0.85                 // fraction of predicted teammate travel during the pass
    var passEarlyAdjustmentEnabled = true // one guarded correction for very early receiver steering
    var receivingSpeed = 34.0           // m/s, maximum relative speed for a cushioning player contact
    var tackleDuration = 0.10           // seconds, standing poke commitment
    var tackleRecovery = 0.28           // seconds after a standing poke
    var tackleSpeed = 14.0              // m/s during a lunge
    var tackleReach = 1.30              // m, standing poke reach within the facing cone
    var tackleBallSpeed = 17.0          // m/s, loose-ball knock following a tackle
    var switchCooldown = 0.10           // seconds between ambiguous selection changes; clear intent bypasses this
    var switchAdvantage = 0.45          // weighted seconds, clear directional score advantage for an immediate switch
    var switchCandidateDuration = 0.06 // seconds of confirmation only when directional scores are ambiguous
    var switchPredictionTime = 0.4     // seconds of ball/carrier path considered, capped to 6m
    var switchMaxExtraDistance = 8.0   // m farther from the threat than the nearest eligible option
    var aiSpeedScale = 0.82             // fraction of human maximum speed for exercise players
    var slideHoldThreshold = 0.22       // seconds, off-ball hold before committing a slide
    var slideDuration = 0.30            // seconds of committed sliding movement
    var slideRecovery = 1.0             // seconds after a slide before full control returns
    var slideSpeed = 16.0               // m/s, committed velocity/facing direction at slide start
    var slideReach = 1.30               // m, physical stretched-foot ball contact radius
    var passiveControlReach = 1.9       // m, forgiving foot reach for front/side running challenges
    var rearPressureBodyReach = 1.95    // m, close pursuit distance behind the carrier
    var rearPressureBallReach = 3.2     // m, includes the ball shielded in front of the carrier
    var rearPressureDuration = 0.5      // seconds of uninterrupted close pursuit before a rear steal
    var queuedPassDuration = 1.0       // seconds, one actor-bound first-time pass opportunity
    var queuedPassMaxDistance = 14.0    // m, maximum distance at which a pass may be armed
    var queuedPassReach = 1.30          // m, contact radius; no kick occurs at the queue distance
    var foulContactDuration = 1.2     // seconds of visible fall and follow-through before the whistle
    var freeKickDelay = 2.4            // seconds of foul/card feedback before placing the kick
    var freeKickStandBack = 9.15        // m, opponents' clearance from the free-kick spot (IFAB Law 13)
    var chipWindowDuration = 0.24       // seconds after a kick to pull back for a chip
    var chipLiftSpeed = 8.0             // m/s, initial upward speed of a chip
    var ballGravity = 18.0              // m/s², exaggerated arcade flight gravity
    var airborneContactHeight = 0.65    // m of ground clearance reachable by feet
    var keeperFootSpeedScale = 0.72     // fraction of outfield running speed under manual keeper control
    var keeperFootKickScale = 0.78      // fraction of outfield foot-kick power
    var keeperFootAcquireDistance = 1.35 // m, less forgiving keeper foot pickup
    var keeperFootReleaseDistance = 2.2 // m, tighter keeper dribble retention
    var keeperFootControlSpeed = 12.0   // m/s, keeper cushioning limit with feet
    var backheelReversalWindow = 0.12  // seconds between deliberate reverse swipe and release
    var matchDuration = 180.0           // seconds of live play across two halves
    var matchRestartDelay = 0.8         // seconds of restart feedback before placing the ball
    static let defaults = GameplayTuning()
}

enum GameDifficulty: String, CaseIterable, Sendable {
    case easy, medium, hard

    var title: String { rawValue.capitalized }
    var description: String {
        switch self {
        case .easy: "Slower opponents, more hesitation and less accurate decisions."
        case .medium: "Balanced pace, reactions and decision making."
        case .hard: "Faster opponents who anticipate play and seek better passing lanes."
        }
    }
    var speedMultiplier: Double {
        switch self { case .easy: 0.82; case .medium: 1; case .hard: 1.16 }
    }
    var decisionInterval: Double {
        switch self { case .easy: 1.55; case .medium: 1; case .hard: 0.55 }
    }
    var anticipation: Double {
        switch self { case .easy: 0.06; case .medium: 0.16; case .hard: 0.34 }
    }
    var kickError: Double {
        switch self { case .easy: 0.09; case .medium: 0; case .hard: 0 }
    }
}
