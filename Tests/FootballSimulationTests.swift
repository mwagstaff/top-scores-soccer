import XCTest
@testable import TopScoresSoccer

final class FootballSimulationTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    func testMovementAcceleratesReversesWithMomentumAndStops() {
        var simulation = FootballSimulation()
        simulation.movement = .up
        simulation.step(dt: tick)
        XCTAssertGreaterThan(simulation.player.velocity.y, 0)
        XCTAssertLessThan(simulation.player.velocity.y, simulation.tuning.playerMaxSpeed)
        advance(&simulation, frames: 45)
        XCTAssertEqual(simulation.player.velocity.y, simulation.tuning.playerMaxSpeed, accuracy: 0.0001)

        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertGreaterThan(simulation.player.velocity.y, 0, "A reversal must retain brief momentum.")
        XCTAssertGreaterThan(simulation.player.facing.y, 0, "Facing must turn rather than flip instantly.")
        advance(&simulation, frames: 35)
        XCTAssertLessThan(simulation.player.velocity.y, -9)
        simulation.movement = .zero
        advance(&simulation, frames: 30)
        XCTAssertEqual(simulation.player.velocity.length, 0, accuracy: 0.0001)
    }

    func testDribblingMovesIndependentBallBetweenPeriodicTouches() {
        var simulation = FootballSimulation()
        simulation.movement = .up
        var gaps: [Double] = []
        var controlledFrames = 0
        var rollingFrames = 0
        for _ in 0..<120 {
            let previousBallVelocity = simulation.ball.velocity.length
            simulation.step(dt: tick)
            gaps.append((simulation.ball.position - simulation.player.position).length)
            if simulation.hasControl { controlledFrames += 1 }
            if previousBallVelocity > 1,
               abs(previousBallVelocity - simulation.ball.velocity.length - simulation.tuning.ballFriction * tick) < 0.0001 {
                rollingFrames += 1
            }
        }
        XCTAssertGreaterThan(simulation.player.position.y, 15)
        XCTAssertGreaterThan(simulation.ball.position.y, simulation.player.position.y)
        XCTAssertGreaterThan(controlledFrames, 110)
        XCTAssertGreaterThan(rollingFrames, 70, "The ball should roll freely between foot touches.")
        XCTAssertGreaterThan(gaps.max()! - gaps.min()!, 0.25, "The ball must not be attached at a fixed offset.")
    }

    func testSharpReversalCanExposeBallAndRunningPlayerCanRecoverIt() {
        var simulation = FootballSimulation()
        simulation.movement = .up
        advance(&simulation, frames: 100)
        simulation.movement = -.up
        var lostControl = false
        for _ in 0..<45 {
            simulation.step(dt: tick)
            lostControl = lostControl || !simulation.hasControl
        }
        XCTAssertTrue(lostControl)
        for _ in 0..<240 {
            simulation.movement = (simulation.ball.position - simulation.player.position).normalized
            simulation.step(dt: tick)
            if simulation.hasControl { break }
        }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.ball.mode, .controlled)
    }

    func testTapHoldBoundaryAndChargeUseReleaseTimestamp() {
        let threshold = GameplayTuning.defaults.holdThreshold
        let cases: [(Double, BallMode, Double)] = [
            (0.1, .pass, GameplayTuning.defaults.knockAheadSpeed),
            (threshold - 0.000001, .pass, GameplayTuning.defaults.knockAheadSpeed),
            (threshold, .shot, GameplayTuning.defaults.shotMinSpeed * 0.9),
            (threshold + GameplayTuning.defaults.fullChargeDuration / 2, .shot,
             (GameplayTuning.defaults.shotMinSpeed + GameplayTuning.defaults.shotMaxSpeed) / 2 * 0.9),
            (10, .shot, GameplayTuning.defaults.shotMaxSpeed * 0.9)
        ]
        for (duration, expectedMode, expectedSpeed) in cases {
            var simulation = FootballSimulation()
            simulation.movement = Vector2(x: 1, y: 0)
            simulation.pressAction()
            // No render step is necessary: release classification uses event time.
            simulation.releaseAction(heldFor: duration)
            XCTAssertEqual(simulation.ball.mode, expectedMode)
            XCTAssertEqual(simulation.ball.velocity.x, expectedSpeed, accuracy: 0.000001)
            XCTAssertEqual(simulation.ball.velocity.y, 0, accuracy: 0.000001)
            XCTAssertEqual(simulation.actionStatus, .idle)
            let velocity = simulation.ball.velocity
            simulation.releaseAction(heldFor: 10)
            XCTAssertEqual(simulation.ball.velocity, velocity, "One press can produce at most one kick.")
        }
    }

    func testChargeFeedbackCapsWithoutAutomaticallyFiring() {
        var simulation = FootballSimulation()
        simulation.pressAction()
        XCTAssertEqual(simulation.actionStatus, .pressed)
        advance(&simulation, frames: 20)
        XCTAssertEqual(simulation.actionStatus, .charging)
        XCTAssertGreaterThan(simulation.chargeFraction, 0)
        advance(&simulation, frames: 100)
        XCTAssertEqual(simulation.chargeFraction, 1)
        XCTAssertEqual(simulation.ball.mode, .controlled)
        XCTAssertEqual(simulation.ball.velocity, .zero)
    }

    func testNeutralReleaseUsesLastFacingAndPassHasNoAftertouch() {
        var simulation = FootballSimulation()
        simulation.player.facing = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.08)
        XCTAssertLessThan(simulation.ball.velocity.x, 0)
        XCTAssertEqual(simulation.ball.velocity.y, 0)
        XCTAssertEqual(simulation.aftertouchRemaining, 0)
    }

    func testCancelledInputCannotFireAndClearsMovementAndCurve() {
        var simulation = FootballSimulation()
        simulation.movement = .up
        simulation.pressAction()
        advance(&simulation, frames: 20)
        simulation.cancelInput()
        let velocity = simulation.ball.velocity
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.ball.velocity, velocity)
        XCTAssertEqual(simulation.movement, .zero)
        XCTAssertEqual(simulation.actionStatus, .idle)
        XCTAssertEqual(simulation.chargeFraction, 0)

        simulation.reset()
        simulation.step(dt: tick)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        XCTAssertGreaterThan(simulation.aftertouchRemaining, 0)
        simulation.cancelInput()
        XCTAssertEqual(simulation.aftertouchRemaining, 0)
        XCTAssertEqual(simulation.aftertouchVector, .zero)
    }

    func testLosingControlCancelsWholePressEvenAfterRecovery() {
        var simulation = FootballSimulation()
        simulation.pressAction()
        simulation.ball.position = Vector2(x: 10, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.actionStatus, .cancelled)
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.actionStatus, .cancelled)
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.ball.mode, .controlled)
        XCTAssertEqual(simulation.ball.velocity, .zero)
    }

    func testOffBallHoldCannotBecomeShotAfterRecoveringBall() {
        var simulation = FootballSimulation()
        simulation.ball.position = Vector2(x: 20, y: 0)
        simulation.pressAction()
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.step(dt: tick)
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertTrue(simulation.isSliding)
        XCTAssertEqual(simulation.slideCount, 1)
    }

    func testKickRequiresReachAsWellAsSoftClaim() {
        var simulation = FootballSimulation()
        simulation.tuning.kickReach = 1
        XCTAssertTrue(simulation.hasControl)
        XCTAssertFalse(simulation.canKick)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.ball.velocity, .zero)
    }

    func testKickedBallEscapesAndCanBeRecoveredLater() {
        var simulation = FootballSimulation()
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        simulation.movement = .up
        for _ in 0..<15 {
            simulation.step(dt: tick)
            XCTAssertFalse(simulation.hasControl)
            XCTAssertEqual(simulation.ball.mode, .pass)
        }
        XCTAssertGreaterThan((simulation.ball.position - simulation.player.position).length, simulation.tuning.queuedPassReach)
        var recovered = false
        for _ in 0..<280 {
            simulation.step(dt: tick)
            if simulation.hasControl {
                recovered = true
                break
            }
        }
        XCTAssertTrue(recovered)
        XCTAssertEqual(simulation.resetGeneration, 0, "Recovery must happen in play, without a restart.")
    }

    func testAftertouchBendsAllShotDirectionsWithoutAddingSpeed() {
        let directions: [Vector2] = [.up, -.up, Vector2(x: 1, y: 1).normalized,
                                     Vector2(x: 1, y: -1).normalized, Vector2(x: -1, y: 0)]
        for direction in directions {
            var straight = FootballSimulation()
            straight.tuning.shotAssistAngle = 0
            straight.movement = direction
            straight.pressAction()
            straight.releaseAction(heldFor: 1)
            var curved = straight
            straight.movement = direction
            curved.movement = direction.perpendicular
            advance(&straight, frames: 35)
            advance(&curved, frames: 35)
            XCTAssertGreaterThan(curved.ball.velocity.normalized.dot(direction.perpendicular), 0.1)
            XCTAssertEqual(straight.ball.velocity.normalized.dot(direction.perpendicular), 0, accuracy: 0.000001)
            XCTAssertEqual(curved.ball.velocity.length, straight.ball.velocity.length, accuracy: 0.000001)
            let angle = acos(min(1, max(-1, curved.ball.velocity.normalized.dot(direction))))
            XCTAssertLessThanOrEqual(angle, curved.tuning.aftertouchMaxAngle * .pi / 180 + 0.000001)
        }
    }

    func testScreenLeftInputBendsBothUpwardAndDownwardShotsLeft() {
        for direction in [Vector2.up, -Vector2.up] {
            var simulation = FootballSimulation()
            simulation.movement = direction
            simulation.pressAction()
            simulation.releaseAction(heldFor: 1)
            simulation.movement = Vector2(x: -1, y: 0)
            advance(&simulation, frames: 20)
            XCTAssertLessThan(simulation.ball.velocity.x, -1)
            XCTAssertGreaterThan(simulation.ball.velocity.dot(direction), 0)
        }
    }

    func testStrongerAftertouchDecayReducesCurveWithoutChangingPower() {
        func shot(decay: Double) -> FootballSimulation {
            var simulation = FootballSimulation()
            simulation.tuning.aftertouchDecay = decay
            simulation.tuning.aftertouchStrength = 0.5
            simulation.pressAction()
            simulation.releaseAction(heldFor: 1)
            simulation.movement = Vector2(x: -1, y: 0)
            advance(&simulation, frames: 35)
            return simulation
        }
        let constant = shot(decay: 0)
        let fading = shot(decay: 4)
        XCTAssertLessThan(constant.ball.velocity.x, fading.ball.velocity.x)
        XCTAssertEqual(constant.ball.velocity.length, fading.ball.velocity.length, accuracy: 0.000001)
    }

    func testAftertouchCoastsShooterThenRestoresExistingStick() {
        var simulation = FootballSimulation()
        simulation.player.velocity = .up * 10
        simulation.ball.velocity = .up * 10
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.player.velocity.x, 0)
        XCTAssertGreaterThan(simulation.player.velocity.y, 0)
        XCTAssertLessThan(simulation.player.velocity.y, 10)
        advance(&simulation, frames: 42)
        XCTAssertEqual(simulation.aftertouchRemaining, 0)
        XCTAssertGreaterThan(simulation.player.velocity.x, 0)
        XCTAssertEqual(simulation.movement, Vector2(x: 1, y: 0))
    }

    func testWholeBallMustCrossLineAndFastGoalsCountOnlyOnce() {
        var simulation = FootballSimulation()
        simulation.tuning.ballFriction = 0
        simulation.ball.position = Vector2(x: 0, y: Pitch.length / 2 + Pitch.ballRadius - 0.01)
        simulation.ball.velocity = .up * 0.5
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.northGoals, 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .goal(north: true))
        advance(&simulation, frames: 10)
        XCTAssertEqual(simulation.northGoals, 1)

        for north in [true, false] {
            var fast = FootballSimulation()
            fast.ball.position = Vector2(x: 0, y: north ? 40 : -40)
            fast.ball.velocity = .up * (north ? 1_500 : -1_500)
            fast.step(dt: tick)
            XCTAssertEqual(fast.phase, .goal(north: north))
            XCTAssertEqual(fast.northGoals + fast.southGoals, 1)
            fast.step(dt: tick)
            XCTAssertEqual(fast.northGoals + fast.southGoals, 1)
        }
    }

    func testSweptPostContactReboundsWithoutGoalAndEndsCurve() {
        var simulation = FootballSimulation()
        simulation.tuning.ballFriction = 0
        simulation.player.position = Vector2(x: Pitch.goalWidth / 2, y: 47.75)
        simulation.ball.position = Vector2(x: Pitch.goalWidth / 2, y: 49)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        XCTAssertGreaterThan(simulation.aftertouchRemaining, 0)
        // Exercise a deliberately extreme swept collision independently of bounded kick power.
        simulation.ball.velocity = .up * 600
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertLessThan(simulation.ball.position.y, Pitch.length / 2)
        XCTAssertEqual(simulation.northGoals, 0)
        XCTAssertEqual(simulation.aftertouchRemaining, 0)
    }

    func testFastWideShotsAndTouchlineCrossingsRestart() {
        let examples: [(Vector2, Vector2)] = [
            (Vector2(x: 8, y: 50), .up * 600),
            (Vector2(x: 33, y: 0), Vector2(x: 600, y: 0)),
            (Vector2(x: -33, y: 0), Vector2(x: -600, y: 0)),
            (Vector2(x: -8, y: -50), -.up * 600)
        ]
        for (position, velocity) in examples {
            var simulation = FootballSimulation()
            simulation.ball.position = position
            simulation.ball.velocity = velocity
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.phase, .outOfPlay)
            XCTAssertEqual(simulation.northGoals + simulation.southGoals, 0)
            advance(&simulation, frames: 70)
            XCTAssertEqual(simulation.phase, .playing)
            XCTAssertEqual(simulation.resetGeneration, 1)
            XCTAssertEqual(simulation.ball.position, BallState().position)
        }
    }

    func testResetClearsTransientStatePreservesScoreAndRequiresFreshPress() {
        var simulation = FootballSimulation()
        simulation.ball.position = Vector2(x: 0, y: 52)
        simulation.ball.velocity = .up * 100
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.northGoals, 1)
        simulation.reset()
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.player.velocity, .zero)
        XCTAssertEqual(simulation.ball.velocity, .zero)
        XCTAssertEqual(simulation.movement, .zero)
        XCTAssertEqual(simulation.aftertouchRemaining, 0)
        XCTAssertEqual(simulation.actionStatus, .idle)
        XCTAssertFalse(simulation.hasControl)
        simulation.step(dt: tick)
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.ball.velocity, .zero)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.ball.mode, .pass)
        simulation.reset(clearScore: true)
        XCTAssertEqual(simulation.northGoals + simulation.southGoals, 0)
        XCTAssertEqual(simulation.resetGeneration, 2)
    }

    func testFixedStepsProduceSameOutcomeAcrossRenderFrameSequences() {
        func simulate(frameTimes: [Double]) -> FootballSimulation {
            var simulation = FootballSimulation()
            var accumulated = 0.0
            var ticks = 0
            for duration in frameTimes {
                accumulated += duration
                while accumulated + 0.000000001 >= tick {
                    if ticks == 0 { simulation.movement = .up }
                    if ticks == 45 { simulation.pressAction() }
                    if ticks == 85 {
                        simulation.releaseAction(heldFor: 40 * tick)
                        simulation.movement = Vector2(x: -1, y: 0)
                    }
                    simulation.step(dt: tick)
                    accumulated -= tick
                    ticks += 1
                }
            }
            XCTAssertEqual(ticks, 150)
            return simulation
        }
        let sixty = simulate(frameTimes: Array(repeating: tick, count: 150))
        let thirty = simulate(frameTimes: Array(repeating: 1.0 / 30, count: 75))
        let irregular = simulate(frameTimes: (0..<75).flatMap { _ in [1.0 / 120, 1.0 / 40] })
        for result in [thirty, irregular] {
            XCTAssertEqual(result.player.position, sixty.player.position)
            XCTAssertEqual(result.ball.position, sixty.ball.position)
            XCTAssertEqual(result.ball.velocity, sixty.ball.velocity)
            XCTAssertEqual(result.phase, sixty.phase)
            XCTAssertEqual(result.northGoals, sixty.northGoals)
        }
    }
}

