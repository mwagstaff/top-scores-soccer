import Foundation

/// Crosses choose a box runner at release, then obey ordinary ball flight. A poor release
/// changes the launch itself; receivers and scoring never receive a guaranteed contact.
enum CrossingMechanics {
    static let arrivalHeight = 1.75

    struct Opportunity: Equatable, Sendable {
        let receiverID: Int
        let destination: Vector2
        let flightTime: Double
        let positionQuality: Double
    }

    struct Plan: Equatable, Sendable {
        let receiverID: Int
        /// The intended runner's contact point; under/overhit balls can miss it completely.
        let destination: Vector2
        let direction: Vector2
        /// Ability and release power are already included. Do not apply rated kick power again.
        let speed: Double
        let verticalVelocity: Double
        let height: Double
        /// The actual descending arrival at heading height, not a promise to reach the runner.
        let flightTime: Double
        let positionQuality: Double
        let timingQuality: Double
        let accuracy: Double
        let isUnderhit: Bool
        let isOverhit: Bool
    }

    /// Wide attacking positions only. Early crosses and almost-byline deliveries remain
    /// possible, but the side of the penalty area gives the most forgiving release.
    static func positionalQuality(origin: Vector2, team: Team,
                                  ends: MatchEnds = MatchEnds()) -> Double? {
        guard finite(origin), abs(origin.x) >= 20, abs(origin.x) <= Pitch.width / 2,
              abs(origin.y) <= Pitch.length / 2 else { return nil }
        let depth = Pitch.length / 2 - origin.y * ends.attackSign(for: team)
        guard depth >= 3, depth <= 32 else { return nil }
        let depthPenalty = depth < 10 ? (10 - depth) / 7 : depth > 20 ? (depth - 20) / 12 : 0
        let widthPenalty = abs(origin.x) < 23 ? (23 - abs(origin.x)) / 3
            : abs(origin.x) > 31 ? (abs(origin.x) - 31) / 3 : 0
        return clamp(1 - depthPenalty * 0.52 - widthPenalty * 0.16, 0.25, 1)
    }

    /// Overall rating supplies the arcade skill estimate; midfielders and forwards gain
    /// a role advantage. Practice players retain a strong, consistent delivery.
    static func ability(_ crosser: Footballer) -> Double {
        guard let player = crosser.clubPlayer else { return 0.9 }
        let rating = player.effectiveRating.isFinite ? player.effectiveRating : 78
        let quality = (clamp(rating, 55, 95) - 55) / 40
        let roleBonus = player.role == "M" ? 0.12 : player.role == "F" ? 0.10 : 0
        return clamp(0.40 + quality * 0.48 + roleBonus, 0.4, 1)
    }

    static func opportunity(crosser: Footballer, roster: [Footballer], tuning: GameplayTuning,
                            ends: MatchEnds = MatchEnds(),
                            excludedReceiverIDs: Set<Int> = []) -> Opportunity? {
        guard available(crosser), let quality = positionalQuality(origin: crosser.state.position,
            team: crosser.team, ends: ends) else { return nil }
        let attack = ends.attackSign(for: crosser.team)
        var best: (opportunity: Opportunity, score: Double)?
        for receiver in roster where receiver.id != crosser.id && receiver.team == crosser.team
            && available(receiver) && !excludedReceiverIDs.contains(receiver.id) {
            let role = receiver.clubPlayer?.role
            let depth = Pitch.length / 2 - receiver.state.position.y * attack
            // Defenders can attack a cross if they have actually advanced; a deep outfielder
            // must run into the box before becoming a credible receiving option.
            guard depth >= 2, depth <= 29, abs(receiver.state.position.x) <= 25 else { continue }
            let led = receiver.state.position + receiver.state.velocity.clampedLength(11) * 0.35
            let targetDepth = clamp(Pitch.length / 2 - led.y * attack - 1.2, 6, 14)
            let target = Vector2(x: clamp(led.x, -13, 13),
                                 y: (Pitch.length / 2 - targetDepth) * attack)
            let distance = (target - crosser.state.position).length
            guard distance >= 9, distance <= 49 else { continue }
            let time = deliveryTime(distance: distance)
            guard canReach(receiver, destination: target, time: time, tuning: tuning) else { continue }
            let clearance = roster.filter { $0.team != crosser.team && !$0.isUnavailable }
                .map { ($0.state.position - target).length }.min() ?? 10
            let runDistance = (target - receiver.state.position).length
            let roleBonus = role == "F" ? 2.2 : role == "M" ? 0.8 : 0
            let score = roleBonus + min(6, clearance) * 0.55 - abs(target.x) * 0.12
                - abs(targetDepth - 10) * 0.18 - runDistance * 0.18
            if best == nil || score > best!.score {
                best = (Opportunity(receiverID: receiver.id, destination: target,
                    flightTime: time, positionQuality: quality), score)
            }
        }
        return best?.opportunity
    }

