import XCTest
@testable import TopScoresSoccer

final class KickMechanicsTests: XCTestCase {
    private let tuning = GameplayTuning.defaults

    private func origin(distance: Double, team: Team = .blue) -> Vector2 {
        Vector2(x: 0, y: (team == .blue ? 1 : -1) * (Pitch.length / 2 - distance))
    }

    /// Advance the actual shared vertical physics in fixed steps to the full-ball goal plane.
    private func ballAtGoal(_ shot: KickMechanics.Shot, origin: Vector2, team: Team = .blue,
                            tuning: GameplayTuning = .defaults) -> BallState {
        var ball = BallState(position: origin, velocity: shot.direction * shot.speed,
                             mode: .shot, height: 0, verticalVelocity: shot.verticalVelocity)
        let attack = team == .blue ? 1.0 : -1.0
        let crossingY = attack * (Pitch.length / 2 + Pitch.ballRadius)
        var remaining = (crossingY - origin.y) / ball.velocity.y
        for _ in 0..<1800 where remaining > 0.0000001 {
            let dt = min(1.0 / 60.0, remaining)
            ball.position += ball.velocity * dt
            BallFlight.advance(&ball, dt: dt, gravity: tuning.ballGravity)
            remaining -= dt
        }
        return ball
    }

    private func firstLandingDistance(_ flight: KickMechanics.Flight, gravity: Double = 18) -> Double {
        let time = (flight.verticalVelocity + sqrt(flight.verticalVelocity * flight.verticalVelocity
            + 2 * gravity * flight.height)) / gravity
        return time * flight.speed
    }

    func testSweetHoldsProduceRaisedCornerShotsBelowTheFullBallCrossbarLimit() throws {
        for team in [Team.blue, .red] {
            let attack = team == .blue ? 1.0 : -1.0
            for distance in [8.0, 16, 28] {
                for hold in [0.60, 0.75, 0.90] {
                    let start = origin(distance: distance, team: team)
                    let shot = try XCTUnwrap(KickMechanics.shot(origin: start, aim: Vector2(x: 0.45, y: attack),
                                                                team: team, heldFor: hold, tuning: tuning))
                    let arrival = ballAtGoal(shot, origin: start, team: team)
                    XCTAssertFalse(shot.isOverhit)
                    XCTAssertGreaterThan(arrival.position.x, 3)
                    XCTAssertLessThan(arrival.position.x, Pitch.goalWidth / 2 - Pitch.postRadius - Pitch.ballRadius)
                    XCTAssertGreaterThan(arrival.height, 0.6)
                    XCTAssertLessThan(arrival.height + Pitch.ballRadius * 2, Pitch.crossbarHeight - 0.05)
                }
            }
        }
    }

    func testLongOverholdPhysicallyRisesAboveBarWithoutChangingTheGoalRules() throws {
        for distance in [8.0, 16, 28] {
            let start = origin(distance: distance)
            let controlled = try XCTUnwrap(KickMechanics.shot(origin: start, aim: .up, team: .blue,
                                                             heldFor: 0.90, tuning: tuning))
            let overhit = try XCTUnwrap(KickMechanics.shot(origin: start, aim: .up, team: .blue,
                                                         heldFor: 1.30, tuning: tuning))
            XCTAssertFalse(controlled.isOverhit)
            XCTAssertTrue(overhit.isOverhit)
            XCTAssertEqual(overhit.direction, controlled.direction)
            XCTAssertGreaterThan(ballAtGoal(overhit, origin: start).height + Pitch.ballRadius * 2,
                                 Pitch.crossbarHeight + 1)
            XCTAssertLessThan(ballAtGoal(controlled, origin: start).height + Pitch.ballRadius * 2,
                              Pitch.crossbarHeight)
        }
    }

    func testDeliberateLeftCentreAndRightAimsKeepDifferentGoalIntercepts() throws {
        let start = origin(distance: 20)
        var intercepts: [Double] = []
        for x in [-0.5, -0.1, 0, 0.1, 0.5] {
            let shot = try XCTUnwrap(KickMechanics.shot(origin: start, aim: Vector2(x: x, y: 1),
                                                       team: .blue, heldFor: 0.75, tuning: tuning))
            intercepts.append(ballAtGoal(shot, origin: start).position.x)
        }
        XCTAssertLessThan(intercepts[0], -3)
        XCTAssertEqual(intercepts[2], 0, accuracy: 0.000001)
        XCTAssertGreaterThan(intercepts[4], 3)
        for pair in zip(intercepts, intercepts.dropFirst()) { XCTAssertLessThan(pair.0, pair.1) }
        XCTAssertEqual(intercepts[0], -intercepts[4], accuracy: 0.000001)
        XCTAssertEqual(intercepts[1], -intercepts[3], accuracy: 0.000001)
    }