extension FootballSimulationTests {
    private func freeSolo() -> FootballSimulation {
        var simulation = FootballSimulation()
        simulation.ball.position = Vector2(x: 20, y: -20)
        simulation.step(dt: tick)
        return simulation
    }

    private func redPossessionFixture() -> FootballSimulation {
        var simulation = stationaryExercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.step(dt: tick)
        simulation.roster[3].state.position = Vector2(x: 0, y: 2)
        simulation.ball.position = Vector2(x: 0, y: 1.05)
        simulation.player.position = Vector2(x: 0, y: -0.15)
        simulation.player.facing = .up
        simulation.step(dt: tick)
        return simulation
    }

    private func rearSlideFoulFixture(existingYellows: Int = 0) -> FootballSimulation {
        var simulation = stationaryExercise()
        simulation.roster[1].state.position = Vector2(x: -25, y: -25)
        simulation.roster[2].state.position = Vector2(x: 25, y: -25)
        simulation.roster[3].state.position = Vector2(x: -7, y: 18)
        simulation.roster[3].state.facing = -.up
        simulation.roster[4].state.position = Vector2(x: 25, y: 35)
        simulation.roster[5].state.position = Vector2(x: -25, y: 35)
        simulation.player.position = Vector2(x: -7, y: 20.6)
        simulation.player.velocity = -.up * 16
        simulation.player.facing = -.up
        simulation.roster[0].yellowCards = existingYellows
        simulation.ball.position = Vector2(x: 25, y: 0)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        for _ in 0..<12 {
            simulation.step(dt: tick)
            if simulation.phase != .playing { break }
        }
        return simulation
    }