    static func plan(origin: Vector2, crosser: Footballer, roster: [Footballer], heldFor: Double,
                     tuning: GameplayTuning, ends: MatchEnds = MatchEnds(), sequence: Int = 0,
                     excludedReceiverIDs: Set<Int> = []) -> Plan? {
        guard finite(origin), abs(origin.x) <= Pitch.width / 2 + Pitch.ballRadius,
              abs(origin.y) <= Pitch.length / 2 + Pitch.ballRadius,
              heldFor.isFinite, heldFor >= holdThreshold(tuning),
              let opportunity = opportunity(crosser: crosser, roster: roster, tuning: tuning,
                  ends: ends, excludedReceiverIDs: excludedReceiverIDs) else { return nil }
        return flight(origin: origin, opportunity: opportunity, crosser: crosser,
                      heldFor: heldFor, tuning: tuning, sequence: sequence)
    }

    static func flight(origin: Vector2, opportunity: Opportunity, crosser: Footballer,
                       heldFor: Double, tuning: GameplayTuning, sequence: Int = 0) -> Plan {
        let offset = opportunity.destination - origin
        let time = deliveryTime(distance: offset.length)
        let power = normalizedCharge(heldFor: heldFor, tuning: tuning)
        let shortfall = clamp((0.52 - power) / 0.52, 0, 1)
        let excess = clamp((power - 0.985) / (1.6 - 0.985), 0, 1)
        let timingQuality = clamp(1 - max(shortfall, excess), 0, 1)
        let quality = ability(crosser)
        let accuracy = clamp(quality * (0.45 + 0.55 * opportunity.positionQuality)
            * (0.5 + 0.5 * timingQuality), 0, 1)
        // Every rating sees the same deterministic samples. Skill reduces their spread,
        // while releasing early/late or from a poor location remains costly at any rating.
        let phase = Double(sequence) * 2.399963229728653 + Double(crosser.id) * 0.754877666 + 0.7
        let angularSpread = 0.008 + (1 - quality) * 0.075
            + (1 - opportunity.positionQuality) * 0.12 + (1 - timingQuality) * 0.075
        let error = sin(phase) * angularSpread
        let rangeError = cos(phase * 1.37) * ((1 - quality) * 0.035
            + (1 - opportunity.positionQuality) * 0.055)
        let speed = offset.length / time * (1 - 0.58 * shortfall + 0.72 * excess) * (1 + rangeError)
        let gravity = bounded(tuning.ballGravity, fallback: 18, minimum: 0.1, maximum: 80)
        let lift = (arrivalHeight / time + gravity * time / 2)
            * (1 - 0.22 * shortfall + 0.12 * excess)
        let discriminant = max(0, lift * lift - 2 * gravity * arrivalHeight)
        let headingTime = (lift + sqrt(discriminant)) / gravity
        return Plan(receiverID: opportunity.receiverID, destination: opportunity.destination,
            direction: offset.normalized.rotated(by: error), speed: speed,
            verticalVelocity: lift, height: 0, flightTime: headingTime,
            positionQuality: opportunity.positionQuality, timingQuality: timingQuality,
            accuracy: accuracy, isUnderhit: power < 0.52,
            isOverhit: isOverhit(heldFor: heldFor, tuning: tuning))
    }

