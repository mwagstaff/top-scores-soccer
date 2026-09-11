import XCTest
@testable import TopScoresSoccer

final class CrossingMechanicsTests: XCTestCase {
    private let tuning = GameplayTuning.defaults

    private func footballer(_ id: Int, x: Double, y: Double, team: Team = .blue,
                            role: String = "M", rating: Double = 78) -> Footballer {
        Footballer(id: id, team: team, state: PlayerState(position: Vector2(x: x, y: y)),
            clubPlayer: ClubPlayer(id: "cross-\(id)", name: "Cross test", position: role,
                rating: rating, appearance: .generated(for: "cross-test")))
    }

    private func delivery(rating: Double = 78, hold: Double = 0.75, sequence: Int = 0,
                          x: Double = 27, y: Double = 37) -> CrossingMechanics.Plan {
        let crosser = footballer(0, x: x, y: y, rating: rating)
        let receiver = footballer(1, x: 0, y: 41, role: "F")
        return CrossingMechanics.plan(origin: crosser.state.position, crosser: crosser,
            roster: [crosser, receiver], heldFor: hold, tuning: tuning, sequence: sequence)!
    }

    func testCrossZoneAndAutomaticBoxTargetMirrorBothFlanksAndAttackingEnds() throws {
        for north in [true, false] {
            let ends = MatchEnds(blueAttacksNorth: north)
            for team in [Team.blue, .red] {
                let attack = ends.attackSign(for: team)
                for flank in [-1.0, 1] {
                    let crosser = footballer(0, x: flank * 27, y: 37 * attack, team: team)
                    var receiver = footballer(1, x: 3, y: 39 * attack, team: team, role: "F")
                    receiver.state.velocity = .up * 5 * attack
                    let plan = try XCTUnwrap(CrossingMechanics.plan(origin: crosser.state.position,
                        crosser: crosser, roster: [crosser, receiver], heldFor: 0.75,
                        tuning: tuning, ends: ends))
                    XCTAssertEqual(plan.receiverID, receiver.id)
                    XCTAssertLessThan(plan.direction.x * flank, -0.8)
                    XCTAssertGreaterThan(plan.destination.y * attack, receiver.state.position.y * attack)
                    XCTAssertLessThanOrEqual(abs(plan.destination.x), 13)
                    XCTAssertGreaterThanOrEqual(plan.destination.y * attack, 38.5)
                    XCTAssertEqual(plan.positionQuality, 1)
                }
            }
        }
    }

    func testRealisticWingPositionsAreRequiredAndSideOfBoxIsBest() throws {
        let prime = try XCTUnwrap(CrossingMechanics.positionalQuality(origin: Vector2(x: 27, y: 37), team: .blue))
        for origin in [Vector2(x: 27, y: 21), Vector2(x: 33, y: 49)] {
            XCTAssertLessThan(try XCTUnwrap(CrossingMechanics.positionalQuality(origin: origin, team: .blue)), prime)
        }
        for origin in [Vector2(x: 19, y: 37), Vector2(x: 27, y: 15),
                       Vector2(x: 27, y: 50), Vector2(x: 35, y: 37), Vector2(x: .nan, y: 37)] {
            XCTAssertNil(CrossingMechanics.positionalQuality(origin: origin, team: .blue))
        }
    }

    func testShortSweetAndOverhitReleasesProduceDifferentPhysicalTravel() {
        let short = delivery(hold: 0.28)
        let sweet = delivery(hold: 0.75)
        let over = delivery(hold: 1.4)
        let intendedDistance = (sweet.destination - Vector2(x: 27, y: 37)).length
        XCTAssertTrue(short.isUnderhit)
        XCTAssertFalse(sweet.isUnderhit)
        XCTAssertFalse(sweet.isOverhit)
        XCTAssertTrue(over.isOverhit)
        XCTAssertLessThan(short.speed * short.flightTime, intendedDistance * 0.6)
        XCTAssertEqual(sweet.speed * sweet.flightTime, intendedDistance, accuracy: 0.5)
        XCTAssertGreaterThan(over.speed * over.flightTime, intendedDistance * 1.65)
        XCTAssertGreaterThan(sweet.timingQuality, short.timingQuality)
        XCTAssertGreaterThan(sweet.timingQuality, over.timingQuality)
    }

    func testSweetCrossArrivesDescendingAtHeadingHeightUnderActualBallPhysics() {
        for plan in [delivery(x: 23, y: 34), delivery(x: -33, y: 45), delivery(x: 31, y: 23)] {
            var ball = BallState(position: .zero, velocity: plan.direction * plan.speed,
                mode: .pass, height: plan.height, verticalVelocity: plan.verticalVelocity)
            let steps = 120
            for _ in 0..<steps {
                let dt = plan.flightTime / Double(steps)
                ball.position += ball.velocity * dt
                BallFlight.advance(&ball, dt: dt, gravity: tuning.ballGravity)
            }
            XCTAssertEqual(ball.height, CrossingMechanics.arrivalHeight, accuracy: 0.00001)
            XCTAssertLessThan(ball.verticalVelocity, 0)
            XCTAssertEqual(ball.position.length, plan.speed * plan.flightTime, accuracy: 0.00001)
        }
    }