    func testOffBallRunningIsFasterWhileControlledDribbleKeepsOriginalSpeed() {
        var dribbling = FootballSimulation()
        dribbling.movement = .up
        advance(&dribbling, frames: 60)
        XCTAssertTrue(dribbling.hasControl)
        XCTAssertEqual(dribbling.player.velocity.length, dribbling.tuning.playerMaxSpeed, accuracy: 0.000001)
        var chasing = freeSolo()
        chasing.movement = .up
        advance(&chasing, frames: 60)
        XCTAssertFalse(chasing.hasControl)
        XCTAssertEqual(chasing.player.velocity.length,
                       chasing.tuning.playerMaxSpeed * chasing.tuning.offBallSpeedBoost, accuracy: 0.000001)
    }

    func testExternalHoldClockDoesNotDoubleCountStepsAndSlideUsesVelocity() {
        var simulation = freeSolo()
        simulation.player.velocity = Vector2(x: 5, y: 0)
        simulation.player.facing = .up
        simulation.movement = .up
        simulation.pressAction()
        simulation.updateActionHold(heldFor: simulation.tuning.slideHoldThreshold - 0.000001)
        simulation.step(dt: tick)
        XCTAssertFalse(simulation.isSliding, "A fixed step must not add time to a timestamp-owned press.")
        let expected = simulation.player.velocity.normalized
        simulation.updateActionHold(heldFor: simulation.tuning.slideHoldThreshold)
        simulation.step(dt: tick)
        XCTAssertTrue(simulation.isSliding)
        XCTAssertEqual(simulation.player.velocity.normalized.x, expected.x, accuracy: 0.000001)
        XCTAssertEqual(simulation.player.velocity.normalized.y, expected.y, accuracy: 0.000001)
        XCTAssertEqual(simulation.chargeFraction, 0)
        simulation.releaseAction(heldFor: 0.35)
        XCTAssertEqual(simulation.slideCount, 1)
        XCTAssertEqual(simulation.kickCount, 0)
        advance(&simulation, frames: 20)
        XCTAssertEqual(simulation.actionStatus, .recovering, "Solo shares slide recovery feedback.")
    }