    func testShotPowerAndArrivalHeightIncreaseAcrossControlledCharge() throws {
        let start = origin(distance: 22)
        var previousSpeed = 0.0
        var previousHeight = -1.0
        var previousMeter = -1.0
        for hold in [0.27, 0.4, 0.6, 0.75, 0.9] {
            let shot = try XCTUnwrap(KickMechanics.shot(origin: start, aim: .up, team: .blue,
                                                       heldFor: hold, tuning: tuning))
            let height = ballAtGoal(shot, origin: start).height
            let meter = KickMechanics.shotMeterFraction(heldFor: hold, tuning: tuning)
            XCTAssertGreaterThan(shot.speed, previousSpeed)
            XCTAssertGreaterThan(height, previousHeight)
            XCTAssertGreaterThan(meter, previousMeter)
            previousSpeed = shot.speed
            previousHeight = height
            previousMeter = meter
        }
        XCTAssertLessThanOrEqual(previousSpeed, tuning.shotMaxSpeed)
    }

    func testMeterSweetBandAndOverhitThresholdAgreeWithDurationSettings() {
        let defaults = KickMechanics.shotSweetSpotDurations(tuning: tuning)
        XCTAssertEqual(defaults.lowerBound, 0.598, accuracy: 0.000001)
        XCTAssertEqual(defaults.upperBound, 0.90025, accuracy: 0.000001)
        XCTAssertFalse(KickMechanics.isOverhit(heldFor: 1.05, tuning: tuning))
        XCTAssertTrue(KickMechanics.isOverhit(heldFor: 1.06, tuning: tuning))
        XCTAssertEqual(KickMechanics.shotMeterFraction(heldFor: 1.30, tuning: tuning), 1, accuracy: 0.000001)
        XCTAssertEqual(KickMechanics.shotOverhitStart(tuning: tuning), 0.7625, accuracy: 0.000001)
        var slower = tuning
        slower.holdThreshold = 0.3
        slower.fullChargeDuration = 1
        for setting in [tuning, slower] {
            let durations = KickMechanics.shotSweetSpotDurations(tuning: setting)
            let band = KickMechanics.shotSweetSpot(tuning: setting)
            XCTAssertEqual(band.lowerBound, KickMechanics.shotMeterFraction(heldFor: durations.lowerBound, tuning: setting))
            XCTAssertEqual(band.upperBound, KickMechanics.shotMeterFraction(heldFor: durations.upperBound, tuning: setting))
            XCTAssertGreaterThan(band.lowerBound, 0)
            XCTAssertLessThan(band.upperBound, 1)
            XCTAssertFalse(KickMechanics.isOverhit(heldFor: durations.upperBound, tuning: setting))
            let overhitTime = setting.holdThreshold + setting.fullChargeDuration * 1.22
            XCTAssertEqual(KickMechanics.shotOverhitStart(tuning: setting),
                           KickMechanics.shotMeterFraction(heldFor: overhitTime, tuning: setting))
            XCTAssertFalse(KickMechanics.isOverhit(heldFor: overhitTime, tuning: setting))
            XCTAssertTrue(KickMechanics.isOverhit(heldFor: overhitTime + 0.0001, tuning: setting))
        }
    }

    func testShotsOutsideConeRangeOrPitchAreNotAssisted() {
        let start = origin(distance: 20)
        for aim in [Vector2(x: 1, y: 0), -.up, .zero] {
            XCTAssertNil(KickMechanics.shot(origin: start, aim: aim, team: .blue, heldFor: 0.75, tuning: tuning))
        }
        var shortRange = tuning
        shortRange.shotAssistRange = 10
        XCTAssertNil(KickMechanics.shot(origin: start, aim: .up, team: .blue, heldFor: 0.75, tuning: shortRange))
        XCTAssertNil(KickMechanics.shot(origin: Vector2(x: 0, y: 54), aim: -.up, team: .blue,
                                        heldFor: 0.75, tuning: tuning))
        XCTAssertNil(KickMechanics.shot(origin: Vector2(x: 1000, y: 0), aim: Vector2(x: -1, y: 1),
                                        team: .blue, heldFor: 0.75, tuning: tuning))
    }

    func testFarShotsUseOrdinaryBoundedLoftRatherThanSolvingDistantArrival() throws {
        let near = try XCTUnwrap(KickMechanics.shot(origin: origin(distance: 40), aim: .up,
                                                   team: .blue, heldFor: 0.75, tuning: tuning))
        let far = try XCTUnwrap(KickMechanics.shot(origin: origin(distance: 90), aim: .up,
                                                  team: .blue, heldFor: 0.75, tuning: tuning))
        XCTAssertEqual(near.speed, far.speed)
        XCTAssertEqual(near.verticalVelocity, far.verticalVelocity)
        XCTAssertLessThan(far.verticalVelocity, 10)
        XCTAssertGreaterThan(far.verticalVelocity, 0)
    }