    func testBetterRatedMidfieldersHaveSmallerCrossErrorAcrossRepeatedReleases() {
        var lowError = 0.0
        var highError = 0.0
        let origin = Vector2(x: 27, y: 37)
        for sequence in 0..<100 {
            let low = delivery(rating: 55, sequence: sequence)
            let high = delivery(rating: 95, sequence: sequence)
            lowError += (origin + low.direction * low.speed * low.flightTime - low.destination).length
            highError += (origin + high.direction * high.speed * high.flightTime - high.destination).length
            XCTAssertGreaterThan(high.accuracy, low.accuracy)
        }
        XCTAssertLessThan(highError, lowError * 0.35)
        for role in ["M", "F"] {
            XCTAssertGreaterThan(CrossingMechanics.ability(footballer(0, x: 27, y: 37, role: role, rating: 90)),
                                 CrossingMechanics.ability(footballer(0, x: 27, y: 37, role: "D", rating: 90)))
        }
        XCTAssertGreaterThan(delivery().accuracy, delivery(y: 21).accuracy)
    }

    func testUnavailableOffsideAndUnreachableTeammatesCannotBeSelected() {
        let crosser = footballer(0, x: 27, y: 37)
        let good = footballer(1, x: 0, y: 41, role: "F")
        for mode in 0..<6 {
            var unavailable = good
            switch mode {
            case 0: unavailable.isInjured = true
            case 1: unavailable.isSentOff = true
            case 2: unavailable.isGoalkeeper = true
            case 3: unavailable.isTackling = true
            case 4: unavailable.recoveryProgress = 0.5
            default: unavailable.state.position = Vector2(x: -25, y: 23.5)
            }
            XCTAssertNil(CrossingMechanics.opportunity(crosser: crosser,
                roster: [crosser, unavailable], tuning: tuning))
        }
        XCTAssertNil(CrossingMechanics.opportunity(crosser: crosser, roster: [crosser, good],
            tuning: tuning, excludedReceiverIDs: [good.id]))
        XCTAssertNil(CrossingMechanics.plan(origin: crosser.state.position, crosser: crosser,
            roster: [crosser, good], heldFor: 0.75, tuning: tuning, excludedReceiverIDs: [good.id]))
        XCTAssertNil(CrossingMechanics.plan(origin: crosser.state.position, crosser: crosser,
            roster: [crosser, good], heldFor: 0.1, tuning: tuning))
    }

    func testSupportRunsStayOnsideAndReverseForTheOtherEnd() {
        for north in [true, false] {
            let attack = north ? 1.0 : -1
            let crosser = footballer(0, x: 27, y: 37 * attack)
            let roster = [crosser, footballer(1, x: 0, y: 30 * attack, role: "F"),
                footballer(2, x: 8, y: 29 * attack, role: "M"),
                footballer(3, x: -8, y: 29 * attack, role: "F"),
                footballer(4, x: -8, y: 0, role: "D")]
            let targets = CrossingMechanics.supportTargets(crosser: crosser, roster: roster,
                offsideLine: 40, ends: MatchEnds(blueAttacksNorth: north))
            XCTAssertEqual(Set(targets.keys), [1, 2, 3])
            for position in targets.values {
                XCTAssertLessThanOrEqual(position.y * attack, 38.8)
                XCTAssertGreaterThan(position.y * attack, 30)
                XCTAssertLessThanOrEqual(abs(position.x), 8)
            }
        }
    }

    func testBlueReceiverCanRunForCrossWhenOpponentAISpeedIsDisabled() {
        var stationaryAI = tuning
        stationaryAI.aiSpeedScale = 0
        let crosser = footballer(0, x: 27, y: 37)
        let receiver = footballer(1, x: 5, y: 34, role: "F")
        XCTAssertNotNil(CrossingMechanics.opportunity(crosser: crosser,
            roster: [crosser, receiver], tuning: stationaryAI))
    }

    func testMeterAndPhysicalReleaseBoundariesAgree() {
        let band = CrossingMechanics.sweetSpot(tuning: tuning)
        let durations = CrossingMechanics.sweetSpotDurations(tuning: tuning)
        XCTAssertEqual(CrossingMechanics.meterFraction(heldFor: durations.lowerBound, tuning: tuning), band.lowerBound, accuracy: 0.000001)
        XCTAssertEqual(CrossingMechanics.meterFraction(heldFor: durations.upperBound, tuning: tuning), band.upperBound, accuracy: 0.000001)
        let overTime = tuning.holdThreshold + tuning.fullChargeDuration * 1.22
        XCTAssertFalse(CrossingMechanics.isOverhit(heldFor: overTime, tuning: tuning))
        XCTAssertTrue(CrossingMechanics.isOverhit(heldFor: overTime + 0.001, tuning: tuning))
        XCTAssertEqual(CrossingMechanics.meterFraction(heldFor: overTime, tuning: tuning), CrossingMechanics.overhitStart(tuning: tuning), accuracy: 0.000001)
    }
}
