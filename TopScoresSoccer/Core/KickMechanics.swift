import Foundation

/// Initial kick conditions only. Interceptions, posts, aftertouch and gravity remain
/// physical simulation events; no flight is steered or guaranteed to become a goal.
enum KickMechanics {
    struct Shot: Equatable, Sendable {
        let direction: Vector2
        let speed: Double
        let verticalVelocity: Double
        let isOverhit: Bool
    }

    struct Flight: Equatable, Sendable {
        let speed: Double
        let verticalVelocity: Double
        /// The bottom of the ball above the turf, matching BallFlight's convention.
        let height: Double
    }

    private static func bounded(_ value: Double, fallback: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value.isFinite ? value : fallback))
    }

    private static func timing(_ tuning: GameplayTuning) -> (threshold: Double, charge: Double) {
        (bounded(tuning.holdThreshold, fallback: 0.26, minimum: 0.05, maximum: 1),
         bounded(tuning.fullChargeDuration, fallback: 0.65, minimum: 0.15, maximum: 3))
    }

    private static func duration(_ heldFor: Double) -> Double {
        heldFor.isFinite ? max(0, heldFor) : 0
    }

    private static func charge(_ heldFor: Double, tuning: GameplayTuning) -> Double {
        let time = timing(tuning)
        return min(1, max(0, (duration(heldFor) - time.threshold) / time.charge))
    }

    /// The full meter includes both the controlled-power window and the overhold region.
    static func shotMeterFraction(heldFor: Double, tuning: GameplayTuning) -> Double {
        let time = timing(tuning)
        return min(1, max(0, (duration(heldFor) - time.threshold) / (time.charge * 1.6)))
    }

    /// Normalized meter fractions, suitable for drawing a green band on the shot meter.
    static func shotSweetSpot(tuning: GameplayTuning) -> ClosedRange<Double> {
        let times = shotSweetSpotDurations(tuning: tuning)
        let lower = shotMeterFraction(heldFor: times.lowerBound, tuning: tuning)
        let upper = shotMeterFraction(heldFor: times.upperBound, tuning: tuning)
        return lower...upper
    }

    /// Defaults to approximately 0.60–0.90 seconds of total ACTION hold time.
    static func shotSweetSpotDurations(tuning: GameplayTuning) -> ClosedRange<Double> {
        let time = timing(tuning)
        return (time.threshold + time.charge * 0.52)...(time.threshold + time.charge * 0.985)
    }

    /// Normalized start of the red meter region; uses the same timing as isOverhit.
    static func shotOverhitStart(tuning: GameplayTuning) -> Double {
        let time = timing(tuning)
        return shotMeterFraction(heldFor: time.threshold + time.charge * 1.22, tuning: tuning)
    }

    static func isOverhit(heldFor: Double, tuning: GameplayTuning) -> Bool {
        let time = timing(tuning)
        return heldFor.isFinite && heldFor > time.threshold + time.charge * 1.22
    }

    private static func overhold(_ heldFor: Double, tuning: GameplayTuning) -> Double {
        let time = timing(tuning)
        return min(1, max(0, (duration(heldFor) - time.threshold - time.charge * 1.22) / (time.charge * 0.38)))
    }

    static func shot(origin: Vector2, aim: Vector2, team: Team, heldFor: Double,
                     tuning: GameplayTuning, ends: MatchEnds = MatchEnds()) -> Shot? {
        guard origin.x.isFinite, origin.y.isFinite, aim.x.isFinite, aim.y.isFinite,
              heldFor.isFinite, heldFor >= 0,
              abs(origin.x) <= Pitch.width / 2 + Pitch.ballRadius,
              abs(origin.y) <= Pitch.length / 2 + Pitch.ballRadius else { return nil }
        let length = hypot(aim.x, aim.y)
        guard length.isFinite, length > 0.000001 else { return nil }
        let requested = aim / length
        let attack = ends.attackSign(for: team)
        let goalY = Pitch.length / 2 * attack
        let toGoal = Vector2(x: -origin.x, y: goalY - origin.y)
        let goalDistance = toGoal.length
        let range = bounded(tuning.shotAssistRange, fallback: 140, minimum: 1, maximum: 200)
        let angle = bounded(tuning.shotAssistAngle, fallback: 50, minimum: 1, maximum: 85)
        guard toGoal.y * attack > 0, goalDistance <= range,
              requested.dot(toGoal.normalized) + 0.0000001 >= cos(angle * .pi / 180) else { return nil }

        // Keep the requested goal-line intercept, including left/right corner intent.
        // Rough aim outside the mouth is brought just inside the posts. Using the full-ball
        // crossing plane keeps the same clearance convention as match goal adjudication.
        let crossingY = goalY + Pitch.ballRadius * attack
        let forwardDistance = (crossingY - origin.y) * attack
        let rayX = origin.x + requested.x * forwardDistance / max(0.001, requested.y * attack)
        let cornerLimit = Pitch.goalWidth / 2 - Pitch.postRadius - Pitch.ballRadius - 0.22
        let target = Vector2(x: min(cornerLimit, max(-cornerLimit, rayX)), y: crossingY)
        let offset = target - origin
        let direction = offset.normalized
        let power = charge(heldFor, tuning: tuning)
        let minimumSpeed = bounded(tuning.shotMinSpeed, fallback: 25, minimum: 1, maximum: 100)
        let maximumSpeed = bounded(tuning.shotMaxSpeed, fallback: 47, minimum: minimumSpeed, maximum: 120)
        let speed = minimumSpeed + (maximumSpeed - minimumSpeed) * power
        let excess = overhold(heldFor, tuning: tuning)
        let gravity = bounded(tuning.ballGravity, fallback: 18, minimum: 0.1, maximum: 80)
        let lift: Double
        if power <= 0 {
            lift = 0
        } else if goalDistance <= 30 {
            // A controlled shot rises toward a useful height at the goal. Holding too long
            // raises that target above the bar; it never changes scoring directly.
            let clearHeight = Pitch.crossbarHeight - Pitch.ballRadius * 2
            let controlledHeight = 0.15 + (clearHeight - 0.36) * min(1, power / 0.985)
            let targetHeight = controlledHeight + excess * 2
            let flightTime = max(0.02, offset.length / speed)
            lift = min(32, max(0, targetHeight / flightTime + 0.5 * gravity * flightTime))
        } else {
            // Longer attempts use bounded ordinary loft, without solving a distant goal arrival.
            lift = 2 + 5 * power + 5 * excess
        }
        return Shot(direction: direction, speed: speed, verticalVelocity: lift,
                    isOverhit: isOverhit(heldFor: heldFor, tuning: tuning))
    }

    /// Held open-play clearances lift immediately, then gain both height and distance.
    /// At default gravity, a 0.4s hold lands around 27m away; full power lands around 59m.
    /// Full charge remains a useful clearance even when held longer, without a shot's overhit band.
    static func longKick(heldFor: Double, tuning: GameplayTuning) -> Flight {
        let power = charge(heldFor, tuning: tuning)
        let minimumSpeed = bounded(tuning.shotMinSpeed, fallback: 25, minimum: 10, maximum: 40)
        let maximumSpeed = bounded(tuning.shotMaxSpeed, fallback: 47, minimum: minimumSpeed, maximum: 65)
        let speed = (minimumSpeed + (maximumSpeed - minimumSpeed) * power) * 0.9
        return Flight(speed: speed, verticalVelocity: 8 + 4.5 * power, height: 0)
    }

    /// A tap makes a short throw; longer holds add range, with no overhit classification.
    static func throwIn(heldFor: Double, tuning: GameplayTuning) -> Flight {
        let power = charge(heldFor, tuning: tuning)
        return Flight(speed: 14 + 13 * power, verticalVelocity: 3.2 + 3.8 * power, height: 1.65)
    }

    /// A held release is always a high overarm throw from the hands, never a punt.
    /// Targeted taps are solved by KeeperDeliveryPlanner; this is the untargeted range profile.
    static func keeperDistribution(heldFor: Double, tuning: GameplayTuning) -> Flight {
        let held = duration(heldFor)
        if held < timing(tuning).threshold {
            return Flight(speed: 21, verticalVelocity: 6, height: 1.8)
        }
        let power = charge(held, tuning: tuning)
        return Flight(speed: 26 + 8 * power, verticalVelocity: 12 + 5 * power, height: 1.8)
    }
}
