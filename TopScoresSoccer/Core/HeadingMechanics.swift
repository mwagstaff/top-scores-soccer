import Foundation

/// Aerial contact competes with feet, keepers and boundaries on the same timeline.
/// Height is the bottom of the ball, as in BallFlight; a jump never moves the ball to a player.
enum HeadingMechanics {
    static let minimumHeight = 0.85
    static let maximumHeight = 2.65
    static let reach = 1.7
    static let prepareWindow = 0.5
    static let animationDuration = 0.35

    static func contactFraction(ball: BallState, relativeOffset: Vector2, relativeTravel: Vector2,
                                duration: Double, gravity: Double) -> Double? {
        guard duration.isFinite, duration > 0, gravity.isFinite, gravity > 0,
              ball.height.isFinite, ball.verticalVelocity.isFinite,
              relativeOffset.lengthSquared.isFinite, relativeTravel.lengthSquared.isFinite else { return nil }
        let a = relativeTravel.lengthSquared
        let c = relativeOffset.lengthSquared - reach * reach
        let entry: Double
        let exit: Double
        if a < 0.00000001 {
            guard c <= 0 else { return nil }
            entry = 0; exit = 1
        } else {
            let b = 2 * relativeOffset.dot(relativeTravel)
            let discriminant = b * b - 4 * a * c
            guard discriminant >= 0 else { return nil }
            entry = max(0, (-b - sqrt(discriminant)) / (2 * a))
            exit = min(1, (-b + sqrt(discriminant)) / (2 * a))
            guard entry <= exit else { return nil }
        }
        var flight = ball
        let begin = entry * duration
        BallFlight.advance(&flight, dt: begin, gravity: gravity)
        var elapsed = begin
        let end = exit * duration
        for _ in 0..<6 {
            if flight.height >= minimumHeight - 0.000001,
               flight.height <= maximumHeight + 0.000001 { return elapsed / duration }
            let available = end - elapsed
            guard available > 0.00000001 else { return nil }
            let landing = (flight.verticalVelocity + sqrt(flight.verticalVelocity * flight.verticalVelocity
                + 2 * gravity * max(0, flight.height))) / gravity
            let horizon = min(available, landing)
            var crossing: Double?
            for level in [minimumHeight, maximumHeight] {
                let discriminant = flight.verticalVelocity * flight.verticalVelocity
                    + 2 * gravity * (flight.height - level)
                guard discriminant >= 0 else { continue }
                for time in [(flight.verticalVelocity - sqrt(discriminant)) / gravity,
                             (flight.verticalVelocity + sqrt(discriminant)) / gravity]
                    where time >= 0 && time <= horizon + 0.00000001 {
                    crossing = min(crossing ?? .infinity, time)
                }
            }
            if let crossing { return min(exit, (elapsed + crossing) / duration) }
            guard landing > 0.00000001, landing < available else { return nil }
            BallFlight.advance(&flight, dt: landing, gravity: gravity)
            elapsed += landing
        }
        return nil
    }
}
