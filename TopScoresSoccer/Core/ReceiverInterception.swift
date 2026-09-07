import Foundation

/// A neutral receiver runs to a future ball position he can reach in time. The ball's
/// path remains unchanged; contact and possession are still resolved by swept physics.
enum ReceiverInterception {
    struct Meeting {
        let position: Vector2
        let time: Double
    }

    static func meeting(ball: BallState, receiver: PlayerState, speed: Double,
                        acceleration: Double, deceleration: Double, reach: Double,
                        friction: Double, gravity: Double, maximumHeight: Double,
                        horizon: Double, maximumRelativeSpeed: Double? = nil) -> Meeting? {
        let interval = 1.0 / 30
        let horizon = max(0, horizon)
        var projectedBall = ball
        var time = 0.0
        while time <= horizon + 0.000001 {
            guard abs(projectedBall.position.x) <= Pitch.width / 2 + Pitch.ballRadius,
                  abs(projectedBall.position.y) <= Pitch.length / 2 + Pitch.ballRadius else { return nil }
            if projectedBall.height <= maximumHeight {
                let offset = projectedBall.position - receiver.position
                let direction = offset.normalized
                let motion = GroundPassPlanner.motion(after: time, receiver: receiver,
                    requestedVelocity: direction * max(0, speed), acceleration: acceleration,
                    deceleration: deceleration)
                let remaining = projectedBall.position - motion.position
                // Passing the target along the run means the receiver could arrive earlier
                // and wait; perpendicular momentum still has to fit the contact reach.
                let reachable = remaining.dot(direction) <= reach
                    && abs(remaining.dot(direction.perpendicular)) <= reach
                let controlledSpeed = maximumRelativeSpeed.map {
                    (projectedBall.velocity - motion.velocity).length <= $0
                } ?? true
                if reachable && controlledSpeed {
                    return Meeting(position: projectedBall.position, time: time)
                }
            }
            guard time < horizon else { break }
            let dt = min(interval, horizon - time)
            let rolling = projectedBall.height <= 0.001 && projectedBall.verticalVelocity <= 0
            let drag = rolling ? max(0, friction) : 0
            let ballSpeed = projectedBall.velocity.length
            let movingTime = drag > 0.001 ? min(dt, ballSpeed / drag) : dt
            let distance = max(0, ballSpeed * movingTime - 0.5 * drag * movingTime * movingTime)
            projectedBall.position += projectedBall.velocity.normalized * distance
            projectedBall.velocity = projectedBall.velocity.normalized * max(0, ballSpeed - drag * movingTime)
            BallFlight.advance(&projectedBall, dt: dt, gravity: gravity)
            time += dt
        }
        return nil
    }
}
