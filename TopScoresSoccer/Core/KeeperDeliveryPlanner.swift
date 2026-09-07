import Foundation

/// Delivery labels describe the actual launch, independently of pass/shot contact physics.
enum KeeperDistributionKind: String, Sendable {
    case underarmThrow = "underarm throw"
    case overarmThrow = "overarm throw"
    case highThrow = "high throw"
    case longThrow = "long throw"
    case groundGoalKick = "goal kick pass"
    case loftedGoalKick = "lofted goal kick"
    case longGoalKick = "long goal kick"
}

enum GoalkeeperReleaseKind: Sendable { case underarmThrow, overarmThrow, goalKick }

/// Solves launch conditions once. Gravity, headers, interception and receiving remain physical;
/// there is no steering toward the recipient after release.
enum KeeperDeliveryPlanner {
    struct Plan: Sendable {
        let kind: KeeperDistributionKind
        let destination: Vector2
        let direction: Vector2
        /// Actual horizontal speed, with distribution ability already accounted for.
        let speed: Double
        let verticalVelocity: Double
        let height: Double
        let flightTime: Double
        let isReachable: Bool
    }

    static func ability(_ abilities: ArcadePlayerAbilities) -> Double {
        min(1.15, max(0.82, (abilities.passPower + abilities.goalkeeping) / 2))
    }

    static func plan(origin: Vector2, receiver: PlayerState, requestedVelocity: Vector2?,
                     acceleration: Double, deceleration: Double, hands: Bool,
                     heldFor: Double, ability: Double, blockers: [Vector2], tuning: GameplayTuning,
                     forceHighArc: Bool = false) -> Plan {
        let power = min(1, max(0, (heldFor - tuning.holdThreshold) / max(0.001, tuning.fullChargeDuration)))
        let held = heldFor >= tuning.holdThreshold
        let quality = min(1.15, max(0.82, ability))
        let initialDistance = (receiver.position - origin).length
        let initialBlocked = isBlocked(origin: origin, destination: receiver.position, opponents: blockers)
        if !hands, !held, !initialBlocked {
            let ground = GroundPassPlanner.plan(origin: origin, receiver: receiver,
                requestedVelocity: requestedVelocity, acceleration: acceleration, deceleration: deceleration,
                minimumSpeed: tuning.passSpeed * quality, arrivalSpeed: tuning.passArrivalSpeed,
                friction: tuning.ballFriction, maximumSpeed: 44 * min(1, quality))
            // Recheck the actual led line: an initially open passing lane can lead into a defender.
            if !isBlocked(origin: origin, destination: ground.destination, opponents: blockers) {
                return Plan(kind: .groundGoalKick, destination: ground.destination,
                    direction: (ground.destination - origin).normalized, speed: ground.launchSpeed,
                    verticalVelocity: 0, height: 0, flightTime: ground.flightTime, isReachable: ground.isReachable)
            }
        }
        let kind: KeeperDistributionKind
        if held { kind = hands ? .longThrow : .longGoalKick }
        else if !hands { kind = .loftedGoalKick }
        else if initialBlocked || forceHighArc { kind = .highThrow }
        else {
            let closeMotion = GroundPassPlanner.motion(after: 0.5, receiver: receiver,
                requestedVelocity: requestedVelocity, acceleration: acceleration, deceleration: deceleration)
            kind = max(initialDistance, (closeMotion.position - origin).length) <= 9 ? .underarmThrow : .overarmThrow
        }
        let startHeight = !hands ? 0.0 : kind == .underarmThrow ? 0.65 : 1.8
        let gravity = max(0.01, tuning.ballGravity)
        let arrivalHeight = 0.20
        let awaySpeed = max(0, (requestedVelocity ?? receiver.velocity).dot((receiver.position - origin).normalized))
        let overarmSpeed = min(34, 24 + awaySpeed * 0.8) * quality
        let preferredSpeed: Double
        let minimumTime: Double
        let maximumLift: Double
        switch kind {
        case .underarmThrow:
            preferredSpeed = 14 * quality; minimumTime = 0.4; maximumLift = 7 * quality
        case .overarmThrow:
            preferredSpeed = overarmSpeed; minimumTime = 0.65; maximumLift = 17 * quality
        case .highThrow, .loftedGoalKick:
            preferredSpeed = overarmSpeed; minimumTime = 1.25; maximumLift = 18 * quality
        case .longThrow:
            preferredSpeed = (26 + 8 * power) * quality
            minimumTime = (1.5 + 0.45 * power) * quality
            maximumLift = (15 + 4 * power) * quality
        case .longGoalKick:
            preferredSpeed = (29 + 13 * power) * quality
            minimumTime = (1.45 + 0.45 * power) * quality
            maximumLift = (16 + 4 * power) * quality
        case .groundGoalKick:
            preconditionFailure("Ground delivery is solved above")
        }
        var best: Plan?
        // A 20ms search is bounded and cheap even when previewing a full lineup. The receiver
        // uses the same acceleration/braking model as ordinary coordinated passing.
        for sample in 0...150 {
            let time = minimumTime + Double(sample) * 0.02
            let motion = GroundPassPlanner.motion(after: time, receiver: receiver,
                requestedVelocity: requestedVelocity, acceleration: acceleration, deceleration: deceleration)
            let offset = motion.position - origin
            let speed = offset.length / time
            let lift = (arrivalHeight - startHeight) / time + 0.5 * gravity * time
            guard lift >= 0, lift <= maximumLift, speed <= preferredSpeed else { continue }
            let blocked = isBlocked(origin: origin, destination: motion.position, opponents: blockers)
            if kind == .underarmThrow || kind == .overarmThrow, blocked {
                // A led run can reveal a blocker absent from the original line. Rebuild the
                // whole high profile, including launch height and power bounds, exactly once.
                return plan(origin: origin, receiver: receiver, requestedVelocity: requestedVelocity,
                    acceleration: acceleration, deceleration: deceleration, hands: hands, heldFor: heldFor,
                    ability: ability, blockers: blockers, tuning: tuning, forceHighArc: true)
            }
            if blocked, kind == .highThrow || kind == .loftedGoalKick {
                guard clearsCentralBlockers(origin: origin, destination: motion.position,
                    height: startHeight, lift: lift, flightTime: time, gravity: gravity, opponents: blockers) else { continue }
            }
            best = Plan(kind: kind, destination: motion.position, direction: offset.normalized,
                speed: speed, verticalVelocity: lift, height: startHeight, flightTime: time, isReachable: true)
            break
        }
        if let best { return best }
        let fallbackTime = minimumTime
        let motion = GroundPassPlanner.motion(after: fallbackTime, receiver: receiver,
            requestedVelocity: requestedVelocity, acceleration: acceleration, deceleration: deceleration)
        return Plan(kind: kind, destination: motion.position, direction: (motion.position - origin).normalized,
            speed: preferredSpeed, verticalVelocity: min(maximumLift, max(1, gravity * fallbackTime / 2)),
            height: startHeight, flightTime: fallbackTime, isReachable: false)
    }