    func testShortTapNearOpponentBallDoesNotPerformAStandingTackle() {
        for facing in [Vector2.up, -Vector2.up] {
            var simulation = redPossessionFixture()
            simulation.player.facing = facing
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.05)
            XCTAssertEqual(simulation.standingTackleCount, 0)
            XCTAssertEqual(simulation.slideCount, 0)
            XCTAssertEqual(simulation.kickCount, 0)
            XCTAssertEqual(simulation.queuedActionRemaining, 0)
            XCTAssertEqual(simulation.ball.velocity.length, 0, accuracy: 0.000001)
            XCTAssertEqual(simulation.possessionTeam, .red)
        }
    }

    func testRunningIntoTheFrontOfATightDribbleWinsWithoutAButton() {
        var simulation = redPossessionFixture()
        simulation.player.position = simulation.ball.position - .up * 1.4
        simulation.player.velocity = .up * 4
        simulation.movement = .up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.runningChallengeCount, 1)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.foulCount, 0)
    }

    func testPassiveAcquisitionCannotSaveBallUsingFuturePlayerPosition() {
        var simulation = FootballSimulation(mode: .passing)
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = Vector2(x: Double(id) * 3 - 8, y: -35 - Double(id))
            simulation.roster[id].state.velocity = .zero
        }
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        simulation.player.position = Vector2(x: Pitch.width / 2 - Pitch.playerRadius, y: -0.55)
        simulation.player.velocity = .up * 8
        simulation.player.facing = .up
        simulation.movement = .up
        simulation.ball.position = Vector2(x: 34.2, y: 0)
        simulation.ball.velocity = Vector2(x: 12, y: 0)
        simulation.ball.mode = .free
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .outOfPlay)
        XCTAssertNil(simulation.possessionTeam)
        XCTAssertEqual(simulation.ball.position.x, Pitch.width / 2 + Pitch.ballRadius, accuracy: 0.000001)
    }

    func testExposedBallStillRequiresAnIntentionalRunToSteal() {
        for running in [true, false] {
            var simulation = redPossessionFixture()
            simulation.ball.position = simulation.roster[3].state.position - .up * (simulation.tuning.dribbleReach + 0.25)
            simulation.ball.velocity = .zero
            simulation.player.position = simulation.ball.position - .up
            simulation.player.velocity = running ? .up * 4 : .zero
            simulation.player.facing = .up
            simulation.movement = running ? .up : .zero
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.possessionTeam, running ? .blue : .red)
            XCTAssertEqual(simulation.hasControl, running)
            XCTAssertEqual(simulation.runningChallengeCount, running ? 1 : 0)
            XCTAssertEqual(simulation.tackleCount, 0)
            XCTAssertEqual(simulation.kickCount, 0)
        }
    }

    func testNaturalRearChaseCanWinBeforeTheCarrierPasses() {
        var simulation = redPossessionFixture()
        simulation.tuning.aiSpeedScale = GameplayTuning.defaults.aiSpeedScale
        simulation.roster[3].state.position = .zero
        simulation.roster[3].state.facing = -.up
        simulation.roster[3].state.velocity = -.up * 8.5
        simulation.player.position = .up * 1.6
        simulation.player.facing = -.up
        simulation.player.velocity = -.up * 10.5
        simulation.movement = -.up
        simulation.ball.position = -.up * 1.2
        simulation.ball.velocity = -.up * 8.5
        for id in [1, 2, 4, 5] { simulation.roster[id].state.position = Vector2(x: id % 2 == 0 ? 25 : -25, y: 35) }
        var sawPressure = false
        for _ in 0..<45 where !simulation.hasControl {
            simulation.movement = (simulation.roster[3].state.position - simulation.player.position).normalized
            simulation.step(dt: tick)
            sawPressure = sawPressure || simulation.isPressingFromBehind
        }
        XCTAssertTrue(sawPressure)
        XCTAssertTrue(simulation.hasControl, "A real chase must survive normal AI movement, shielding and dribble nudges.")
        XCTAssertEqual(simulation.runningChallengeCount, 1)
        XCTAssertEqual(simulation.foulCount, 0)
    }

    func testRunningChallengeCompetesWithWholeBallBoundaryCrossing() {
        for arrivesBeforeCrossing in [true, false] {
            var simulation = redPossessionFixture()
            simulation.tuning.dribbleReach = 0.1 // Isolate the challenge from a carrier's nudge.
            simulation.roster[3].state.position = Vector2(x: 33.28, y: 0)
            simulation.roster[3].state.facing = .up
            simulation.roster[3].state.velocity = .zero
            simulation.ball.position = Vector2(x: 34.2, y: 0)
            simulation.ball.velocity = Vector2(x: 12, y: 0)
            simulation.player.position = Vector2(x: 33.28, y: arrivesBeforeCrossing ? 1.5 : 2.3)
            simulation.player.velocity = -.up * 8
            simulation.movement = -.up
            simulation.step(dt: 0.1)
            XCTAssertEqual(simulation.phase, arrivesBeforeCrossing ? .playing : .outOfPlay)
            XCTAssertEqual(simulation.runningChallengeCount, arrivesBeforeCrossing ? 1 : 0)
        }
    }

    func testCleanRunningWinCannotImmediatelyPingPongBackThroughAnAIPoke() {
        var simulation = redPossessionFixture()
        simulation.player.position = simulation.ball.position - .up * 1.4
        simulation.player.velocity = .up * 4
        simulation.movement = .up
        simulation.step(dt: tick)
        XCTAssertTrue(simulation.hasControl)
        let carrier = simulation.roster[3].state
        for _ in 0..<12 {
            // Keep the former carrier near the ball, facing it, while the new owner controls it.
            simulation.roster[3].state.position = simulation.ball.position + .up * 1.2
            simulation.roster[3].state.facing = -.up
            simulation.roster[3].state.velocity = carrier.velocity
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.possessionTeam, .blue)
            XCTAssertEqual(simulation.phase, .playing)
        }
        XCTAssertEqual(simulation.runningChallengeCount, 1)
        XCTAssertEqual(simulation.foulCount, 0)
    }

    func testQueuedPassWaitsForPhysicalContactAndExecutesOnce() {
        var simulation = freeSolo()
        simulation.ball.position = simulation.player.position + .up * 5
        simulation.ball.velocity = -.up * 8
        simulation.movement = .up
        let requestedAt = simulation.ball.position
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertGreaterThan(simulation.queuedActionRemaining, 0)
        XCTAssertEqual(simulation.queuedActionKind, "pass")
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.ball.position, requestedAt)
        for _ in 0..<40 {
            simulation.step(dt: tick)
            if simulation.kickCount == 1 { break }
        }
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.queuedActionRemaining, 0)
        XCTAssertGreaterThan(simulation.ball.velocity.y, 0)
        XCTAssertLessThan((simulation.ball.position - simulation.player.position).length, 1.8)
        advance(&simulation, frames: 20)
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testQueuedPassKeepsRequestedAimAndExpiresWithoutContact() {
        var simulation = freeSolo()
        simulation.ball.position = simulation.player.position + Vector2(x: 4, y: 0)
        simulation.ball.velocity = Vector2(x: -10, y: 0)
        simulation.player.velocity = Vector2(x: 3, y: 0)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        simulation.movement = Vector2(x: 1, y: 0)
        for _ in 0..<40 {
            simulation.step(dt: tick)
            if simulation.kickCount == 1 { break }
        }
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertGreaterThan(simulation.ball.velocity.y, abs(simulation.ball.velocity.x))

        simulation = freeSolo()
        simulation.ball.position = simulation.player.position + .up * 5
        simulation.ball.velocity = -.up * 8
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertGreaterThan(simulation.queuedActionRemaining, 0)
        simulation.ball.position = Vector2(x: 25, y: 25)
        simulation.ball.velocity = .zero
        simulation.movement = .zero
        advance(&simulation, frames: Int(ceil(simulation.tuning.queuedPassDuration / tick)) + 1)
        XCTAssertEqual(simulation.queuedActionRemaining, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.ball.position = simulation.player.position + .up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.kickCount, 0, "An expired request cannot become a delayed ghost kick.")
    }

    func testQueuedBoundaryClearanceOccursBeforeWholeBallCrossing() {
        var simulation = freeSolo()
        simulation.player.position = Vector2(x: 31.8, y: 0)
        simulation.player.velocity = Vector2(x: 11.76, y: 0)
        simulation.player.facing = Vector2(x: 1, y: 0)
        simulation.ball.position = Vector2(x: 33.5, y: 0)
        simulation.ball.velocity = Vector2(x: 6, y: 0)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertGreaterThan(simulation.queuedActionRemaining, 0)
        for _ in 0..<10 {
            simulation.step(dt: tick)
            if simulation.kickCount > 0 || simulation.phase != .playing { break }
        }
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertLessThan(simulation.ball.velocity.x, 0, "A stretched-foot clearance redirects an outward aim back into play.")

        simulation = freeSolo()
        simulation.player.position = Vector2(x: 33, y: 0)
        simulation.ball.position = Vector2(x: 34.5, y: 0)
        simulation.ball.velocity = .zero
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .outOfPlay)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testSlideCanSaveBoundaryBallButCannotUndoEarlierCrossing() {
        var simulation = freeSolo()
        simulation.player.position = Vector2(x: 31.8, y: 0)
        simulation.player.velocity = Vector2(x: 8, y: 0)
        simulation.ball.position = Vector2(x: 33.5, y: 0)
        simulation.ball.velocity = Vector2(x: 6, y: 0)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        for _ in 0..<8 {
            simulation.step(dt: tick)
            if simulation.ball.velocity.x < 0 || simulation.phase != .playing { break }
        }
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertLessThan(simulation.ball.velocity.x, 0)
        XCTAssertEqual(simulation.slideCount, 1)
        XCTAssertEqual(simulation.kickCount, 0)

        simulation = freeSolo()
        simulation.player.position = Vector2(x: 31.8, y: 0)
        simulation.player.velocity = Vector2(x: 8, y: 0)
        simulation.ball.position = Vector2(x: 34.2, y: 0)
        simulation.ball.velocity = Vector2(x: 20, y: 0)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .outOfPlay)
        XCTAssertEqual(simulation.resetGeneration, 0)
    }

    func testPullingBackChipsPassesAndShotsOnlyOnceInsideWindow() {
        for hold in [0.05, 1.0] {
            var simulation = FootballSimulation()
            simulation.movement = .up
            simulation.pressAction()
            simulation.releaseAction(heldFor: hold)
            let horizontalSpeed = simulation.ball.velocity.length
            XCTAssertGreaterThan(simulation.chipWindowRemaining, 0)
            simulation.movement = -.up
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.chipCount, 1)
            XCTAssertGreaterThan(simulation.ball.height, 0)
            XCTAssertGreaterThan(simulation.ball.verticalVelocity, 0)
            XCTAssertEqual(simulation.ball.velocity.length, horizontalSpeed, accuracy: 0.000001)
            advance(&simulation, frames: 20)
            XCTAssertEqual(simulation.chipCount, 1)
        }
        var late = FootballSimulation()
        late.pressAction()
        late.releaseAction(heldFor: 0.05)
        advance(&late, frames: 20)
        late.movement = -.up
        late.step(dt: tick)
        XCTAssertEqual(late.chipCount, 0)
        XCTAssertEqual(late.ball.height, 0)
    }

    func testAirborneBallClearsGroundPlayerAndGoalChecksCrossbarHeightAtCrossing() {
        var simulation = stationaryExercise()
        let opponent = simulation.roster[3].state.position
        simulation.ball.position = opponent - .up * 2
        simulation.ball.velocity = .up * 45
        simulation.ball.height = 1.5
        advance(&simulation, frames: 6)
        XCTAssertGreaterThan(simulation.ball.position.y, opponent.y)
        XCTAssertGreaterThan(simulation.ball.velocity.y, 0)
        XCTAssertNil(simulation.possessionTeam)

        for (height, expected) in [(1.0, SandboxPhase.goal(north: true)), (2.2, .outOfPlay)] {
            var crossing = FootballSimulation()
            crossing.ball.position = Vector2(x: 0, y: 52)
            crossing.ball.velocity = .up * 100
            crossing.ball.height = height
            crossing.ball.verticalVelocity = 2
            crossing.step(dt: tick)
            XCTAssertEqual(crossing.phase, expected)
            let crossingTime = (Pitch.length / 2 + Pitch.ballRadius - 52) / 100
            XCTAssertEqual(crossing.ball.height, height + 2 * crossingTime - 0.5 * crossing.tuning.ballGravity * crossingTime * crossingTime,
                           accuracy: 0.000001)
        }
    }

    func testNearestSelectionUsesActualBallAndExcludesGoalkeepersAndDismissals() {
        var simulation = stationaryExercise()
        simulation.tuning.switchCandidateDuration = 0
        simulation.roster[0].state.position = .zero
        simulation.roster[1].state.position = Vector2(x: 5, y: 0)
        simulation.roster[2].state.position = Vector2(x: 15, y: 0)
        simulation.ball.position = Vector2(x: 12, y: 0)
        simulation.ball.velocity = Vector2(x: -40, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 2, "Prediction must not outweigh actual ball distance.")
        simulation.roster[2].isGoalkeeper = true
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.roster[1].isSentOff = true
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
    }

    func testSlideFoulAwardsFreeKickAndSecondYellowDismissesOffender() {
        var first = rearSlideFoulFixture()
        XCTAssertEqual(first.phase, .foulContact(team: .red))
        advance(&first, frames: Int(ceil(first.tuning.foulContactDuration / tick)))
        XCTAssertEqual(first.phase, .freeKick(team: .red))
        XCTAssertEqual(first.foulCount, 1)
        XCTAssertEqual(first.lastFoul?.offenderID, 0)
        XCTAssertEqual(first.lastFoul?.victimID, 3)
        XCTAssertEqual(first.lastFoul?.card, .yellow)
        XCTAssertEqual(first.roster[0].yellowCards, 1)
        XCTAssertFalse(first.roster[0].isSentOff)
        XCTAssertEqual(first.ball.velocity, .zero)
        XCTAssertEqual(first.ball.height, 0)

        var second = rearSlideFoulFixture(existingYellows: 1)
        advance(&second, frames: Int(ceil(second.tuning.foulContactDuration / tick)))
        XCTAssertEqual(second.lastFoul?.card, .red)
        XCTAssertTrue(second.roster[0].isSentOff)
        XCTAssertEqual(second.roster[0].yellowCards, 2)
        advance(&second, frames: Int(ceil(second.tuning.freeKickDelay / tick)) + 5)
        XCTAssertNotEqual(second.selectedPlayerID, 0)
        XCTAssertTrue(second.roster[0].isSentOff)
    }

    func testBallFirstSlideIsCleanAndRedFreeKickResumesAutomatically() {
        var clean = stationaryExercise()
        clean.ball.position = Vector2(x: 25, y: -25)
        clean.step(dt: tick)
        clean.player.position = Vector2(x: -7, y: 14)
        clean.player.velocity = .zero
        clean.ball.position = Vector2(x: -7, y: 16.8)
        clean.ball.velocity = .zero
        clean.pressAction()
        clean.updateActionHold(heldFor: 0.3)
        XCTAssertTrue(clean.isSliding)
        advance(&clean, frames: 10)
        XCTAssertEqual(clean.foulCount, 0)
        XCTAssertEqual(clean.phase, .playing)

        var foul = rearSlideFoulFixture()
        advance(&foul, frames: Int(ceil((foul.tuning.foulContactDuration + foul.tuning.freeKickDelay + 0.7) / tick)))
        XCTAssertEqual(foul.phase, .playing)
        XCTAssertGreaterThan(foul.ball.velocity.length, 0)
        XCTAssertEqual(foul.kickCount, 0)
        XCTAssertEqual(foul.roster[0].yellowCards, 1)
    }

    func testBlueFreeKickWaitsForFreshActionAndOpponentsStandBack() {
        var simulation = stationaryExercise()
        simulation.tuning.tackleReach = 3
        simulation.player.position = .zero
        simulation.ball.position = .up * 1.25
        simulation.roster[3].state.position = Vector2(x: 0, y: -1.5)
        simulation.roster[3].state.facing = .up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        advance(&simulation, frames: Int(ceil((simulation.tuning.foulContactDuration + simulation.tuning.freeKickDelay) / tick)) + 2)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertTrue(simulation.hasControl)
        let spot = simulation.ball.position
        for opponent in simulation.roster where opponent.team == .red && !opponent.isSentOff {
            XCTAssertGreaterThanOrEqual((opponent.state.position - spot).length, simulation.tuning.freeKickStandBack - 0.01)
        }
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 90)
        XCTAssertEqual(simulation.ball.position, spot)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertGreaterThan(simulation.ball.velocity.length, 0)
    }

    func testAutomaticRestartsKeepDisciplineAndManualResetClearsIt() {
        var simulation = stationaryExercise()
        simulation.roster[0].yellowCards = 2
        simulation.roster[0].isSentOff = true
        simulation.roster[3].yellowCards = 1
        simulation.ball.position = Vector2(x: 0, y: 52)
        simulation.ball.velocity = .up * 100
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .goal(north: true))
        advance(&simulation, frames: 70)
        XCTAssertTrue(simulation.roster[0].isSentOff)
        XCTAssertEqual(simulation.roster[3].yellowCards, 1)
        XCTAssertNotEqual(simulation.selectedPlayerID, 0)
        simulation.reset()
        XCTAssertTrue(simulation.roster.allSatisfy { !$0.isSentOff && $0.yellowCards == 0 })
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertEqual(simulation.chipWindowRemaining, 0)
        XCTAssertEqual(simulation.queuedActionRemaining, 0)
    }

    func testNoEligiblePlayersEndsPracticeUntilManualReset() {
        var simulation = stationaryExercise()
        for id in 0..<3 { simulation.roster[id].isSentOff = true }
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .practiceEnded(losingTeam: .blue))
        let generation = simulation.resetGeneration
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 180)
        XCTAssertEqual(simulation.phase, .practiceEnded(losingTeam: .blue))
        XCTAssertEqual(simulation.resetGeneration, generation)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.reset()
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertTrue(simulation.hasControl)
    }
}

