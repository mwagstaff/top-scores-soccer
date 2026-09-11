import XCTest
@testable import TopScoresSoccer

final class HeadingQualityTests: XCTestCase {
    private func player(rating: Double = 95, role: String = "ST", position: Vector2,
                        team: Team = .blue) -> Footballer {
        Footballer(id: 0, team: team, state: PlayerState(position: position),
            clubPlayer: ClubPlayer(id: "header", name: "Header", position: role,
                rating: rating, appearance: .generated(for: "header")))
    }

    private func ball(distance: Double = 12, height: Double = 1.7,
                      team: Team = .blue, ends: MatchEnds = MatchEnds()) -> BallState {
        BallState(position: Vector2(x: 0, y: (Pitch.length / 2 - distance) * ends.attackSign(for: team)),
            velocity: Vector2(x: 18, y: 0), mode: .pass, height: height, verticalVelocity: -3)
    }

    /// Exercise the shared flight physics through the actual full-ball goal plane.
    /// A successful trajectory can still be saved or intercepted in the match.
    private func arrival(_ result: HeadingMechanics.AttackingHeader, ball initial: BallState,
                         team: Team = .blue, ends: MatchEnds = MatchEnds(), gravity: Double = 18) -> BallState {
        var ball = initial
        ball.velocity = result.direction * result.speed
        ball.verticalVelocity = result.verticalVelocity
        let attack = ends.attackSign(for: team)
        let goalY = (Pitch.length / 2 + Pitch.ballRadius) * attack
        var remaining = (goalY - ball.position.y) / ball.velocity.y
        for _ in 0..<1200 where remaining > 0.00000001 {
            let step = min(1.0 / 240, remaining)
            ball.position += ball.velocity * step
            BallFlight.advance(&ball, dt: step, gravity: gravity)
            remaining -= step
        }
        return ball
    }

    private func isOnTarget(_ ball: BallState) -> Bool {
        abs(ball.position.x) + Pitch.ballRadius < Pitch.goalWidth / 2 - Pitch.postRadius
            && ball.height + Pitch.ballRadius * 2 < Pitch.crossbarHeight
    }

    func testPreferredContactLetsTheCrossReachForeheadInsteadOfBrushingOuterReach() throws {
        var incoming = ball(height: 2.5)
        incoming.position.x = -3
        let actor = player(position: Vector2(x: 0, y: incoming.position.y))
        let entry = try XCTUnwrap(HeadingMechanics.contactFraction(ball: incoming,
            relativeOffset: incoming.position - actor.state.position,
            relativeTravel: incoming.velocity * 0.2, duration: 0.2, gravity: 18)) * 0.2
        let preferred = try XCTUnwrap(HeadingMechanics.preferredContactDelay(ball: incoming,
            player: actor, window: 0.2, gravity: 18))
        XCTAssertGreaterThan(preferred, entry + 0.04)
        XCTAssertLessThan((incoming.position + incoming.velocity * preferred - actor.state.position).length, 0.4)
        let contactHeight = BallFlight.height(after: preferred, ball: incoming)
        XCTAssertGreaterThan(contactHeight, 1.5)
        XCTAssertLessThan(contactHeight, 1.95)
        var remote = actor
        remote.state.position.y += 10
        XCTAssertNil(HeadingMechanics.preferredContactDelay(ball: incoming, player: remote,
            window: 0.2, gravity: 18))
        XCTAssertNil(HeadingMechanics.preferredContactDelay(ball: incoming, player: actor,
            window: .infinity, gravity: 18))
    }

