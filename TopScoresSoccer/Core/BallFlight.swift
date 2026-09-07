import Foundation

/// Vertical motion is separate from the ground-plane ball simulation. Height is
/// the ball's bottom above the grass; zero is an ordinary rolling ball.
enum BallFlight {
    static func chip(_ ball: inout BallState, liftSpeed: Double = 8) {
        guard liftSpeed.isFinite, liftSpeed > 0, ball.height <= 0.05 else { return }
        ball.verticalVelocity = liftSpeed
    }

    static func height(after dt: Double, ball: BallState, gravity: Double = 18,
                       bounceRestitution: Double = 0.32) -> Double {
        flight(after: dt, height: ball.height, velocity: ball.verticalVelocity,
               gravity: gravity, restitution: bounceRestitution).height
    }

    static func advance(_ ball: inout BallState, dt: Double, gravity: Double = 18,
                        bounceRestitution: Double = 0.32) {
        let result = flight(after: dt, height: ball.height, velocity: ball.verticalVelocity,
                            gravity: gravity, restitution: bounceRestitution)
        ball.height = result.height
        ball.verticalVelocity = result.velocity
        // Turf absorbs some horizontal energy on each landing. Flight itself
        // does not add horizontal power or apply ground rolling resistance.
        ball.velocity *= pow(0.86, Double(result.impacts))
    }

    private static func flight(after dt: Double, height: Double, velocity: Double,
                               gravity: Double, restitution: Double)
        -> (height: Double, velocity: Double, impacts: Int) {
        guard dt.isFinite, dt > 0 else { return (height, velocity, 0) }
        guard height.isFinite, velocity.isFinite, gravity.isFinite else { return (0, 0, 0) }
        let gravity = max(0.01, gravity)
        let bounce = restitution.isFinite ? min(0.8, max(0, restitution)) : 0
        var remaining = dt
        var h = max(0, height)
        var v = velocity
        var impacts = 0
        for _ in 0..<12 {
            if h <= 0, v <= 0 { return (0, 0, impacts) }
            let landingTime = (v + sqrt(v * v + 2 * gravity * h)) / gravity
            if remaining < landingTime {
                return (max(0, h + v * remaining - 0.5 * gravity * remaining * remaining),
                        v - gravity * remaining, impacts)
            }
            remaining -= landingTime
            let impactSpeed = max(0, gravity * landingTime - v)
            impacts += 1
            h = 0
            v = impactSpeed * bounce
            if v < 0.75 { return (0, 0, impacts) }
            if remaining <= 0 { return (0, v, impacts) }
        }
        return (0, 0, impacts)
    }
}