extension FootballSimulationTests {
    private func stationaryExercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        return FootballSimulation(tuning: tuning, mode: .passing)
    }

    func testPassingExerciseStartsThreeAgainstThreeWithTimeToMakeFirstPass() {
        var simulation = FootballSimulation(mode: .passing)
        XCTAssertEqual(simulation.footballers.count, 6)
        XCTAssertEqual(simulation.footballers.filter { $0.team == .blue }.count, 3)
        XCTAssertEqual(simulation.footballers.filter { $0.team == .red }.count, 3)
        XCTAssertEqual(Set(simulation.footballers.map(\.id)).count, 6)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertTrue(simulation.hasControl)
        advance(&simulation, frames: 120)
        XCTAssertTrue(simulation.hasControl, "The opening must leave enough time to aim a first pass.")
        XCTAssertEqual(simulation.possessionTeam, .blue)
    }

    func testDirectionalPassConePrefersAimOverNearestAndAllowsOpenSpace() {
        var simulation = stationaryExercise()
        simulation.movement = .up
        XCTAssertEqual(simulation.passTargetID, 2, "The slightly farther right teammate lies inside the upward cone.")
        simulation.movement = Vector2(x: -1, y: 1).normalized
        XCTAssertEqual(simulation.passTargetID, 1)
        simulation.movement = -.up
        XCTAssertNil(simulation.passTargetID)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertNil(simulation.passTargetID)
        XCTAssertEqual(simulation.ball.velocity.x, 0, accuracy: 0.000001)
        XCTAssertLessThan(simulation.ball.velocity.y, 0, "An empty cone keeps the user's manual kick direction.")
    }

    func testAssistedPassLeadsMovingReceiverAndGoalDirectedShotGetsGoalAssist() {
        var simulation = FootballSimulation(mode: .passing)
        advance(&simulation, frames: 20)
        let receiver = simulation.footballers[1].state
        XCTAssertGreaterThan(receiver.velocity.length, 0.1)
        let direct = (receiver.position - simulation.ball.position).normalized
        simulation.movement = (receiver.position - simulation.player.position).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.passTargetID, 1)
        let assisted = simulation.ball.velocity.normalized
        XCTAssertGreaterThan((assisted - direct).dot(receiver.velocity), 0)

        simulation.reset()
        simulation.player.position = Vector2(x: 0, y: 30)
        simulation.ball.position = simulation.player.position + .up * 1.25
        let aim = Vector2(x: 0.15, y: 1).normalized
        simulation.movement = aim
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        let goalCrossingX = simulation.ball.position.x + simulation.ball.velocity.x / simulation.ball.velocity.y
            * (Pitch.length / 2 - simulation.ball.position.y)
        XCTAssertGreaterThan(goalCrossingX, 0, "Rough rightward goal aim retains the requested corner.")
        XCTAssertLessThan(goalCrossingX, Pitch.goalWidth / 2 - Pitch.ballRadius)
        XCTAssertEqual(simulation.lastKickKind, "shot")
        XCTAssertNil(simulation.passTargetID)
    }

    func testAssistedPassIsReceivedThroughContactAndSelectionFollowsReceiver() {
        var simulation = stationaryExercise()
        let target = simulation.footballers[1].state.position
        simulation.movement = (target - simulation.player.position).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        simulation.movement = .zero
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.passTargetID, 1)
        var received = false
        for _ in 0..<120 {
            simulation.step(dt: tick)
            if simulation.hasControl, simulation.selectedPlayerID == 1 {
                received = true
                break
            }
        }
        XCTAssertTrue(received)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertEqual(simulation.ball.mode, .controlled)
        XCTAssertLessThan((simulation.ball.position - simulation.player.position).length, simulation.tuning.controlReleaseDistance,
                          "The receiver meets the pass and cushions it at his actual receiving position.")
        XCTAssertGreaterThan((simulation.player.position - target).length, 1,
                             "Neutral assistance should move to meet this led delivery.")
        XCTAssertEqual(simulation.switchCount, 1)
        XCTAssertEqual(simulation.resetGeneration, 0)
    }

    func testOpponentCanInterceptFastPassAtPhysicalContact() {
        var simulation = stationaryExercise()
        let defender = simulation.footballers[3].state.position
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        simulation.ball.position = defender - .up * 3
        simulation.ball.velocity = .up * simulation.tuning.passSpeed
        simulation.ball.mode = .pass
        var intercepted = false
        for _ in 0..<20 {
            simulation.step(dt: tick)
            if simulation.possessionTeam == .red {
                intercepted = true
                break
            }
        }
        XCTAssertTrue(intercepted)
        XCTAssertEqual(simulation.ball.mode, .controlled)
        XCTAssertLessThan((simulation.ball.position - defender).length, 1.3)
        XCTAssertGreaterThan(simulation.ball.velocity.y, 0, "A pass is cushioned at contact rather than teleported or reflected.")
    }

    func testFastLowShotDeflectsOffOpponentAndImmediatelyEndsAftertouch() {
        var simulation = stationaryExercise()
        simulation.player.position = Vector2(x: -7, y: 12.5)
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        XCTAssertGreaterThan(simulation.aftertouchRemaining, 0)
        // Isolate a fast low-ball contact; a normal held clearance can now fly over this player.
        simulation.ball.verticalVelocity = 0
        var contacted = false
        for _ in 0..<15 {
            simulation.step(dt: tick)
            if simulation.aftertouchRemaining == 0 {
                contacted = true
                break
            }
        }
        XCTAssertTrue(contacted)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertEqual(simulation.phase, .playing)
    }

    func testOffBallHoldCommitsSlideOnceAndReleaseNeverShoots() {
        var simulation = stationaryExercise()
        simulation.ball.position = simulation.player.position + .up * 5
        simulation.step(dt: tick)
        simulation.ball.position = simulation.player.position + .up * 2.8
        simulation.pressAction()
        XCTAssertFalse(simulation.isTackling)
        simulation.updateActionHold(heldFor: simulation.tuning.slideHoldThreshold - 0.000001)
        XCTAssertFalse(simulation.isSliding)
        XCTAssertEqual(simulation.chargeFraction, 0)
        simulation.updateActionHold(heldFor: simulation.tuning.slideHoldThreshold)
        XCTAssertTrue(simulation.isSliding)
        XCTAssertEqual(simulation.actionStatus, .sliding)
        simulation.updateActionHold(heldFor: 1)
        XCTAssertEqual(simulation.slideCount, 1)
        advance(&simulation, frames: 7)
        XCTAssertGreaterThan(simulation.ball.velocity.y, 10)
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testMissedSlideHasRecoveryPinsSelectionAndCannotBufferKick() {
        var simulation = stationaryExercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        advance(&simulation, frames: 20)
        XCTAssertFalse(simulation.isTackling)
        XCTAssertEqual(simulation.actionStatus, .recovering)
        let selected = simulation.selectedPlayerID
        simulation.ball.position = simulation.footballers[1].state.position + .up * 0.95
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, selected)
        simulation.releaseAction(heldFor: 1)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 1)
        XCTAssertEqual(simulation.slideCount, 1)
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.kickCount, 0)
        advance(&simulation, frames: 100)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
    }

    func testActionPressedDuringCurveDoesNotTackleOrQueueLunge() {
        var simulation = stationaryExercise()
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        let shooter = simulation.selectedPlayerID
        simulation.pressAction()
        XCTAssertEqual(simulation.actionStatus, .cancelled)
        XCTAssertFalse(simulation.isTackling)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertGreaterThan(simulation.aftertouchRemaining, 0)
        advance(&simulation, frames: 20)
        XCTAssertEqual(simulation.selectedPlayerID, shooter)
        advance(&simulation, frames: 30)
        XCTAssertEqual(simulation.tackleCount, 0)
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertFalse(simulation.isTackling)
    }

    func testNeutralSelectionQuicklyFindsRelevantPlayerAndDoesNotFlickerAtTie() {
        var simulation = stationaryExercise()
        simulation.ball.position = Vector2(x: 0, y: 6)
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        for frame in 0..<150 {
            simulation.ball.position = Vector2(x: frame.isMultiple(of: 2) ? -0.15 : 0.15, y: 3.5)
            simulation.ball.velocity = .zero
            simulation.step(dt: tick)
        }
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertEqual(simulation.switchCount, 1)
        simulation.ball.position = Vector2(x: -8, y: 2)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "A remote neutral selection should recover on the next tick.")
    }

    func testAIRecoversBallNearGoalLineAndTouchline() {
        for position in [Vector2(x: -12, y: 52), Vector2(x: 33.5, y: 22)] {
            var simulation = FootballSimulation(mode: .passing)
            simulation.ball.position = position
            simulation.ball.velocity = .zero
            var reached = false
            for _ in 0..<360 {
                simulation.step(dt: tick)
                if simulation.possessionTeam == .red || simulation.phase != .playing {
                    reached = true
                    break
                }
            }
            XCTAssertTrue(reached, "A chaser must leave its formation inset to recover a boundary ball at \(position).")
        }
    }

    func testRedPlayersPressWinBallAndAttackWithoutHumanInput() {
        var simulation = FootballSimulation(mode: .passing)
        var redControlled = false
        var redShot = false
        for _ in 0..<1_200 {
            simulation.step(dt: tick)
            redControlled = redControlled || simulation.possessionTeam == .red
            redShot = redShot || simulation.ball.mode == .shot
        }
        XCTAssertTrue(redControlled, "Standing still should let opponents pressure and win an exposed ball.")
        XCTAssertTrue(redShot, "Red possession should advance into an attacking shot opportunity.")
        XCTAssertEqual(simulation.kickCount, 0, "AI actions do not increment the human input diagnostic.")
    }

    func testExerciseModeChangesAndResetsClearRosterTransientState() {
        var simulation = FootballSimulation(mode: .passing)
        simulation.ball.position = Vector2(x: 30, y: 0)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.35)
        XCTAssertTrue(simulation.isSliding)
        simulation.reset()
        XCTAssertEqual(simulation.footballers.count, 6)
        XCTAssertFalse(simulation.isTackling)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.actionStatus, .idle)
        XCTAssertEqual(simulation.movement, .zero)
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.setMode(.solo)
        XCTAssertEqual(simulation.footballers.count, 1)
        XCTAssertEqual(simulation.mode, .solo)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertNil(simulation.passTargetID)
        simulation.setMode(.passing)
        XCTAssertEqual(simulation.footballers.count, 6)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.resetGeneration, 3)
    }

    func testPassingExerciseIsDeterministicOverExtendedMixedInput() {
        func run() -> FootballSimulation {
            var simulation = FootballSimulation(mode: .passing)
            for frame in 0..<1_800 {
                if frame.isMultiple(of: 180) {
                    simulation.movement = Vector2(x: frame.isMultiple(of: 360) ? -0.5 : 0.5, y: 1).normalized
                }
                if frame % 180 == 30 { simulation.pressAction() }
                if frame % 180 == 35 { simulation.releaseAction(heldFor: 0.08) }
                if frame % 180 == 90 { simulation.pressAction() }
                if frame % 180 == 140 { simulation.releaseAction(heldFor: 0.83) }
                simulation.step(dt: tick)
                XCTAssertTrue(simulation.ball.position.x.isFinite && simulation.ball.position.y.isFinite)
                XCTAssertEqual(simulation.footballers[simulation.selectedPlayerID].team, .blue)
            }
            return simulation
        }
        let first = run()
        let second = run()
        XCTAssertEqual(first.ball.position, second.ball.position)
        XCTAssertEqual(first.ball.velocity, second.ball.velocity)
        XCTAssertEqual(first.selectedPlayerID, second.selectedPlayerID)
        XCTAssertEqual(first.switchCount, second.switchCount)
        XCTAssertEqual(first.northGoals, second.northGoals)
        XCTAssertEqual(first.southGoals, second.southGoals)
        for id in first.footballers.indices {
            XCTAssertEqual(first.footballers[id].state.position, second.footballers[id].state.position)
            XCTAssertEqual(first.footballers[id].state.velocity, second.footballers[id].state.velocity)
        }
    }

    func testTenMinuteExerciseRemainsFiniteAndDoesNotStrandBoundaryBalls() {
        var simulation = FootballSimulation(mode: .passing)
        var boundaryStall = 0
        var longestBoundaryStall = 0
        var sawRedControl = false
        for frame in 0..<36_000 {
            if case .practiceEnded = simulation.phase { simulation.reset() }
            if simulation.aftertouchRemaining > 0 {
                simulation.movement = Vector2(x: frame.isMultiple(of: 2) ? -0.6 : 0.6, y: 0)
            } else if simulation.hasControl {
                simulation.movement = (Vector2(x: 0, y: Pitch.length / 2) - simulation.player.position).normalized
            } else {
                simulation.movement = (simulation.ball.position - simulation.player.position).normalized
            }
            if frame % 150 == 10 { simulation.pressAction() }
            if frame % 150 == 15 { simulation.releaseAction(heldFor: 0.08) }
            if frame % 150 == 55 { simulation.pressAction() }
            if frame % 150 == 105 { simulation.releaseAction(heldFor: 0.83) }
            if frame % 1_800 == 1_799 { simulation.cancelInput() }
            simulation.step(dt: tick)

            XCTAssertTrue(simulation.ball.position.x.isFinite && simulation.ball.position.y.isFinite)
            XCTAssertTrue(simulation.ball.velocity.x.isFinite && simulation.ball.velocity.y.isFinite)
            XCTAssertLessThanOrEqual(abs(simulation.ball.position.x), Pitch.width / 2 + Pitch.ballRadius + 0.001)
            XCTAssertLessThanOrEqual(abs(simulation.ball.position.y), Pitch.length / 2 + Pitch.ballRadius + 0.001)
            XCTAssertLessThanOrEqual(simulation.ball.velocity.length, simulation.tuning.shotMaxSpeed + 2 * simulation.tuning.tackleSpeed)
            for footballer in simulation.footballers {
                XCTAssertTrue(footballer.state.position.x.isFinite && footballer.state.position.y.isFinite)
                XCTAssertLessThanOrEqual(abs(footballer.state.position.x), Pitch.width / 2 - Pitch.playerRadius + 0.001)
                XCTAssertLessThanOrEqual(abs(footballer.state.position.y), Pitch.length / 2 - Pitch.playerRadius + 0.001)
                XCTAssertLessThanOrEqual(footballer.state.velocity.length,
                                        max(simulation.tuning.playerMaxSpeed * simulation.tuning.offBallSpeedBoost, simulation.tuning.slideSpeed) + 0.001)
            }
            sawRedControl = sawRedControl || simulation.possessionTeam == .red
            let nearBoundary = abs(simulation.ball.position.x) > Pitch.width / 2 - 1.2
                || abs(simulation.ball.position.y) > Pitch.length / 2 - 1.2
            if simulation.phase == .playing, nearBoundary, simulation.ball.velocity.length < 0.15 {
                boundaryStall += 1
                longestBoundaryStall = max(longestBoundaryStall, boundaryStall)
            } else { boundaryStall = 0 }
        }
        XCTAssertTrue(sawRedControl)
        XCTAssertGreaterThan(simulation.kickCount, 10)
        XCTAssertGreaterThan(simulation.tackleCount, 10)
        XCTAssertGreaterThan(simulation.resetGeneration, 5)
        XCTAssertLessThan(longestBoundaryStall, 8 * 60, "A legal boundary ball should remain reachable by a chaser.")
    }
}


