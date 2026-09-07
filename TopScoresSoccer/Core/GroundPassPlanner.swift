import Foundation

/// Launch conditions for a rolling pass. The plan never changes the ball after release.
enum GroundPassPlanner {
    struct Plan: Sendable {
        let destination: Vector2
        let launchSpeed: Double
        let flightTime: Double
        let isReachable: Bool
    }

    struct Motion: Sendable {
        let position: Vector2
        let velocity: Vector2
    }

    /// A constant requested velocity includes acceleration from the receiver's old run.
    /// Nil keeps an autonomous player's current run; zero predicts neutral braking.
    static func motion(after time: Double, receiver: PlayerState, requestedVelocity: Vector2?,
                       acceleration: Double, deceleration: Double) -> Motion {
        let time = max(0, time)
        guard let requestedVelocity else {
            return boundedMotion(position: receiver.position + receiver.velocity * time, velocity: receiver.velocity)
        }
        let change = requestedVelocity - receiver.velocity
        let rate = max(0.001, requestedVelocity.length > 0.0001 ? acceleration : deceleration)
        let transition = change.length / rate
        let accelerating = min(time, transition)
        let fraction = transition > 0.000001 ? accelerating / transition : 1
        let velocity = receiver.velocity + change * fraction
        var position = receiver.position + receiver.velocity * accelerating
            + change * (accelerating * fraction * 0.5)
        if time > transition { position += requestedVelocity * (time - transition) }
        return boundedMotion(position: position, velocity: velocity)
    }

    static func plan(origin: Vector2, receiver: PlayerState, requestedVelocity: Vector2?,
                     acceleration: Double, deceleration: Double, minimumSpeed: Double,
                     arrivalSpeed: Double, friction: Double, maximumSpeed: Double = 44) -> Plan {
        let friction = max(0, friction)
        let minimumSpeed = max(1, minimumSpeed)
        let arrivalSpeed = max(1, arrivalSpeed)
        let maximumSpeed = max(minimumSpeed, maximumSpeed)
        func candidate(at time: Double) -> (Motion, Double, Double) {
            let motion = motion(after: time, receiver: receiver, requestedVelocity: requestedVelocity,
                                acceleration: acceleration, deceleration: deceleration)
            let offset = motion.position - origin
            let launch = offset.length / time + 0.5 * friction * time
            let relativeArrival = launch - friction * time - motion.velocity.dot(offset.normalized)
            return (motion, launch, relativeArrival)
        }

        // Find the slowest useful delivery: it must still reach the moving contact point with
        // enough closing pace to control, and short passes retain their responsive minimum pace.
        var lower = 0.025
        var upper = 3.5
        for _ in 0..<20 {
            let middle = (lower + upper) * 0.5
            let (_, speed, relativeArrival) = candidate(at: middle)
            if speed >= minimumSpeed && relativeArrival >= arrivalSpeed
                && speed - friction * middle >= min(4, arrivalSpeed) { lower = middle }
            else { upper = middle }
        }
        var time = lower
        var (contact, speed, _) = candidate(at: time)
        var reachable = true
        if speed > maximumSpeed {
            // An exceptional distant/fast run may exceed useful ground-pass power. Keep the
            // physical limit and seek a reachable point instead of claiming a guaranteed pass.
            speed = maximumSpeed
            let stopTime = friction > 0.001 ? speed / friction : 5.0
            var previousTime = 0.025
            var found = false
            for index in 1...100 {
                let trial = min(5, stopTime) * Double(index) / 100
                let projected = motion(after: trial, receiver: receiver, requestedVelocity: requestedVelocity,
                                       acceleration: acceleration, deceleration: deceleration)
                let travel = speed * trial - 0.5 * friction * trial * trial
                if (projected.position - origin).length <= travel {
                    var start = previousTime
                    var end = trial
                    for _ in 0..<16 {
                        let midpoint = (start + end) * 0.5
                        let state = motion(after: midpoint, receiver: receiver, requestedVelocity: requestedVelocity,
                                           acceleration: acceleration, deceleration: deceleration)
                        if (state.position - origin).length <= speed * midpoint - 0.5 * friction * midpoint * midpoint {
                            end = midpoint
                        } else { start = midpoint }
                    }
                    time = end
                    contact = motion(after: time, receiver: receiver, requestedVelocity: requestedVelocity,
                                     acceleration: acceleration, deceleration: deceleration)
                    found = true
                    break
                }
                previousTime = trial
            }
            if !found {
                reachable = false
                time = min(3.5, stopTime)
                contact = motion(after: time, receiver: receiver, requestedVelocity: requestedVelocity,
                                 acceleration: acceleration, deceleration: deceleration)
            }
        }
        return Plan(destination: contact.position, launchSpeed: speed, flightTime: time, isReachable: reachable)
    }

    private static func boundedMotion(position: Vector2, velocity: Vector2) -> Motion {
        let xLimit = Pitch.width / 2 - Pitch.playerRadius
        let yLimit = Pitch.length / 2 - Pitch.playerRadius
        let bounded = Vector2(x: min(xLimit, max(-xLimit, position.x)),
                              y: min(yLimit, max(-yLimit, position.y)))
        var effectiveVelocity = velocity
        // The simulation preserves stored velocity against a boundary, but the player cannot
        // move farther outward. Closing pace must use actual positional movement there.
        if abs(position.x) >= xLimit && position.x * velocity.x > 0 { effectiveVelocity.x = 0 }
        if abs(position.y) >= yLimit && position.y * velocity.y > 0 { effectiveVelocity.y = 0 }
        return Motion(position: bounded, velocity: effectiveVelocity)
    }
}