    static func space(origin: Vector2, aim: Vector2, hands: Bool, heldFor: Double,
                      ability: Double, tuning: GameplayTuning) -> Plan {
        let quality = min(1.15, max(0.82, ability))
        let held = heldFor >= tuning.holdThreshold
        let flight = hands ? KickMechanics.keeperDistribution(heldFor: heldFor, tuning: tuning)
            : held ? KickMechanics.longKick(heldFor: heldFor, tuning: tuning)
            : KickMechanics.Flight(speed: tuning.passSpeed, verticalVelocity: 0, height: 0)
        let speed = flight.speed * quality
        let lift = flight.verticalVelocity * quality
        let gravity = max(0.01, tuning.ballGravity)
        let time = lift > 0 || flight.height > 0
            ? (lift + sqrt(lift * lift + 2 * gravity * flight.height)) / gravity
            : speed / max(0.01, tuning.ballFriction)
        let distance = lift > 0 || flight.height > 0 ? speed * time : speed * time / 2
        return Plan(kind: hands ? (held ? .longThrow : .overarmThrow) : (held ? .longGoalKick : .groundGoalKick),
            destination: origin + aim.normalized * distance, direction: aim.normalized, speed: speed,
            verticalVelocity: lift, height: flight.height, flightTime: time, isReachable: true)
    }

    static func isBlocked(origin: Vector2, destination: Vector2, opponents: [Vector2]) -> Bool {
        let offset = destination - origin
        guard offset.length > 1 else { return false }
        return opponents.contains { opponent in
            let along = (opponent - origin).dot(offset.normalized)
            // A marker at the receiving end is never a promise to bypass the contest.
            return along > 2 && along < offset.length - 4.5
                && abs((opponent - origin).dot(offset.normalized.perpendicular)) < 2.8
        }
    }

    private static func clearsCentralBlockers(origin: Vector2, destination: Vector2, height: Double,
        lift: Double, flightTime: Double, gravity: Double, opponents: [Vector2]) -> Bool {
        let offset = destination - origin
        let distance = offset.length
        for opponent in opponents {
            let along = (opponent - origin).dot(offset.normalized)
            guard along > 2, along < distance - 4.5,
                  abs((opponent - origin).dot(offset.normalized.perpendicular)) < 2.8 else { continue }
            for edge in [-HeadingMechanics.reach, HeadingMechanics.reach] {
                let time = min(1, max(0, (along + edge) / max(0.01, distance))) * flightTime
                let clearance = height + lift * time - 0.5 * gravity * time * time
                if clearance < HeadingMechanics.maximumHeight + 0.25 { return false }
            }
        }
        return true
    }
}