extension FootballSimulationTests {
    func testOnlyAmbiguousDirectionalOptionsRequireOneContinuousShortConfirmation() {
        var simulation = stationaryExercise()
        simulation.tuning.playerAcceleration = 0 // Isolate selection timing from player acceleration.
        simulation.player.position = Vector2(x: 0, y: -10)
        simulation.roster[1].state.position = Vector2(x: -1, y: -5)
        simulation.roster[2].state.position = Vector2(x: 1, y: -6)
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.movement = .up
        advance(&simulation, frames: 2)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        simulation.roster[1].state.position.y = -6
        simulation.roster[2].state.position.y = -5
        advance(&simulation, frames: 2)
        XCTAssertEqual(simulation.selectedPlayerID, 0, "Ambiguous different candidates cannot pool their confirmation time.")
        simulation.roster[1].state.position.y = -5
        simulation.roster[2].state.position.y = -6
        advance(&simulation, frames: 3)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.switchCount, 1)
    }

    func testClearJoystickReversalSelectsIntendedPlayerDespiteRecentSwitchCooldown() {
        var simulation = stationaryExercise()
        simulation.player.position = Vector2(x: -4, y: 0)
        simulation.roster[1].state.position = Vector2(x: 8, y: 0)
        simulation.roster[2].state.position = Vector2(x: 25, y: 25)
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        let selectedAt = simulation.roster[1].state.position
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0, "A clear reversal must bypass the previous selection's cooldown.")
        XCTAssertGreaterThan(simulation.roster[0].state.position.x, -4)
        XCTAssertEqual(simulation.switchCount, 2)
        XCTAssertLessThan(selectedAt.x, 8, "The first selected player already responded during its selection tick.")
    }

    func testPerfectlyAlignedRemoteCurrentPlayerCannotBypassNearbySelectionGate() {
        var simulation = stationaryExercise()
        simulation.player.position = Vector2(x: 0, y: -30)
        simulation.roster[1].state.position = Vector2(x: 0, y: 4)
        simulation.roster[2].state.position = Vector2(x: 20, y: 20)
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.movement = .up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.possessionTeam, nil)
    }

    func testDirectionalActionTapCannotUndoSelectionWhenJoystickLiftsBeforeRelease() {
        var simulation = stationaryExercise()
        simulation.player.position = Vector2(x: -4, y: 0)
        simulation.roster[1].state.position = Vector2(x: 8, y: 0)
        simulation.roster[2].state.position = Vector2(x: 25, y: 25)
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.slideCount, 0)
    }

    func testDirectionalSelectionWaitsForActiveSlideButCanLeaveItsRecovery() {
        var simulation = stationaryExercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        XCTAssertTrue(simulation.roster[0].isSliding)
        simulation.roster[1].state.position = Vector2(x: 8, y: 0)
        simulation.roster[2].state.position = Vector2(x: -4, y: 0)
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.movement = Vector2(x: -1, y: 0)
        advance(&simulation, frames: 10)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertTrue(simulation.roster[0].isSliding)
        advance(&simulation, frames: 10)
        XCTAssertFalse(simulation.roster[0].isSliding)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "After follow-through, a ready teammate can answer the new run direction.")
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.slideCount, 1)
        XCTAssertFalse(simulation.isTackling)
    }

    func testNaturalDirectionalRunKeepsTheChosenActorAsItClosesOnTheBall() {
        var simulation = stationaryExercise()
        simulation.player.position = Vector2(x: -4, y: 0)
        simulation.roster[1].state.position = Vector2(x: 8, y: 0)
        simulation.roster[2].state.position = Vector2(x: 25, y: 25)
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.movement = Vector2(x: -1, y: 0)
        for _ in 0..<35 {
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.selectedPlayerID, 1)
        }
        XCTAssertEqual(simulation.switchCount, 1)
        XCTAssertLessThan(simulation.roster[1].state.position.x, 4)
        XCTAssertEqual(simulation.roster[0].state.position.x, -4, accuracy: 0.000001)
    }

    func testCloseIncomingLooseBallIsCushionedAtSweptReachWithoutMovingItsPosition() {
        for mode in ExerciseMode.allCases {
            var simulation = mode == .solo ? freeSolo() : stationaryExercise()
            simulation.ball.position = Vector2(x: 25, y: -25)
            simulation.step(dt: tick)
            simulation.player.position = .zero
            simulation.ball.position = Vector2(x: -2.2, y: 0)
            simulation.ball.velocity = Vector2(x: 8, y: 0)
            simulation.ball.mode = .free
            simulation.step(dt: 0.1)
            XCTAssertTrue(simulation.hasControl, "The wider foot reach should work in \(mode).")
            XCTAssertGreaterThan((simulation.ball.position - simulation.player.position).length, 1.3,
                                 "Acquisition must cushion velocity without snapping the ball to a body or dribble offset.")
            XCTAssertLessThan(simulation.ball.velocity.length, 3)
            XCTAssertEqual(simulation.ball.position.y, 0, accuracy: 0.000001)
        }
    }

    func testGradualDribbleTurnKeepsBallCloseAndIndependent() {
        var simulation = FootballSimulation()
        simulation.movement = .up
        advance(&simulation, frames: 45)
        var gaps: [Double] = []
        var rollingFrames = 0
        for frame in 0..<120 {
            let previousVelocity = simulation.ball.velocity.length
            simulation.movement = Vector2.up.rotated(by: -.pi / 2 * Double(frame) / 119)
            simulation.step(dt: tick)
            XCTAssertTrue(simulation.hasControl, "A gradual turn should preserve an ordinary dribble.")
            gaps.append((simulation.ball.position - simulation.player.position).length)
            if abs(previousVelocity - simulation.ball.velocity.length - simulation.tuning.ballFriction * tick) < 0.000001 {
                rollingFrames += 1
            }
        }
        XCTAssertLessThan(gaps.max()!, 2.0)
        XCTAssertGreaterThan(rollingFrames, 80, "The ball must still roll independently between touches.")
        XCTAssertGreaterThan(simulation.player.position.x, 10)
    }

    func testFoulStartsAtSweptBodyContactAndAftermathCannotScore() {
        var simulation = rearSlideFoulFixture()
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertTrue(simulation.roster[0].isSliding, "The first collision frame must retain the offender's follow-through pose.")
        XCTAssertEqual((simulation.roster[0].state.position - simulation.roster[3].state.position).length,
                       Pitch.playerRadius * 2, accuracy: 0.00001)
        let offenderStart = simulation.roster[0].state.position
        let victimStart = simulation.roster[3].state.position
        let initialSpeed = simulation.roster[0].state.velocity.length
        simulation.ball.position = Vector2(x: 0, y: Pitch.length / 2)
        simulation.ball.velocity = .up * 20
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 12)
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertGreaterThan((simulation.roster[0].state.position - offenderStart).length, 0.5)
        XCTAssertGreaterThan((simulation.roster[3].state.position - victimStart).length, 0.3)
        XCTAssertLessThan(simulation.roster[0].state.velocity.length, initialSpeed)
        XCTAssertEqual(simulation.northGoals, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.foulCount, 1)
        advance(&simulation, frames: Int(ceil(simulation.tuning.foulContactDuration / tick)) - 12)
        XCTAssertEqual(simulation.phase, .freeKick(team: .red))
        XCTAssertEqual(simulation.northGoals, 0)
        XCTAssertEqual(simulation.foulCount, 1)
    }

    func testManualTapCanLeaveRecoveryWithoutTransferringTheOldAction() {
        var simulation = stationaryExercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        simulation.releaseAction(heldFor: 0.3)
        advance(&simulation, frames: 20)
        XCTAssertEqual(simulation.actionStatus, .recovering)
        simulation.ball.position = simulation.roster[1].state.position + .up * 3
        XCTAssertTrue(simulation.canSwitchToNearestPlayer)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.slideCount, 1)
        XCTAssertEqual(simulation.standingTackleCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
        simulation.releaseAction(heldFor: 1)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertFalse(simulation.roster[0].isSliding)
    }
}


