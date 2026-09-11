import Foundation

/// Aerial contact competes with feet, keepers and boundaries on the same timeline.
/// Height is the bottom of the ball, as in BallFlight; a jump never moves the ball to a player.
enum HeadingMechanics {
    static let minimumHeight = 0.85
    static let maximumHeight = 2.65
    static let reach = 1.7
    static let prepareWindow = 0.5
    static let animationDuration = 0.35

    struct AttackingHeader: Equatable, Sendable {
        let direction: Vector2
        let speed: Double
        let verticalVelocity: Double
        let quality: Double
        let timingQuality: Double
        let contactQuality: Double
    }

    /// Choose the squarest reachable contact during a short jump, rather than
    /// heading as soon as the edge of the reach circle brushes the ball. The
    /// simulation must still check intervening collisions before this contact.
    static func preferredContactDelay(ball: BallState, player: Footballer, window: Double,
                                      gravity: Double) -> Double? {
        guard window.isFinite, window > 0, window <= 2,
              gravity.isFinite, gravity > 0, ball.height.isFinite,
              ball.verticalVelocity.isFinite, ball.position.lengthSquared.isFinite,
              ball.velocity.lengthSquared.isFinite, player.state.position.lengthSquared.isFinite,
              player.state.velocity.lengthSquared.isFinite else { return nil }
        let relativeOffset = ball.position - player.state.position
        let relativeVelocity = ball.velocity - player.state.velocity
        guard let entry = contactFraction(ball: ball, relativeOffset: relativeOffset,
            relativeTravel: relativeVelocity * window, duration: window, gravity: gravity) else { return nil }
        var bestTime = entry * window
        var bestScore = Double.infinity
        let samples = max(1, Int(ceil(window * 120)))
        for index in 0...samples {
            let time = index == 0 ? bestTime : window * Double(index) / Double(samples)
            let offset = relativeOffset + relativeVelocity * time
            let height = BallFlight.height(after: time, ball: ball, gravity: gravity)
            guard offset.lengthSquared <= reach * reach + 0.000001,
                  height >= minimumHeight - 0.000001,
                  height <= maximumHeight + 0.000001 else { continue }
            let heightError = (height - 1.7) / 0.95
            let score = 0.65 * offset.lengthSquared / (reach * reach) + 0.35 * heightError * heightError
            if score < bestScore {
                bestTime = time
                bestScore = score
            }
        }
        return bestTime
    }

    /// Launch conditions for an actual aerial contact, never a goal outcome. `preparedFor`
    /// is time from pressing ACTION to contact; the jump is strongest after a short wind-up.
    /// `variation` is a caller-supplied, reproducible sample in -1...1, independent of rating.
    static func attackingHeader(ball: BallState, player: Footballer, preparedFor: Double,
                                tuning: GameplayTuning, ends: MatchEnds = MatchEnds(),
                                variation: Double = 0) -> AttackingHeader? {
        guard ball.position.x.isFinite, ball.position.y.isFinite,
              ball.velocity.lengthSquared.isFinite, ball.height.isFinite, ball.verticalVelocity.isFinite,
              player.state.position.x.isFinite, player.state.position.y.isFinite,
              preparedFor.isFinite, preparedFor >= 0, variation.isFinite,
              !player.isGoalkeeper, !player.isUnavailable,
              ball.height >= minimumHeight - 0.000001,
              ball.height <= maximumHeight + 0.000001,
              abs(ball.position.x) <= 20,
              abs(ball.position.y) <= Pitch.length / 2 + Pitch.ballRadius else { return nil }

        let offset = ball.position - player.state.position
        let contactDistance = offset.length
        guard contactDistance <= reach + 0.000001 else { return nil }
        let attack = ends.attackSign(for: player.team)
        let goalY = Pitch.length / 2 * attack
        let forwardDistance = (goalY - ball.position.y) * attack
        let goalDistance = Vector2(x: -ball.position.x, y: goalY - ball.position.y).length
        guard forwardDistance > 0, goalDistance <= 26 else { return nil }

        let timingQuality: Double
        if preparedFor < 0.08 {
            // Contact immediately after the press is a late, abbreviated jump.
            timingQuality = 0.6 + 0.4 * preparedFor / 0.08
        } else if preparedFor <= 0.15 {
            timingQuality = 1
        } else {
            timingQuality = max(0.12, 1 - (preparedFor - 0.15) / 0.35 * 0.88)
        }
        // A stretched header remains possible at the shared collision radius, but a
        // cross at forehead height and close to the body produces cleaner contact.
        let stretch = min(1, contactDistance / reach)
        let heightError = min(1, abs(ball.height - 1.7) / 0.95)
        let contactQuality = (1 - 0.28 * stretch * stretch) * (1 - 0.42 * heightError * heightError)
        let technique: Double
        if let clubPlayer = player.clubPlayer {
            let raw = clubPlayer.effectiveRating
            let rating = min(95, max(55, raw.isFinite ? raw : 78))
            let roleBonus = clubPlayer.role == "F" ? 0.12 : clubPlayer.role == "M" ? 0.035 : 0
            technique = min(1, 0.52 + (rating - 55) / 40 * 0.36 + roleBonus)
        } else {
            technique = 0.86
        }
        let rangeQuality = max(0.8, 1 - max(0, goalDistance - 12) * 0.012)
        let quality = timingQuality * contactQuality * technique * rangeQuality
        let sample = min(1, max(-1, variation))
        // Good strikers can place the ball away from the keeper. Poor timing/contact
        // widens the distribution enough to miss a post, even from a clean delivery.
        let targetSide = abs(ball.position.x) > 0.5 ? (ball.position.x > 0 ? -1.0 : 1.0)
            : (sample < 0 ? -1.0 : 1.0)
        let intendedX = targetSide * (1.5 + 0.9 * technique)
        let targetX = intendedX + sample * (0.25 + 6.8 * (1 - quality))
        let target = Vector2(x: targetX, y: goalY + Pitch.ballRadius * attack)
        let direction = (target - ball.position).normalized
        let speed = min(29, 16 + 9 * quality + min(2.2, ball.velocity.length * 0.08))

        // BallFlight has no airborne horizontal drag. Keep a controlled header in
        // flight to the goal plane, avoiding premature turf impacts/rolling friction.
        // Mishits naturally loop above the bar; none of this bypasses interceptions,
        // goalkeepers, posts, gravity, or the ordinary full-ball goal adjudication.
        let targetHeight = max(0.15, 0.35 + 3.8 * pow(1 - quality, 2)
            + sample * 0.8 * (1 - quality))
        let flightTime = max(0.04, (target - ball.position).length / speed)
        let gravity = tuning.ballGravity.isFinite ? min(80, max(0.1, tuning.ballGravity)) : 18
        let lift = min(16, max(-8, (targetHeight - ball.height) / flightTime + 0.5 * gravity * flightTime))
        return AttackingHeader(direction: direction, speed: speed, verticalVelocity: lift,
            quality: quality, timingQuality: timingQuality, contactQuality: contactQuality)
    }

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
