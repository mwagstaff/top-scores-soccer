import Foundation

/// Brief launch-window assistance supplies one small direction correction, never
/// extra pace, a new recipient, or a route around a defender.
enum EarlyPassAdjustment {
    static let window = 0.12
    static let maximumAngle = 6.0 * Double.pi / 180

    struct State {
        let receiverID: Int
        let originalDirection: Vector2
        let launchMovement: Vector2
        var remaining = EarlyPassAdjustment.window
    }

    struct Opponent {
        let position: Vector2
        let maximumSpeed: Double
        let reach: Double
    }

    enum Decision {
        case wait
        case veto
        case correction(velocity: Vector2, angle: Double)
    }

    static func evaluate(ball: BallState, receiver: PlayerState, movement: Vector2,
                         launchMovement: Vector2, originalDirection: Vector2,
                         receiverSpeed: Double, acceleration: Double, deceleration: Double,
                         friction: Double, opponents: [Opponent]) -> Decision {
        let speed = ball.velocity.length
        guard speed > 2, ball.height <= 0.001, ball.verticalVelocity <= 0,
              ball.velocity.normalized.dot(originalDirection) > 0.99999 else { return .veto }
        let requested = movement.clampedLength(1) * receiverSpeed
        guard let (target, contactTime) = contact(ball: ball, receiver: receiver,
            requested: requested, acceleration: acceleration, deceleration: deceleration,
            friction: friction) else { return .veto }
        let distance = (target - ball.position).length
        // Close the window even before a new command if the original route already offers
        // an opponent a reachable interception. Later movement cannot reopen that chance.
        if threatened(origin: ball.position, direction: originalDirection, distance: distance,
                      speed: speed, friction: friction, duration: contactTime, opponents: opponents) { return .veto }
        guard movement.length >= 0.08, (movement - launchMovement).length > 0.12 else { return .wait }
        guard movement.dot(originalDirection) > -0.7 else { return .veto }
        let desired = (target - ball.position).normalized
        let angle = atan2(originalDirection.x * desired.y - originalDirection.y * desired.x,
                          originalDirection.dot(desired))
        let bounded = min(maximumAngle, max(-maximumAngle, angle))
        let corrected = originalDirection.rotated(by: bounded)
        if threatened(origin: ball.position, direction: corrected, distance: distance,
                      speed: speed, friction: friction, duration: contactTime, opponents: opponents) { return .veto }
        return .correction(velocity: corrected * speed, angle: bounded)
    }

    private static func contact(ball: BallState, receiver: PlayerState, requested: Vector2,
                                acceleration: Double, deceleration: Double,
                                friction: Double) -> (Vector2, Double)? {
        let friction = max(0, friction)
        let speed = ball.velocity.length
        let limit = min(4, friction > 0.001 ? speed / friction : 4)
        var previous = 0.0
        func projected(_ time: Double) -> Vector2 {
            GroundPassPlanner.motion(after: time, receiver: receiver, requestedVelocity: requested,
                                     acceleration: acceleration, deceleration: deceleration).position
        }
        func travel(_ time: Double) -> Double { speed * time - 0.5 * friction * time * time }
        for index in 1...64 {
            let time = limit * Double(index) / 64
            if (projected(time) - ball.position).length <= travel(time) {
                var lower = previous
                var upper = time
                for _ in 0..<16 {
                    let middle = (lower + upper) * 0.5
                    if (projected(middle) - ball.position).length <= travel(middle) { upper = middle }
                    else { lower = middle }
                }
                return (projected(upper), upper)
            }
            previous = time
        }
        return nil
    }

    private static func threatened(origin: Vector2, direction: Vector2, distance: Double,
                                   speed: Double, friction: Double, duration: Double,
                                   opponents: [Opponent]) -> Bool {
        let friction = max(0, friction)
        for opponent in opponents {
            let along = min(distance, max(0, (opponent.position - origin).dot(direction)))
            let point = origin + direction * along
            let time = friction > 0.001
                ? (speed - sqrt(max(0, speed * speed - 2 * friction * along))) / friction
                : along / max(0.001, speed)
            // A defender need not already stand on the ray: include every position they can
            // physically reach before the ball arrives, plus contact and a small time-step margin.
            let reachable = max(0, opponent.maximumSpeed) * min(duration, max(0, time))
                + max(Pitch.playerRadius + Pitch.ballRadius, opponent.reach) + 0.25
            if (opponent.position - point).length <= reachable { return true }
        }
        return false
    }
}