extension FootballSimulationTests {
    func testCancellingInputDuringFoulKeepsFrozenFollowThroughPose() {
        var simulation = rearSlideFoulFixture()
        advance(&simulation, frames: 10)
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        let offender = simulation.roster[0]
        let victim = simulation.roster[3]
        XCTAssertTrue(offender.isSliding)
        simulation.movement = .up
        simulation.cancelInput()
        XCTAssertEqual(simulation.movement, .zero)
        XCTAssertTrue(simulation.roster[0].isSliding)
        XCTAssertEqual(simulation.roster[0].state.position, offender.state.position)
        XCTAssertEqual(simulation.roster[0].state.velocity, offender.state.velocity)
        XCTAssertEqual(simulation.roster[3].fallProgress, victim.fallProgress)
        XCTAssertEqual(simulation.roster[3].fallDirection, victim.fallDirection)
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: Int(ceil(simulation.tuning.foulContactDuration / tick)) - 10)
        XCTAssertEqual(simulation.phase, .freeKick(team: .red))
        XCTAssertTrue(simulation.roster[0].isSliding, "The offender follows through after the whistle until getting up.")
        XCTAssertEqual(simulation.roster[3].fallProgress, 1)
        XCTAssertEqual(simulation.kickCount, 0)
    }
}


extension FootballSimulationTests {
    private func incomingSolo(speed: Double = 12, distance: Double = 5) -> FootballSimulation {
        var simulation = freeSolo()
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.ball.position = .up * distance
        simulation.ball.velocity = -.up * speed
        simulation.ball.mode = .free
        return simulation
    }

