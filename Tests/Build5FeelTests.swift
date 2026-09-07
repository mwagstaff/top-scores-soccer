import XCTest
@testable import TopScoresSoccer

/// Independent play sequences for assisted kicks and actions prepared before reception.
final class Build5FeelTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    private func quietExercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.player.facing = .up
        simulation.ball.position = .up * 1.25
        simulation.roster[1].state.position = Vector2(x: 12, y: 12)
        simulation.roster[2].state.position = Vector2(x: -25, y: -25)
        simulation.roster[3].state.position = Vector2(x: -25, y: 30)
        simulation.roster[4].state.position = Vector2(x: 25, y: 35)
        simulation.roster[5].state.position = Vector2(x: 0, y: 42)
        return simulation
    }

    private func incomingSolo(distance: Double = 4, speed: Double = 10) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.ballFriction = 0
        var simulation = FootballSimulation(tuning: tuning)
        simulation.ball.position = Vector2(x: 20, y: 20)
        simulation.step(dt: tick) // Release the sandbox's initial possession claim.
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.player.facing = .up
        simulation.ball.position = Vector2(x: -distance, y: 0)
        simulation.ball.velocity = Vector2(x: speed, y: 0)
        simulation.ball.mode = .pass
        return simulation
    }

    func testRoughAimFindsTeammateAndPassActuallyArrives() {
        var simulation = quietExercise()
        simulation.movement = .up // Teammate is 45 degrees to the right of this rough aim.
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.lastKickKind, "pass")
        simulation.movement = .zero

        var receiverOwnedBall = false
        for _ in 0..<150 {
            simulation.step(dt: tick)
            if simulation.possessionTeam == .blue,
               (simulation.ball.position - simulation.roster[1].state.position).length < 2.5 {
                receiverOwnedBall = true
                break
            }
        }
        XCTAssertTrue(receiverOwnedBall, "Assistance needs enough pace to reach its receiver, not merely point at them.")
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertLessThan(simulation.ball.velocity.length, simulation.tuning.controlRelativeSpeed)
    }

    func testAssistedPassStillCanBeInterceptedInItsPath() {
        var simulation = quietExercise()
        let initialBall = simulation.ball.position
        simulation.roster[3].state.position = (initialBall + simulation.roster[1].state.position) * 0.5
        simulation.movement = .up
        simulation.pressAction()
        // Keep the receiver stationary at launch: the defender is placed on this
        // exact pass line, rather than on a stale line behind a newly led run.
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.passTargetID, 1)
        simulation.movement = .zero

        var intercepted = false
        for _ in 0..<90 {
            simulation.step(dt: tick)
            if simulation.possessionTeam == .red { intercepted = true; break }
        }
        XCTAssertTrue(intercepted, "Receiver assistance must leave defenders able to make a physical interception.")
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertNil(simulation.passTargetID)
    }

    func testLongAssistedPassReachesReceiverWithHighRollingResistance() {
        var simulation = quietExercise()
        simulation.tuning.ballFriction = 9 // The highest exposed rolling-resistance setting.
        simulation.roster[1].state.position = .up * 38
        simulation.roster[5].state.position = Vector2(x: 25, y: 42)
        simulation.movement = Vector2(x: 1, y: 1).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.passTargetID, 1)
        simulation.movement = .zero

        var arrived = false
        for _ in 0..<180 {
            simulation.step(dt: tick)
            if simulation.possessionTeam == .blue,
               (simulation.ball.position - simulation.roster[1].state.position).length < 2.5 {
                arrived = true
                break
            }
        }
        XCTAssertTrue(arrived, "A distant assisted pass needs enough pace for the configured pitch friction.")
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.phase, .playing)
    }

    func testPreparedPassCapturesOutwardAimWithoutAFalseChipOnArrival() {
        var simulation = incomingSolo()
        XCTAssertEqual(simulation.receivingPlayerID, 0)
        simulation.movement = .up // Arrival is from the left; the requested pass goes upfield.
        simulation.pressAction()
        XCTAssertTrue(simulation.isPreparingReceivingKick)
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.queuedActionKind, "pass")
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.movement = .zero
        advance(&simulation, frames: 10)
        simulation.movement = -.up // Resume movement before contact; this is not aftertouch.

        for _ in 0..<30 where simulation.kickCount == 0 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertNil(simulation.queuedActionKind)
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(.up), 0.98)
        advance(&simulation, frames: 3)
        XCTAssertEqual(simulation.chipCount, 0, "Movement already held before reception must not become a new pull-back gesture.")
        XCTAssertEqual(simulation.ball.height, 0, accuracy: 0.0001)
        XCTAssertEqual(simulation.slideCount, 0)
    }

    func testReceivingHoldQueuesChargedKickInsteadOfSliding() {
        var simulation = incomingSolo(distance: 6, speed: 8)
        simulation.pressAction()
        XCTAssertTrue(simulation.isPreparingReceivingKick)
        advance(&simulation, frames: 18) // The actual hold is longer than the slide threshold.
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.movement = .up
        simulation.releaseAction(heldFor: 0.3)
        XCTAssertEqual(simulation.queuedActionKind, "shot")
        simulation.movement = .zero

        for _ in 0..<60 where simulation.kickCount == 0 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.lastKick, .shot)
        XCTAssertEqual(simulation.lastKickKind, "long kick")
        let clearance = KickMechanics.longKick(heldFor: 0.3, tuning: simulation.tuning)
        XCTAssertEqual(simulation.ball.velocity.length, clearance.speed, accuracy: 0.0001)
        XCTAssertGreaterThan(simulation.ball.height, 0)
        XCTAssertEqual(simulation.ball.verticalVelocity, clearance.verticalVelocity,
                       accuracy: simulation.tuning.ballGravity * tick)
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(.up), 0.98)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testUntargetedTapStopsNearEnoughToChaseAndRecover() {
        var simulation = FootballSimulation()
        let startingBall = simulation.ball.position
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.lastKickKind, "knock ahead")
        XCTAssertLessThan(simulation.ball.velocity.length, simulation.tuning.passSpeed)
        advance(&simulation, frames: 150)
        let distance = (simulation.ball.position - startingBall).length
        XCTAssertGreaterThan(distance, 4)
        XCTAssertLessThan(distance, 12)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertLessThan(simulation.ball.velocity.length, 0.1)

        for _ in 0..<150 where !simulation.hasControl {
            simulation.movement = (simulation.ball.position - simulation.player.position).normalized
            simulation.step(dt: tick)
        }
        XCTAssertTrue(simulation.hasControl, "An untargeted tap should create a reachable chase rather than a full-length pass.")
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testHeldKickAssistsRoughGoalAimButKeepsLongClearancePower() {
        var goalAttempt = FootballSimulation()
        goalAttempt.player.position = Vector2(x: 8, y: 32)
        goalAttempt.ball.position = Vector2(x: 8, y: 33.25)
        goalAttempt.movement = .up
        goalAttempt.pressAction()
        goalAttempt.releaseAction(heldFor: 1)
        XCTAssertEqual(goalAttempt.lastKickKind, "shot")
        XCTAssertGreaterThan(goalAttempt.ball.velocity.y, 0)
        let crossingTime = (Pitch.length / 2 - goalAttempt.ball.position.y) / goalAttempt.ball.velocity.y
        let crossingX = goalAttempt.ball.position.x + crossingTime * goalAttempt.ball.velocity.x
        XCTAssertLessThan(abs(crossingX), Pitch.goalWidth / 2 - Pitch.ballRadius)

        var clearance = FootballSimulation()
        let right = Vector2(x: 1, y: 0)
        clearance.movement = right
        clearance.pressAction()
        clearance.releaseAction(heldFor: 1)
        XCTAssertEqual(clearance.lastKickKind, "long kick")
        XCTAssertGreaterThan(clearance.ball.velocity.length, clearance.tuning.passSpeed * 1.5)
        XCTAssertGreaterThan(clearance.ball.velocity.normalized.dot(right), 0.98)
    }

    func testOppositionPossessionHoldRetainsSlideAction() {
        var simulation = quietExercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.step(dt: tick)
        simulation.player.position = .zero
        simulation.roster[3].state.position = .up * 3
        simulation.ball.position = .up * 2.1
        simulation.ball.velocity = .zero
        simulation.ball.mode = .free
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertFalse(simulation.canPrepareReceivingKick)
        simulation.movement = .up
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        simulation.releaseAction(heldFor: 0.3)
        XCTAssertEqual(simulation.slideCount, 1)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testFarStationaryBallAutoSelectsUsefulRunnerAndTapDoesNotQueueAnAction() {
        var simulation = quietExercise()
        simulation.player.position = Vector2(x: -25, y: -25)
        simulation.roster[1].state.position = .zero
        simulation.roster[2].state.position = Vector2(x: 25, y: -25)
        simulation.ball.position = .up * 28
        simulation.ball.velocity = .zero
        simulation.ball.mode = .free
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "A clearly remote player should yield without needing a tap.")
        XCTAssertEqual(simulation.switchCount, 1)
        XCTAssertFalse(simulation.canPrepareReceivingKick)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.switchCount, 1, "The tap should not undo the automatic selection.")
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }
}