    func testNearLineAndLargeFiniteAimRemainBounded() throws {
        for distance in [0.001, 0.1, 0.9] {
            let shot = try XCTUnwrap(KickMechanics.shot(origin: origin(distance: distance),
                                                       aim: Vector2(x: 0, y: 1e200), team: .blue,
                                                       heldFor: 20, tuning: tuning))
            XCTAssertTrue(shot.direction.x.isFinite)
            XCTAssertTrue(shot.direction.y.isFinite)
            XCTAssertEqual(shot.direction.length, 1, accuracy: 0.000001)
            XCTAssertLessThanOrEqual(shot.verticalVelocity, 32)
            XCTAssertLessThanOrEqual(shot.speed, tuning.shotMaxSpeed)
        }
    }

    func testInvalidInputCannotCreateNonfiniteShotOrPower() throws {
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertNil(KickMechanics.shot(origin: origin(distance: 16), aim: .up, team: .blue,
                                            heldFor: invalid, tuning: tuning))
            XCTAssertEqual(KickMechanics.shotMeterFraction(heldFor: invalid, tuning: tuning), 0)
            XCTAssertFalse(KickMechanics.isOverhit(heldFor: invalid, tuning: tuning))
            XCTAssertTrue(KickMechanics.throwIn(heldFor: invalid, tuning: tuning).speed.isFinite)
            XCTAssertTrue(KickMechanics.keeperDistribution(heldFor: invalid, tuning: tuning).verticalVelocity.isFinite)
        }
        XCTAssertNil(KickMechanics.shot(origin: Vector2(x: .nan, y: 0), aim: .up, team: .blue,
                                        heldFor: 0.75, tuning: tuning))
        XCTAssertNil(KickMechanics.shot(origin: .zero, aim: Vector2(x: .infinity, y: 0), team: .blue,
                                        heldFor: 0.75, tuning: tuning))
        var corrupt = tuning
        corrupt.holdThreshold = .nan
        corrupt.fullChargeDuration = 0
        corrupt.shotMinSpeed = .infinity
        corrupt.shotMaxSpeed = -.infinity
        corrupt.ballGravity = .nan
        let result = try XCTUnwrap(KickMechanics.shot(origin: origin(distance: 16), aim: .up, team: .blue,
                                                     heldFor: 0.75, tuning: corrupt))
        XCTAssertTrue(result.speed.isFinite)
        XCTAssertTrue(result.verticalVelocity.isFinite)
        XCTAssertGreaterThan(result.speed, 0)
    }

    func testThrowHoldAddsPhysicalDistanceAndNeverHasAnOverholdPenalty() {
        var previous = 0.0
        for held in [0.1, 0.4, 0.6, 0.9, 1.1] {
            let flight = KickMechanics.throwIn(heldFor: held, tuning: tuning)
            let distance = firstLandingDistance(flight)
            XCTAssertGreaterThan(distance, previous)
            XCTAssertGreaterThan(flight.height, 1)
            previous = distance
        }
        let tap = KickMechanics.throwIn(heldFor: 0.1, tuning: tuning)
        let long = KickMechanics.throwIn(heldFor: 1.1, tuning: tuning)
        XCTAssertLessThan(firstLandingDistance(tap), 12)
        XCTAssertGreaterThan(firstLandingDistance(long), 24)
        XCTAssertEqual(KickMechanics.throwIn(heldFor: 10, tuning: tuning), long)
    }

    func testUntargetedKeeperThrowsStayOverarmAndGainHeightAndRangeWithHold() {
        let tap = KickMechanics.keeperDistribution(heldFor: 0.1, tuning: tuning)
        let modest = KickMechanics.keeperDistribution(heldFor: 0.4, tuning: tuning)
        let full = KickMechanics.keeperDistribution(heldFor: 1.1, tuning: tuning)
        XCTAssertGreaterThan(tap.height, 1)
        XCTAssertEqual(tap.height, modest.height)
        XCTAssertEqual(full.height, modest.height)
        XCTAssertGreaterThan(modest.speed, tap.speed)
        XCTAssertGreaterThan(full.speed, modest.speed)
        XCTAssertGreaterThan(modest.verticalVelocity, tap.verticalVelocity)
        XCTAssertGreaterThan(full.verticalVelocity, modest.verticalVelocity)
        XCTAssertGreaterThan(firstLandingDistance(modest), firstLandingDistance(tap))
        XCTAssertGreaterThan(firstLandingDistance(full), firstLandingDistance(modest))
        XCTAssertLessThan(firstLandingDistance(tap), 24)
        XCTAssertGreaterThan(firstLandingDistance(full), 45)
        XCTAssertEqual(KickMechanics.keeperDistribution(heldFor: 10, tuning: tuning), full)
    }

    func testSharedPhysicsStillUsesConfiguredGravityForUsefulShotHeight() throws {
        for gravity in [9.0, 18, 28] {
            var changed = tuning
            changed.ballGravity = gravity
            let start = origin(distance: 24)
            let shot = try XCTUnwrap(KickMechanics.shot(origin: start, aim: .up, team: .blue,
                                                       heldFor: 0.85, tuning: changed))
            let arrival = ballAtGoal(shot, origin: start, tuning: changed)
            XCTAssertGreaterThan(arrival.height, 1)
            XCTAssertLessThan(arrival.height + Pitch.ballRadius * 2, Pitch.crossbarHeight)
        }
    }
}