    func testUntargetedTapIsShortAndMovingKnockAheadCanBeChased() {
        var stationary = FootballSimulation()
        let origin = stationary.ball.position
        stationary.pressAction()
        stationary.releaseAction(heldFor: 0.05)
        XCTAssertEqual(stationary.lastKickKind, "knock ahead")
        XCTAssertEqual(stationary.ball.velocity.length, stationary.tuning.knockAheadSpeed, accuracy: 0.000001)
        advance(&stationary, frames: 120)
        XCTAssertLessThan((stationary.ball.position - origin).length, 9)

        var running = FootballSimulation()
        running.movement = .up
        advance(&running, frames: 45)
        let forwardSpeed = running.player.velocity.y
        running.pressAction()
        running.releaseAction(heldFor: 0.05)
        XCTAssertEqual(running.ball.velocity.y, forwardSpeed + running.tuning.knockAheadSpeedBonus, accuracy: 0.000001)
        XCTAssertLessThan(running.ball.velocity.length, running.tuning.passSpeed)
        for _ in 0..<90 {
            running.step(dt: tick)
            if running.hasControl { break }
        }
        XCTAssertTrue(running.hasControl)
        XCTAssertEqual(running.kickCount, 1)
        XCTAssertEqual(running.resetGeneration, 0)
    }

    func testRoughlyAimedAndDistantAssistedPassesReachReceiver() {
        for distant in [false, true] {
            var simulation = stationaryExercise()
            if distant {
                simulation.player.position = Vector2(x: 0, y: -35)
                simulation.ball.position = simulation.player.position + .up * 1.25
                simulation.roster[1].state.position = Vector2(x: 0, y: 6)
                simulation.roster[2].state.position = Vector2(x: -25, y: -25)
                simulation.roster[3].state.position = Vector2(x: 25, y: 30)
                simulation.roster[4].state.position = Vector2(x: -25, y: 35)
                simulation.roster[5].state.position = Vector2(x: 25, y: 45)
                simulation.movement = .up
            } else { simulation.movement = Vector2(x: -1, y: 0) }
            XCTAssertEqual(simulation.passTargetID, 1)
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.05)
            XCTAssertEqual(simulation.lastKickKind, "pass")
            if distant { XCTAssertGreaterThan(simulation.ball.velocity.length, simulation.tuning.passSpeed) }
            simulation.movement = .zero
            for _ in 0..<240 {
                simulation.step(dt: tick)
                if simulation.hasControl, simulation.selectedPlayerID == 1 { break }
            }
            XCTAssertEqual(simulation.selectedPlayerID, 1)
            XCTAssertTrue(simulation.hasControl, "An assisted \(distant ? "distant" : "roughly aimed") pass should be easy to receive.")
            XCTAssertLessThan((simulation.ball.position - simulation.player.position).length,
                              simulation.tuning.controlReleaseDistance)
            XCTAssertEqual(simulation.phase, .playing)
        }
    }

    func testDistantGoalwardHoldClearsWhileNearbyShotIsAssistedAndBackwardKickStaysManual() {
        for y in [-35.0, 25.0] {
            var simulation = FootballSimulation()
            simulation.player.position = Vector2(x: 10, y: y)
            simulation.ball.position = simulation.player.position + .up * 1.25
            simulation.movement = Vector2(x: 0.25, y: 1).normalized
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.6)
            if y < 0 {
                XCTAssertEqual(simulation.lastKickKind, "long kick")
                XCTAssertEqual(simulation.ball.velocity.normalized.x, simulation.movement.x, accuracy: 0.000001)
                XCTAssertEqual(simulation.ball.velocity.normalized.y, simulation.movement.y, accuracy: 0.000001)
                XCTAssertGreaterThan(simulation.ball.verticalVelocity, 8)
            } else {
                XCTAssertEqual(simulation.lastKickKind, "shot")
                let crossingX = simulation.ball.position.x + simulation.ball.velocity.x / simulation.ball.velocity.y
                    * (Pitch.length / 2 - simulation.ball.position.y)
                XCTAssertLessThan(abs(crossingX), Pitch.goalWidth / 2 - Pitch.ballRadius)
                XCTAssertGreaterThan(crossingX, 0, "Near-goal assistance preserves the requested right corner.")
            }
            XCTAssertGreaterThan(simulation.ball.velocity.length, simulation.tuning.shotMinSpeed)
        }
        var backward = FootballSimulation()
        let aim = Vector2(x: -0.3, y: -1).normalized
        backward.movement = aim
        backward.pressAction()
        backward.releaseAction(heldFor: 0.6)
        XCTAssertEqual(backward.lastKickKind, "long kick")
        XCTAssertEqual(backward.ball.velocity.normalized.x, aim.x, accuracy: 0.000001)
        XCTAssertEqual(backward.ball.velocity.normalized.y, aim.y, accuracy: 0.000001)
    }

    func testReceivingHoldQueuesShotInReleaseDirectionWithoutSlidingOrOldMovementCurve() {
        var simulation = incomingSolo()
        XCTAssertTrue(simulation.canPrepareReceivingKick)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.55)
        XCTAssertTrue(simulation.isPreparingReceivingKick)
        XCTAssertFalse(simulation.isSliding)
        XCTAssertGreaterThan(simulation.chargeFraction, 0)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.releaseAction(heldFor: 0.55)
        XCTAssertEqual(simulation.queuedActionKind, "shot")
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.movement = .up
        for _ in 0..<40 {
            simulation.step(dt: tick)
            if simulation.kickCount == 1 { break }
        }
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.lastKick, .shot)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertGreaterThan(simulation.ball.velocity.x, 25)
        XCTAssertEqual(simulation.ball.velocity.y, 0, accuracy: 0.000001)
        advance(&simulation, frames: 3)
        XCTAssertEqual(simulation.ball.velocity.y, 0, accuracy: 0.000001,
                       "The stick used to meet the incoming ball must not curve the saved kick.")
        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertLessThan(simulation.ball.velocity.y, 0, "A fresh direction after the kick may apply intentional aftertouch.")
    }

    func testQueuedKickRequiresFreshPullbackBeforeChipping() {
        var simulation = incomingSolo(speed: 30, distance: 8)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        simulation.movement = -.up
        for _ in 0..<60 {
            simulation.step(dt: tick)
            if simulation.kickCount == 1 { break }
        }
        XCTAssertEqual(simulation.kickCount, 1)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 0)
        XCTAssertEqual(simulation.ball.height, 0)
        simulation.movement = .zero
        simulation.step(dt: tick)
        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 1)
        XCTAssertGreaterThan(simulation.ball.height, 0)
    }

    func testPreparingNextPassSelectsFriendlyReceiverDuringOriginalChipWindow() {
        var simulation = stationaryExercise()
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        simulation.movement = .zero
        advance(&simulation, frames: 8)
        XCTAssertGreaterThan(simulation.chipWindowRemaining, 0)
        XCTAssertEqual(simulation.receivingPlayerID, 1)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.pressAction()
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertTrue(simulation.isPreparingReceivingKick)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.queuedActionKind, "pass")
        simulation.movement = .zero
        for _ in 0..<120 {
            simulation.step(dt: tick)
            if simulation.kickCount == 2 { break }
        }
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertEqual(simulation.passTargetID, 2)
        XCTAssertEqual(simulation.lastKickKind, "pass")
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testReceivingPressCancellationAndExpiredShotCannotBecomeGhostKick() {
        var cancelled = incomingSolo()
        cancelled.pressAction()
        cancelled.updateActionHold(heldFor: 0.5)
        cancelled.cancelInput()
        cancelled.releaseAction(heldFor: 0.5)
        advance(&cancelled, frames: 90)
        XCTAssertEqual(cancelled.kickCount, 0)
        XCTAssertNil(cancelled.queuedActionKind)

        var expired = incomingSolo()
        expired.pressAction()
        expired.releaseAction(heldFor: 0.5)
        XCTAssertEqual(expired.queuedActionKind, "shot")
        expired.ball.position = Vector2(x: 25, y: 25)
        expired.ball.velocity = .zero
        advance(&expired, frames: Int(ceil(expired.tuning.queuedPassDuration / tick)) + 1)
        XCTAssertNil(expired.queuedActionKind)
        expired.ball.position = expired.player.position + .up
        expired.step(dt: tick)
        XCTAssertEqual(expired.kickCount, 0)
    }

    func testSlowLooseBoundaryBallKeepsHoldAsSlideRescue() {
        var simulation = freeSolo()
        simulation.player.position = Vector2(x: 31.5, y: 0)
        simulation.player.velocity = Vector2(x: 8, y: 0)
        simulation.ball.position = Vector2(x: 33.3, y: 0)
        simulation.ball.velocity = .zero
        simulation.ball.mode = .free
        XCTAssertFalse(simulation.canPrepareReceivingKick)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        XCTAssertTrue(simulation.isSliding)
        XCTAssertEqual(simulation.slideCount, 1)
        XCTAssertEqual(simulation.kickCount, 0)
    }
}