    func testPreparedJumpIsStrongerThanLatePressOrEarlyJump() throws {
        let incoming = ball()
        let actor = player(position: incoming.position)
        let sweet = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming, player: actor,
            preparedFor: 0.11, tuning: .defaults))
        for preparation in [0.0, 0.3, 0.5] {
            let mistimed = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming, player: actor,
                preparedFor: preparation, tuning: .defaults))
            XCTAssertGreaterThan(sweet.quality, mistimed.quality)
            XCTAssertGreaterThan(sweet.speed, mistimed.speed)
            XCTAssertLessThan(arrival(sweet, ball: incoming).height, arrival(mistimed, ball: incoming).height)
        }
        XCTAssertTrue(isOnTarget(arrival(sweet, ball: incoming)))
        let early = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming, player: actor,
            preparedFor: 0.5, tuning: .defaults))
        XCTAssertGreaterThan(arrival(early, ball: incoming).height + Pitch.ballRadius * 2,
                             Pitch.crossbarHeight)
    }

    func testCleanBodyContactBeatsStretchedHighAndLowContacts() throws {
        let incoming = ball()
        let clean = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming,
            player: player(position: incoming.position), preparedFor: 0.11, tuning: .defaults))
        for height in [0.88, 1.7, 2.6] {
            var awkward = incoming
            awkward.height = height
            let stretched = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: awkward,
                player: player(position: incoming.position + Vector2(x: 1.65, y: 0)),
                preparedFor: 0.11, tuning: .defaults))
            XCTAssertGreaterThan(clean.contactQuality, stretched.contactQuality)
            XCTAssertGreaterThan(clean.speed, stretched.speed)
        }
    }

    func testWellTimedHeadersPhysicallyReachGoalFromSixToTwentyFourMetres() throws {
        for distance in [6.0, 12, 18, 24] {
            for gravity in [9.0, 18, 28] {
                let incoming = ball(distance: distance)
                var tuning = GameplayTuning.defaults
                tuning.ballGravity = gravity
                let result = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming,
                    player: player(position: incoming.position), preparedFor: 0.11,
                    tuning: tuning, variation: 0.4))
                let atGoal = arrival(result, ball: incoming, gravity: gravity)
                XCTAssertEqual(atGoal.position.y, Pitch.length / 2 + Pitch.ballRadius, accuracy: 0.00001)
                XCTAssertGreaterThan(atGoal.height, 0.1)
                XCTAssertTrue(isOnTarget(atGoal), "distance=\(distance), gravity=\(gravity)")
                XCTAssertEqual(atGoal.velocity.length, result.speed, accuracy: 0.00001,
                               "A clean header should reach goal before losing energy on the turf")
            }
        }
    }

    func testRatingAndStrikerRoleImproveOnTargetFrequencyUnderTheSameContactSamples() throws {
        let incoming = ball(distance: 16)
        let position = incoming.position + Vector2(x: 1.5, y: 0)
        var counts: [Int] = []
        var meanSpeeds: [Double] = []
        for actor in [player(rating: 55, position: position), player(rating: 95, role: "D", position: position),
                      player(rating: 95, position: position)] {
            var onTarget = 0
            var speeds = 0.0
            for index in 0...100 {
                let sample = Double(index) / 50 - 1
                let result = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming, player: actor,
                    preparedFor: 0.11, tuning: .defaults, variation: sample))
                if isOnTarget(arrival(result, ball: incoming)) { onTarget += 1 }
                speeds += result.speed
            }
            counts.append(onTarget)
            meanSpeeds.append(speeds / 101)
        }
        XCTAssertGreaterThan(counts[2], counts[0] + 15)
        XCTAssertGreaterThan(counts[2], counts[1])
        XCTAssertLessThan(counts[2], 101, "Even an elite striker can miss a stretched header")
        XCTAssertGreaterThan(meanSpeeds[2], meanSpeeds[0])
        XCTAssertGreaterThan(meanSpeeds[2], meanSpeeds[1])
    }

    func testAutomaticGoalDirectionFollowsEitherTeamAfterEndsChange() throws {
        for ends in [MatchEnds(), MatchEnds(blueAttacksNorth: false)] {
            for team in [Team.blue, .red] {
                let incoming = ball(team: team, ends: ends)
                let actor = player(position: incoming.position, team: team)
                let result = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming, player: actor,
                    preparedFor: 0.11, tuning: .defaults, ends: ends))
                XCTAssertGreaterThan(result.direction.y * ends.attackSign(for: team), 0)
                XCTAssertTrue(isOnTarget(arrival(result, ball: incoming, team: team, ends: ends)))
            }
        }
    }

    func testDistantOrUnreachableBallsCannotGenerateAnAttackingHeader() {
        let incoming = ball()
        let farPlayer = player(position: incoming.position + Vector2(x: HeadingMechanics.reach + 0.01, y: 0))
        XCTAssertNil(HeadingMechanics.attackingHeader(ball: incoming, player: farPlayer,
            preparedFor: 0.11, tuning: .defaults))
        for distance in [-1.0, 28, 70] {
            let far = ball(distance: distance)
            XCTAssertNil(HeadingMechanics.attackingHeader(ball: far, player: player(position: far.position),
                preparedFor: 0.11, tuning: .defaults))
        }
        for height in [0.0, 0.84, 2.66, Double.nan] {
            let impossible = ball(height: height)
            XCTAssertNil(HeadingMechanics.attackingHeader(ball: impossible,
                player: player(position: impossible.position), preparedFor: 0.11, tuning: .defaults))
        }
        var keeper = player(position: incoming.position)
        keeper.isGoalkeeper = true
        XCTAssertNil(HeadingMechanics.attackingHeader(ball: incoming, player: keeper,
            preparedFor: 0.11, tuning: .defaults))
    }

    func testInvalidTimingAndVariationCannotCreateNonfiniteFlight() throws {
        let incoming = ball()
        let actor = player(position: incoming.position)
        for invalid in [Double.nan, .infinity, -.infinity, -0.1] {
            XCTAssertNil(HeadingMechanics.attackingHeader(ball: incoming, player: actor,
                preparedFor: invalid, tuning: .defaults))
        }
        XCTAssertNil(HeadingMechanics.attackingHeader(ball: incoming, player: actor,
            preparedFor: 0.11, tuning: .defaults, variation: .nan))
        var tuning = GameplayTuning.defaults
        tuning.ballGravity = .nan
        let result = try XCTUnwrap(HeadingMechanics.attackingHeader(ball: incoming,
            player: player(rating: .nan, position: incoming.position), preparedFor: 0.11,
            tuning: tuning, variation: 20))
        XCTAssertTrue(result.verticalVelocity.isFinite)
        XCTAssertTrue(result.speed.isFinite)
        XCTAssertEqual(result.direction.length, 1, accuracy: 0.000001)
    }
}
