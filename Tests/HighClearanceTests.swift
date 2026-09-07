import XCTest
@testable import TopScoresSoccer

final class HighClearanceTests: XCTestCase {
    private let tuning = GameplayTuning.defaults

    private func firstLanding(_ flight: KickMechanics.Flight, gravity: Double = 18) -> Double {
        let time = (flight.verticalVelocity + sqrt(flight.verticalVelocity * flight.verticalVelocity
            + 2 * gravity * flight.height)) / gravity
        return flight.speed * time
    }

    /// Use the shared flight integrator, including its bottom-of-ball height convention.
    private func atDistance(_ distance: Double, flight: KickMechanics.Flight,
                            gravity: Double = 18) -> BallState {
        var ball = BallState(position: .zero, velocity: Vector2(x: flight.speed, y: 0),
                             mode: .shot, height: flight.height, verticalVelocity: flight.verticalVelocity)
        var remaining = distance / flight.speed
        while remaining > 0.0000001 {
            let dt = min(1.0 / 60, remaining)
            ball.position += ball.velocity * dt
            BallFlight.advance(&ball, dt: dt, gravity: gravity, bounceRestitution: 0)
            remaining -= dt
        }
        return ball
    }

    func testModerateHoldsLiftOverFeetWithoutNeedingAftertouch() {
        for held in [0.4, 0.5, 0.6] {
            let flight = KickMechanics.longKick(heldFor: held, tuning: tuning)
            XCTAssertEqual(flight.height, 0, "A clearance starts from the foot on the ground")
            XCTAssertGreaterThan(atDistance(5, flight: flight).height, 1.1)
            XCTAssertGreaterThan(atDistance(10, flight: flight).height, 1.8)
            XCTAssertGreaterThan(firstLanding(flight), 25)
            XCTAssertLessThan(firstLanding(flight), 42)
        }
    }

    func testFirmHoldProducesHighClearanceAcrossFortyToSixtyMetres() {
        for held in [0.9, 1.1, 2] {
            let flight = KickMechanics.longKick(heldFor: held, tuning: tuning)
            XCTAssertGreaterThan(firstLanding(flight), 40)
            XCTAssertLessThan(firstLanding(flight), 60)
            XCTAssertGreaterThan(atDistance(12, flight: flight).height, 2.6)
            XCTAssertGreaterThan(atDistance(30, flight: flight).height, 4)
            XCTAssertGreaterThan(atDistance(45, flight: flight).height, 2.8)
            let descending = atDistance(52, flight: flight)
            XCTAssertGreaterThan(descending.height, 0.9)
            XCTAssertLessThan(descending.height, 2.6, "The far end of the flight can be contested by a header")
            XCTAssertLessThan(descending.verticalVelocity, 0)
        }
    }

    func testLongKickChargeProgressivelyAddsSpeedHeightAndLandingDistance() {
        var previousSpeed = 0.0
        var previousApex = 0.0
        var previousRange = 0.0
        for held in [0.27, 0.4, 0.5, 0.6, 0.75, 0.9] {
            let flight = KickMechanics.longKick(heldFor: held, tuning: tuning)
            let apex = flight.height + flight.verticalVelocity * flight.verticalVelocity / (2 * tuning.ballGravity)
            XCTAssertGreaterThan(flight.speed, previousSpeed)
            XCTAssertGreaterThan(apex, previousApex)
            XCTAssertGreaterThan(firstLanding(flight), previousRange)
            previousSpeed = flight.speed
            previousApex = apex
            previousRange = firstLanding(flight)
        }
    }

    func testOverholdingClearanceCapsPowerInsteadOfApplyingShotPenalty() {
        let full = KickMechanics.longKick(heldFor: tuning.holdThreshold + tuning.fullChargeDuration, tuning: tuning)
        for held in [1.3, 2, 10, 1000] {
            XCTAssertEqual(KickMechanics.longKick(heldFor: held, tuning: tuning), full)
        }
        XCTAssertGreaterThan(full.verticalVelocity, 12)
        XCTAssertLessThan(full.speed, tuning.shotMaxSpeed)
    }

    func testClearanceLandsThroughSharedGravityWithoutSyntheticRangeOrHoming() {
        let flight = KickMechanics.longKick(heldFor: 0.9, tuning: tuning)
        for gravity in [12.0, 18, 24] {
            let landing = firstLanding(flight, gravity: gravity)
            let before = atDistance(landing - 0.1, flight: flight, gravity: gravity)
            let atLanding = atDistance(landing, flight: flight, gravity: gravity)
            XCTAssertGreaterThan(before.height, 0)
            XCTAssertLessThan(before.verticalVelocity, 0)
            XCTAssertEqual(atLanding.height, 0, accuracy: 0.000001)
            XCTAssertEqual(atLanding.position.x, landing, accuracy: 0.000001)
            XCTAssertEqual(atLanding.position.y, 0)
        }
        XCTAssertGreaterThan(firstLanding(flight, gravity: 12), firstLanding(flight, gravity: 24))
    }

    func testExistingTimingAndSpeedSettingsStillControlClearanceCharge() {
        var slower = tuning
        slower.holdThreshold = 0.4
        slower.fullChargeDuration = 1.2
        let partial = KickMechanics.longKick(heldFor: 0.6, tuning: slower)
        let normal = KickMechanics.longKick(heldFor: 0.6, tuning: tuning)
        XCTAssertLessThan(partial.speed, normal.speed)
        XCTAssertLessThan(partial.verticalVelocity, normal.verticalVelocity)
        XCTAssertEqual(KickMechanics.longKick(heldFor: 1.6, tuning: slower),
                       KickMechanics.longKick(heldFor: 0.91, tuning: tuning))
        var weaker = tuning
        weaker.shotMinSpeed = 20
        weaker.shotMaxSpeed = 35
        XCTAssertLessThan(firstLanding(KickMechanics.longKick(heldFor: 0.9, tuning: weaker)),
                          firstLanding(KickMechanics.longKick(heldFor: 0.9, tuning: tuning)))
    }

    func testInvalidOrExtremeInputsCannotProduceUnboundedFlight() {
        let neutral = KickMechanics.longKick(heldFor: 0, tuning: tuning)
        for held in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(KickMechanics.longKick(heldFor: held, tuning: tuning), neutral)
        }
        for value in [Double.nan, .infinity, -.infinity, -1000, 1e100] {
            var invalid = tuning
            invalid.shotMinSpeed = value
            invalid.shotMaxSpeed = value
            invalid.holdThreshold = value
            invalid.fullChargeDuration = value
            let flight = KickMechanics.longKick(heldFor: 1e100, tuning: invalid)
            XCTAssertTrue(flight.speed.isFinite)
            XCTAssertTrue(flight.verticalVelocity.isFinite)
            XCTAssertGreaterThan(flight.speed, 0)
            XCTAssertLessThanOrEqual(flight.speed, 58.5)
            XCTAssertGreaterThanOrEqual(flight.verticalVelocity, 8)
            XCTAssertLessThanOrEqual(flight.verticalVelocity, 12.5)
        }
    }
}
