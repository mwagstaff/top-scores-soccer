import XCTest
@testable import TopScoresSoccer

final class SplitControlsTests: XCTestCase {
    private func controlled(distance: Double = 20, x: Double = 0, north: Bool = true, mode: ExerciseMode = .passing) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var sim = FootballSimulation(tuning: tuning, mode: mode, chooseStartingEnds: { north })
        let attack = sim.ends.attackSign(for: .blue)
        sim.ball.position = Vector2(x: x, y: (Pitch.length / 2 - distance) * attack)
        sim.player.position = sim.ball.position - Vector2.up * attack
        sim.player.velocity = .zero
        sim.player.facing = .up * attack
        sim.ball.velocity = .zero
        sim.ball.height = 0
        for id in sim.roster.indices where id != sim.selectedPlayerID {
            sim.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? 29 : -29, y: -20)
            sim.roster[id].state.velocity = .zero
        }
        return sim
    }

    func testPassIsImmediateGroundPassEvenBesideGoalAndHoldingCannotShoot() {
        for distance in [5.0, 20, 45] {
            var sim = controlled(distance: distance)
            sim.roster[1].state.position = sim.ball.position + Vector2(x: 6, y: 2)
            sim.movement = Vector2(x: 1, y: 0)
            sim.pressAction(button: .pass)
            XCTAssertEqual(sim.kickCount, 1)
            XCTAssertEqual(sim.lastKick, .pass)
            XCTAssertEqual(sim.passTargetID, 1)
            XCTAssertEqual(sim.ball.verticalVelocity, 0)
            sim.updateActionHold(heldFor: 2)
            sim.releaseAction(heldFor: 2)
            XCTAssertEqual(sim.kickCount, 1)
            XCTAssertNil(sim.powerMeterKind)
        }
    }

    func testPassRejectsDistantOutletAndNeverFallsBackToShot() {
        var sim = controlled(distance: 15)
        sim.roster[1].state.position = sim.ball.position + Vector2(x: 30, y: 0)
        sim.movement = Vector2(x: 1, y: 0)
        XCTAssertNil(sim.shortPassTargetID)
        sim.pressAction(button: .pass)
        XCTAssertEqual(sim.lastKick, .pass)
        XCTAssertNil(sim.passTargetID)
        XCTAssertEqual(sim.ball.verticalVelocity, 0)
        XCTAssertLessThan(sim.ball.velocity.length, 15)
    }

    func testQuickShotIgnoresNearbyPassAndBackwardFacingForBothEnds() {
        for north in [true, false] {
            var sim = controlled(distance: 20, north: north, mode: .match)
            let goal = sim.ends.direction(for: .blue) * (Pitch.length / 2)
            sim.roster[1].state.position = sim.ball.position + Vector2(x: 5, y: 0)
            sim.movement = -sim.ends.direction(for: .blue)
            sim.pressAction(button: .shoot)
            XCTAssertEqual(sim.powerMeterKind, .shot)
            XCTAssertEqual(sim.kickCount, 0)
            let origin = sim.ball.position
            sim.releaseAction(heldFor: 0.08)
            XCTAssertEqual(sim.lastKickKind, "shot")
            XCTAssertEqual(sim.lastKick, .shot)
            XCTAssertGreaterThan(sim.ball.velocity.dot((goal - origin).normalized), 10)
            XCTAssertNil(sim.passTargetID)
        }
    }

    func testShootingRangeUsesRadialDistanceAndIncludesBoundary() {
        for distance in [34.9, 35, 35.1] {
            var sim = controlled(distance: distance)
            sim.pressAction(button: .shoot)
            XCTAssertEqual(sim.powerMeterKind, distance <= 35 ? .shot : .longKick)
            sim.releaseAction(heldFor: 0.05)
            XCTAssertEqual(sim.lastKickKind, distance <= 35 ? "shot" : "long kick")
        }
        var wide = controlled(distance: 20, x: 30)
        wide.pressAction(button: .shoot)
        XCTAssertNotEqual(wide.powerMeterKind, .shot)
    }

    func testCapturedShotCannotChangeToLongBallDuringHold() {
        var sim = controlled(distance: 34)
        sim.pressAction(button: .shoot)
        sim.player.position.y -= 3
        sim.ball.position.y -= 3
        sim.updateActionHold(heldFor: 0.65)
        XCTAssertEqual(sim.powerMeterKind, .shot)
        sim.releaseAction(heldFor: 0.65)
        XCTAssertEqual(sim.lastKickKind, "shot")
    }

    func testMeterStartsImmediatelyAndBandMovesHigherAndNarrowsWithDistance() throws {
        var previousLower = -1.0
        var previousWidth = 1.0
        for distance in [6.0, 18, 33] {
            var sim = controlled(distance: distance)
            sim.pressAction(button: .shoot)
            sim.updateActionHold(heldFor: 0.1)
            XCTAssertGreaterThan(sim.powerMeterFraction, 0)
            let band = try XCTUnwrap(sim.powerMeterSweetSpot)
            XCTAssertGreaterThan(band.lowerBound, previousLower)
            XCTAssertLessThan(band.upperBound - band.lowerBound, previousWidth)
            previousLower = band.lowerBound
            previousWidth = band.upperBound - band.lowerBound
            let held = ((band.lowerBound + band.upperBound) / 2) * sim.tuning.shotChargeDuration
            sim.updateActionHold(heldFor: held)
            XCTAssertFalse(sim.isOverchargingPower)
            sim.releaseAction(heldFor: held)
            XCTAssertEqual(sim.lastKickKind, "shot")
        }
    }

    func testPowerIncreasesSpeedAndOverhitFeedbackMatchesKick() {
        var previousSpeed = 0.0
        for held in [0.08, 0.3, 0.6, 0.95, 2.0] {
            var sim = controlled(distance: 30)
            sim.pressAction(button: .shoot)
            sim.updateActionHold(heldFor: held)
            let overhit = sim.isOverchargingPower
            sim.releaseAction(heldFor: held)
            XCTAssertEqual(sim.lastKickKind, overhit ? "overhit shot" : "shot")
            XCTAssertGreaterThanOrEqual(sim.ball.velocity.length + 0.000001, previousSpeed)
            previousSpeed = sim.ball.velocity.length
        }
    }

    func testLongBallTapAndHoldBothLoftAndLongerHoldAddsRange() {
        var previousSpeed = 0.0
        var previousLift = 0.0
        for held in [0.02, 0.3, 0.65] {
            var sim = controlled(distance: 70)
            sim.movement = Vector2(x: 0.3, y: 1)
            sim.pressAction(button: .shoot)
            sim.releaseAction(heldFor: held)
            XCTAssertEqual(sim.lastKickKind, "long kick")
            XCTAssertGreaterThan(sim.ball.velocity.length, previousSpeed)
            XCTAssertGreaterThan(sim.ball.verticalVelocity, previousLift)
            previousSpeed = sim.ball.velocity.length
            previousLift = sim.ball.verticalVelocity
        }
    }

    func testOffBallButtonsTackleImmediatelyOnceWithoutSwitchingOrQueuedKick() {
        for button in [PlayerActionButton.pass, .shoot] {
            var sim = controlled(distance: 60)
            sim.ball.position = Vector2(x: 0, y: 15)
            sim.ball.mode = .free
            sim.step(dt: 1.0 / 60)
            let actor = sim.selectedPlayerID
            XCTAssertFalse(sim.hasControl)
            sim.pressAction(button: button)
            XCTAssertEqual(sim.selectedPlayerID, actor)
            XCTAssertEqual(sim.standingTackleCount, button == .pass ? 1 : 0)
            XCTAssertEqual(sim.slideCount, button == .shoot ? 1 : 0)
            sim.updateActionHold(heldFor: 3)
            sim.releaseAction(heldFor: 3)
            XCTAssertEqual(sim.tackleCount, 1)
            XCTAssertEqual(sim.kickCount, 0)
            XCTAssertNil(sim.queuedActionKind)
            XCTAssertNil(sim.powerMeterKind)
        }
    }

    func testLossOfPossessionAndCancellationNeverReleaseKickOrSlide() {
        for cancel in [true, false] {
            var sim = controlled()
            sim.pressAction(button: .shoot)
            sim.updateActionHold(heldFor: 0.4)
            if cancel { sim.cancelInput() }
            else {
                sim.ball.position = Vector2(x: 25, y: -20)
                sim.step(dt: 1.0 / 60)
            }
            sim.releaseAction(heldFor: 0.6)
            XCTAssertEqual(sim.kickCount, 0)
            XCTAssertEqual(sim.slideCount, 0)
            XCTAssertNil(sim.powerMeterKind)
        }
    }

    func testWellPoweredShotsCanScoreThroughRealBallPhysicsAtEveryDistance() {
        for distance in [6.0, 18, 33] {
            var sim = controlled(distance: distance, mode: .solo)
            let band = KickMechanics.distancePower(distance: distance, heldFor: 0, tuning: sim.tuning).sweetSpot
            let held = (band.lowerBound + band.upperBound) / 2 * sim.tuning.shotChargeDuration
            sim.pressAction(button: .shoot)
            sim.releaseAction(heldFor: held)
            for _ in 0..<300 where sim.phase == .playing { sim.step(dt: 1.0 / 60) }
            XCTAssertEqual(sim.northGoals, 1, "A controlled shot from \(distance)m must remain physically scoreable.")
        }
    }

    func testShootingWinsOverCrossFromAdvancedWing() {
        var sim = controlled(distance: 16, x: 26)
        sim.roster[1].state.position = Vector2(x: 0, y: 41)
        XCTAssertTrue(sim.canCross)
        sim.pressAction(button: .shoot)
        XCTAssertEqual(sim.powerMeterKind, .shot)
        sim.releaseAction(heldFor: 0.6)
        XCTAssertEqual(sim.crossCount, 0)
        XCTAssertEqual(sim.lastKickKind, "shot")
    }

    func testReceivingKeepsExplicitPassShotAndLongBallIntentUntilContact() {
        for (button, distance) in [(PlayerActionButton.pass, 20.0), (.shoot, 20.0), (.shoot, 60.0)] {
            var sim = controlled(distance: distance, mode: .solo)
            sim.ball.position = sim.player.position + .up * 6
            sim.ball.velocity = -.up * 10
            sim.ball.mode = .free
            sim.step(dt: 1.0 / 60)
            XCTAssertTrue(sim.canPrepareReceivingKick)
            sim.pressAction(button: button)
            if button == .shoot { sim.releaseAction(heldFor: 0.55) }
            XCTAssertEqual(sim.queuedActionKind, button == .pass ? "pass" : "shot")
            for _ in 0..<75 where sim.kickCount == 0 { sim.step(dt: 1.0 / 60) }
            XCTAssertEqual(sim.kickCount, 1)
            XCTAssertEqual(sim.lastKick, button == .pass ? .pass : .shot)
            if button == .shoot { XCTAssertEqual(sim.lastKickKind, distance < 35 ? "shot" : "long kick") }
            XCTAssertEqual(sim.slideCount, 0)
            XCTAssertEqual(sim.standingTackleCount, 0)
        }
    }

    func testSecondButtonCannotStealAnActiveShotCharge() {
        var sim = controlled(distance: 20)
        sim.pressAction(button: .shoot)
        sim.updateActionHold(heldFor: 0.3)
        sim.pressAction(button: .pass)
        XCTAssertEqual(sim.kickCount, 0)
        XCTAssertEqual(sim.powerMeterKind, .shot)
        sim.releaseAction(heldFor: 0.45)
        XCTAssertEqual(sim.kickCount, 1)
        XCTAssertEqual(sim.lastKick, .shot)
    }

    func testLongDistanceAndExcessPowerIncreaseExecutionSpread() throws {
        func spread(distance: Double, hold: Double) throws -> Double {
            var total = 0.0
            for sequence in 0..<100 {
                let shot = try XCTUnwrap(KickMechanics.chargedShot(
                    origin: Vector2(x: 0, y: Pitch.length / 2 - distance), aim: .up,
                    facing: .up, team: .blue, heldFor: hold, tuning: .defaults,
                    ends: MatchEnds(), sequence: sequence))
                total += abs(atan2(shot.direction.x, shot.direction.y))
            }
            return total / 100
        }
        XCTAssertGreaterThan(try spread(distance: 33, hold: 0.7), try spread(distance: 8, hold: 0.25))
        XCTAssertGreaterThan(try spread(distance: 33, hold: 0.95), try spread(distance: 33, hold: 0.7))
    }
}
