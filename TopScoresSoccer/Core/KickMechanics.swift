import Foundation

/// Initial kick conditions only. Interceptions, posts, aftertouch and gravity remain
/// physical simulation events; no flight is steered or guaranteed to become a goal.
enum KickMechanics {
    /// The visible band and the actual launch share this distance-dependent profile.
    struct ShotPower: Equatable, Sendable {
        let fraction: Double
        let sweetSpot: ClosedRange<Double>
        let overhitStart: Double
        var isOverhit: Bool { fraction > overhitStart }
    }

    static func distancePower(distance: Double, heldFor: Double, tuning: GameplayTuning) -> ShotPower {
        let distance = bounded(distance, fallback: 20, minimum: 0, maximum: 120)
        let duration = bounded(tuning.shotChargeDuration, fallback: 0.95, minimum: 0.2, maximum: 3)
        let fraction = bounded(heldFor, fallback: 0, minimum: 0, maximum: 10) / duration
        let range = bounded(tuning.shootingRange, fallback: 35, minimum: 20, maximum: 50)
        let reach = min(1, distance / range)
        // A useful finish is a firm strike even from close range. Distance asks for more
        // power and tighter timing, while still leaving a little safety before the overhit
        // region. This profile drives both the visible meter and the physical launch.
        let centre = 0.56 + 0.27 * pow(reach, 0.85)
        let halfWidth = 0.14 - 0.07 * reach
        let band = max(0, centre - halfWidth)...min(0.9, centre + halfWidth)
        return ShotPower(fraction: min(1, fraction), sweetSpot: band,
                         overhitStart: min(0.97, band.upperBound + 0.08))
    }

    /// A dedicated shot always aims at the opposition goal. Power affects pace,
    /// elevation and reproducible execution spread, never the scoring rules.
    static func chargedShot(origin: Vector2, aim: Vector2, facing: Vector2, team: Team,
                            heldFor: Double, tuning: GameplayTuning, ends: MatchEnds,
                            sequence: Int) -> Shot? {
        guard origin.x.isFinite, origin.y.isFinite, aim.x.isFinite, aim.y.isFinite,
              heldFor.isFinite, heldFor >= 0 else { return nil }
        let attack = ends.attackSign(for: team)
        let goal = Vector2(x: 0, y: Pitch.length / 2 * attack)
        let offset = goal - origin
        let distance = offset.length
        let profile = distancePower(distance: distance, heldFor: heldFor, tuning: tuning)
        let power = profile.fraction
        let goalward = offset.normalized
        let requested = aim.length > 0.001 && aim.normalized.dot(goalward) > 0.25 ? aim.normalized : goalward
        let crossingY = goal.y + Pitch.ballRadius * attack
        let cornerLimit = Pitch.goalWidth / 2 - Pitch.postRadius - Pitch.ballRadius - 0.22
        let rayX = origin.x + requested.x * max(0, (crossingY - origin.y) * attack)
            / max(0.05, requested.y * attack)
        let target = Vector2(x: min(cornerLimit, max(-cornerLimit, rayX)), y: crossingY)
        let speed = 12 + (bounded(tuning.shotMaxSpeed, fallback: 47, minimum: 25, maximum: 65) - 12) * power
        let excess = max(0, power - profile.overhitStart) / max(0.03, 1 - profile.overhitStart)
        let needed = (profile.sweetSpot.lowerBound + profile.sweetSpot.upperBound) / 2
        let referenceSpeed = 12 + (bounded(tuning.shotMaxSpeed, fallback: 47, minimum: 25, maximum: 65) - 12) * max(power, needed)
        let flightTime = max(0.04, (target - origin).length / referenceSpeed)
        let height = 0.12 + 1.20 * power + 3.8 * pow(excess, 1.25)
        let gravity = bounded(tuning.ballGravity, fallback: 18, minimum: 0.1, maximum: 80)
        let lift = power < 0.08 ? 0 : min(28, height / flightTime + 0.5 * gravity * flightTime)
        let awkward = (1 - facing.normalized.dot(goalward)) * 0.5
        // Distance and poor timing widen the real launch angle. A well-powered shot is
        // therefore the cleanest strike; raw power is not itself an accuracy penalty until
        // the player enters the overhit region.
        let shootingRange = bounded(tuning.shootingRange, fallback: 35, minimum: 20, maximum: 50)
        let distanceSpread = pow(min(1.35, distance / shootingRange), 1.7) * 0.020
        let underPower = max(0, profile.sweetSpot.lowerBound - power)
            / max(0.1, profile.sweetSpot.lowerBound)
        let aboveBand = max(0, power - profile.sweetSpot.upperBound)
            / max(0.1, 1 - profile.sweetSpot.upperBound)
        let timingSpread = pow(underPower, 1.4) * 0.010 + pow(aboveBand, 1.3) * 0.022
        let spread = 0.0025 + distanceSpread + timingSpread + excess * 0.070 + awkward * 0.022
        let error = sin(Double(sequence + 1) * 2.399963229728653) * spread
        return Shot(direction: (target - origin).normalized.rotated(by: error), speed: speed,
                    verticalVelocity: lift, isOverhit: profile.isOverhit)
    }

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