    /// Stage a small set of box runs while the winger carries/charges. The offside line
    /// is attack progress (as returned by OffsideRules.line), independent of physical end.
    static func supportTargets(crosser: Footballer, roster: [Footballer], offsideLine: Double?,
                               ends: MatchEnds = MatchEnds()) -> [Int: Vector2] {
        guard positionalQuality(origin: crosser.state.position, team: crosser.team, ends: ends) != nil else { return [:] }
        let attack = ends.attackSign(for: crosser.team)
        let side = crosser.state.position.x >= 0 ? 1.0 : -1.0
        let candidates = roster.filter { player in
            guard player.id != crosser.id, player.team == crosser.team, available(player) else { return false }
            let depth = Pitch.length / 2 - player.state.position.y * attack
            let role = player.clubPlayer?.role
            return depth >= 2 && depth <= 42 && (role == nil || role == "F" || role == "M" || depth <= 20)
        }.sorted {
            let lhs = supportPriority($0, attack: attack)
            let rhs = supportPriority($1, attack: attack)
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }.prefix(3)
        let slots = [(7 * side, 8.0), (0.0, 10.0), (-8 * side, 12.0)]
        var result: [Int: Vector2] = [:]
        for (index, player) in candidates.enumerated() {
            var progress = Pitch.length / 2 - slots[index].1
            if let line = offsideLine, line.isFinite { progress = min(progress, line - 1.2) }
            progress = clamp(progress, 0, Pitch.length / 2 - 4)
            result[player.id] = Vector2(x: slots[index].0, y: progress * attack)
        }
        return result
    }

    static func meterFraction(heldFor: Double, tuning: GameplayTuning) -> Double {
        normalizedCharge(heldFor: heldFor, tuning: tuning) / 1.6
    }

    static func sweetSpot(tuning: GameplayTuning) -> ClosedRange<Double> { (0.52 / 1.6)...(0.985 / 1.6) }

    static func sweetSpotDurations(tuning: GameplayTuning) -> ClosedRange<Double> {
        (holdThreshold(tuning) + chargeDuration(tuning) * 0.52)...(holdThreshold(tuning) + chargeDuration(tuning) * 0.985)
    }

    static func overhitStart(tuning: GameplayTuning) -> Double { 1.22 / 1.6 }

    static func isOverhit(heldFor: Double, tuning: GameplayTuning) -> Bool {
        heldFor.isFinite && heldFor > holdThreshold(tuning) + chargeDuration(tuning) * 1.22
    }

    private static func canReach(_ receiver: Footballer, destination: Vector2, time: Double,
                                 tuning: GameplayTuning) -> Bool {
        let run = destination - receiver.state.position
        guard run.length > HeadingMechanics.reach - 0.3 else { return true }
        let speedScale = receiver.team == .blue ? 1 : tuning.aiSpeedScale * tuning.difficulty.speedMultiplier
        let maximum = max(0, tuning.playerMaxSpeed * speedScale * tuning.offBallSpeedBoost
            * receiver.abilities.speed)
        let predicted = GroundPassPlanner.motion(after: time, receiver: receiver.state,
            requestedVelocity: run.normalized * maximum,
            acceleration: tuning.playerAcceleration * receiver.abilities.acceleration,
            deceleration: tuning.playerDeceleration)
        let projectedTravel = (predicted.position - receiver.state.position).dot(run.normalized)
        return run.length <= max(0, projectedTravel) + HeadingMechanics.reach - 0.3
    }

    private static func available(_ player: Footballer) -> Bool {
        !player.isUnavailable && !player.isGoalkeeper && !player.isTackling && !player.isSliding
            && player.fallProgress <= 0.001 && player.recoveryProgress <= 0.001
            && finite(player.state.position) && finite(player.state.velocity)
    }

    private static func supportPriority(_ player: Footballer, attack: Double) -> Double {
        let role = player.clubPlayer?.role
        return (role == "F" ? 12 : role == "M" ? 4 : 0) + player.state.position.y * attack * 0.3
    }

    private static func deliveryTime(distance: Double) -> Double { clamp(distance / 25, 0.95, 1.95) }
    private static func finite(_ vector: Vector2) -> Bool { vector.x.isFinite && vector.y.isFinite }
    private static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double { min(maximum, max(minimum, value)) }
    private static func bounded(_ value: Double, fallback: Double, minimum: Double, maximum: Double) -> Double {
        clamp(value.isFinite ? value : fallback, minimum, maximum)
    }
    private static func holdThreshold(_ tuning: GameplayTuning) -> Double {
        bounded(tuning.holdThreshold, fallback: 0.26, minimum: 0.05, maximum: 1)
    }
    private static func chargeDuration(_ tuning: GameplayTuning) -> Double {
        bounded(tuning.fullChargeDuration, fallback: 0.65, minimum: 0.15, maximum: 3)
    }
    private static func normalizedCharge(heldFor: Double, tuning: GameplayTuning) -> Double {
        guard heldFor.isFinite else { return 0 }
        return clamp((heldFor - holdThreshold(tuning)) / chargeDuration(tuning), 0, 1.6)
    }
}
