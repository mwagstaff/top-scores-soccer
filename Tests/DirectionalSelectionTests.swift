import XCTest
@testable import TopScoresSoccer

/// Selection is an input decision: check the chosen runner and their next movement,
/// as well as the commitments that must survive a different directional candidate.
final class DirectionalSelectionTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    private func exercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        return FootballSimulation(tuning: tuning, mode: .passing)
    }

    private func looseBall() -> FootballSimulation {
        var simulation = exercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.step(dt: tick) // Release the drill's initial possession claim.
        let positions = [Vector2(x: 3.5, y: 0), Vector2(x: -6, y: 0), Vector2(x: 0, y: 9),
                         Vector2(x: -25, y: 35), Vector2(x: 25, y: 35), Vector2(x: 0, y: 45)]
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = positions[id]
            simulation.roster[id].state.velocity = .zero
            simulation.roster[id].state.facing = .up
        }
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.ball.mode = .free
        simulation.movement = .zero
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertFalse(simulation.hasControl)
        return simulation
    }

    private func redCarrier() -> FootballSimulation {
        var simulation = looseBall()
        simulation.tuning.playerTurnRate = 0
        simulation.roster[0].state.position = Vector2(x: -4, y: 0.9)
        simulation.roster[1].state.position = Vector2(x: -25, y: -25)
        simulation.roster[2].state.position = Vector2(x: 25, y: -25)
        simulation.roster[3].state.position = .zero
        simulation.roster[3].state.facing = .up
        simulation.ball.position = .up * 0.9
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        return simulation
    }

    func testHorizontalIntentChoosesFartherMatchingRunnerAndReversesNextTick() {
        var simulation = looseBall()
        let nearStart = simulation.roster[0].state.position
        let matchingStart = simulation.roster[1].state.position
        XCTAssertLessThan(nearStart.length, matchingStart.length)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertGreaterThan(simulation.roster[1].state.position.x, matchingStart.x)
        XCTAssertEqual(simulation.roster[0].state.position, nearStart)

        simulation.movement = Vector2(x: -1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0, "A clear reversed intent must bypass the previous selection's cooldown.")
        XCTAssertLessThan(simulation.roster[0].state.position.x, nearStart.x)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testDiagonalIntentSelectsTheRunnerOnTheCorrespondingSideOfTheBall() {
        var simulation = looseBall()
        simulation.roster[0].state.position = Vector2(x: 3, y: -3)
        simulation.roster[1].state.position = Vector2(x: -5, y: -5)
        simulation.movement = Vector2(x: 1, y: 1).normalized
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertGreaterThan(simulation.roster[1].state.velocity.x, 0)
        XCTAssertGreaterThan(simulation.roster[1].state.velocity.y, 0)
        simulation.movement = Vector2(x: -1, y: 1).normalized
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertLessThan(simulation.roster[0].state.velocity.x, 0)
        XCTAssertGreaterThan(simulation.roster[0].state.velocity.y, 0)
    }

    func testCarrierPathPredictionSelectsTheDefenderRunningIntoItsFuturePath() {
        func scenario(prediction: Double) -> FootballSimulation {
            var simulation = redCarrier()
            simulation.tuning.switchPredictionTime = prediction
            simulation.roster[0].state.position = Vector2(x: -9.8, y: 0)
            simulation.roster[1].state.position = Vector2(x: 2, y: 0)
            simulation.roster[3].state.velocity = Vector2(x: 8, y: 0)
            simulation.roster[3].state.facing = Vector2(x: 1, y: 0)
            simulation.ball.velocity = .zero // Only the carrier's path supplies the prediction.
            simulation.movement = Vector2(x: 1, y: 0)
            return simulation
        }
        var presentOnly = scenario(prediction: 0)
        presentOnly.step(dt: tick)
        XCTAssertEqual(presentOnly.selectedPlayerID, 0)

        var predicted = scenario(prediction: GameplayTuning.defaults.switchPredictionTime)
        let interceptorStart = predicted.roster[1].state.position
        predicted.step(dt: tick)
        XCTAssertEqual(predicted.selectedPlayerID, 1)
        XCTAssertGreaterThan(predicted.roster[1].state.position.x, interceptorStart.x)
        XCTAssertFalse(predicted.hasControl, "The defender is positioning to intercept a future path, before reaching the ball.")
    }

    func testRemotePerfectAlignmentLosesToANearbyUsefulRunner() {
        var simulation = looseBall()
        simulation.roster[1].state.position = Vector2(x: -32, y: 0)
        simulation.roster[2].state.position = Vector2(x: -6, y: 2)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertGreaterThan(simulation.roster[2].state.velocity.x, 0)
        XCTAssertEqual(simulation.roster[1].state.velocity, .zero)
    }

    func testGoalkeeperAndSentOffCandidatesCannotWinDirectionalSelection() {
        for goalkeeper in [true, false] {
            var simulation = looseBall()
            simulation.roster[1].isGoalkeeper = goalkeeper
            simulation.roster[1].isSentOff = !goalkeeper
            simulation.roster[2].state.position = Vector2(x: -5, y: 3)
            simulation.movement = Vector2(x: 1, y: 0)
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.selectedPlayerID, 2)
            XCTAssertNotEqual(simulation.selectedPlayerID, 1)
        }
    }

    func testActiveSlideKeepsItsActorThenRecoveryYieldsToAHealthyRunner() {
        var simulation = looseBall()
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.3)
        simulation.releaseAction(heldFor: 0.3)
        XCTAssertTrue(simulation.roster[0].isSliding)
        simulation.movement = Vector2(x: 1, y: 0)
        for _ in 0..<8 {
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.selectedPlayerID, 0)
            XCTAssertTrue(simulation.roster[0].isSliding)
        }
        for _ in 0..<20 where simulation.selectedPlayerID == 0 { simulation.step(dt: tick) }
        XCTAssertFalse(simulation.roster[0].isSliding)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "The completed slide's remaining recovery must not trap directional selection.")

        // The old slider is now the best geometric leftward option, but remains recovering.
        simulation.roster[0].state.position = Vector2(x: 3.5, y: 0)
        simulation.roster[1].state.position = Vector2(x: -6, y: 0)
        simulation.roster[2].state.position = Vector2(x: 5, y: 3)
        simulation.ball.position = .zero
        simulation.ball.velocity = .zero
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 2, "A healthy nearby alternative should be chosen before the recovering slider.")
    }

    func testNeutralAndSmallNoisyInputDoNotChatterAtNearEqualDistances() {
        var simulation = looseBall()
        simulation.roster[0].state.position = Vector2(x: -5, y: 0)
        simulation.roster[1].state.position = Vector2(x: 5, y: 0)
        simulation.roster[2].state.position = Vector2(x: 0, y: 12)
        let switches = simulation.switchCount
        let inputs = [Vector2.zero, Vector2(x: 0.08, y: 0.04), Vector2(x: -0.08, y: -0.04),
                      Vector2(x: 0.04, y: -0.08), Vector2(x: -0.04, y: 0.08)]
        for frame in 0..<90 {
            simulation.roster[1].state.position.x = frame.isMultiple(of: 2) ? 4.9 : 5.1
            simulation.movement = inputs[frame % inputs.count]
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.selectedPlayerID, 0)
        }
        XCTAssertEqual(simulation.switchCount, switches)
        XCTAssertFalse(simulation.hasControl)
    }

    func testDirectionAndActionBetweenTicksCaptureTheIntendedPlayer() {
        var tap = looseBall()
        tap.movement = Vector2(x: 1, y: 0)
        tap.pressAction() // The direction arrived before any simulation frame.
        XCTAssertEqual(tap.selectedPlayerID, 1)
        tap.movement = .zero
        tap.releaseAction(heldFor: 0.05)
        XCTAssertEqual(tap.selectedPlayerID, 1, "Neutral input at lift must not undo the direction used to begin this press.")
        XCTAssertEqual(tap.kickCount, 0)
        XCTAssertEqual(tap.tackleCount, 0)

        var hold = looseBall()
        hold.movement = Vector2(x: 1, y: 0)
        hold.pressAction()
        hold.updateActionHold(heldFor: 0.3)
        hold.releaseAction(heldFor: 0.3)
        XCTAssertEqual(hold.selectedPlayerID, 1)
        XCTAssertTrue(hold.roster[1].isSliding)
        XCTAssertFalse(hold.roster[0].isSliding)
    }

    func testPossessionAndAssistedReceiverRemainUnderTheirExistingControl() {
        var carrier = exercise()
        carrier.roster[1].state.position = carrier.ball.position + Vector2(x: 6, y: 0)
        carrier.movement = Vector2(x: -1, y: 0)
        carrier.step(dt: tick)
        XCTAssertEqual(carrier.selectedPlayerID, 0)
        XCTAssertTrue(carrier.hasControl)

        var receiver = exercise()
        receiver.movement = Vector2(x: -1, y: 0)
        receiver.pressAction()
        receiver.releaseAction(heldFor: 0.05)
        XCTAssertEqual(receiver.selectedPlayerID, 1)
        receiver.movement = Vector2(x: -1, y: -0.6).normalized
        receiver.step(dt: tick)
        XCTAssertEqual(receiver.selectedPlayerID, 1)
        XCTAssertTrue(receiver.isControllingPassReceiver)
        XCTAssertLessThan(receiver.roster[1].state.velocity.x, 0,
                          "The selected receiver can run away from the pass without inference taking control away.")
    }

    func testPreparedKickStaysBoundToItsActorWhenJoystickDirectionChanges() {
        var simulation = looseBall()
        simulation.roster[0].state.position = .zero
        simulation.roster[1].state.position = Vector2(x: -4, y: 5)
        simulation.ball.position = Vector2(x: -4, y: 0)
        simulation.ball.velocity = Vector2(x: 8, y: 0)
        simulation.ball.mode = .pass
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)
        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testFreeKickAimingCannotSelectADifferentRunner() {
        var simulation = exercise()
        simulation.player.position = .zero
        simulation.ball.position = Vector2(x: 0.9, y: -0.9)
        simulation.roster[3].state.position = Vector2(x: 0, y: -1.44)
        simulation.roster[3].state.facing = .up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        let frames = Int(ceil((simulation.tuning.foulContactDuration + simulation.tuning.freeKickDelay) / tick)) + 2
        for _ in 0..<frames where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.isTakingFreeKick)
        let taker = simulation.selectedPlayerID
        let spot = simulation.ball.position
        simulation.roster[1].state.position = spot + Vector2(x: 6, y: 0)
        simulation.movement = Vector2(x: -1, y: 0)
        advance(&simulation, frames: 12)
        XCTAssertEqual(simulation.selectedPlayerID, taker)
        XCTAssertEqual(simulation.ball.position, spot)
        XCTAssertGreaterThan(simulation.player.facing.dot(Vector2(x: -1, y: 0)), 0.99)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testRearPursuitKeepsCurrentChallengerUntilTheStickTurnsAway() {
        var simulation = redCarrier()
        for _ in 0..<12 {
            simulation.roster[3].state.position = .zero
            simulation.roster[3].state.velocity = .zero
            simulation.ball.position = .up * 0.9
            simulation.ball.velocity = .zero
            simulation.roster[0].state.position = -.up * 1.6
            simulation.roster[0].state.velocity = .up * 5
            simulation.roster[0].state.facing = .up
            simulation.movement = .up
            simulation.step(dt: tick)
        }
        XCTAssertTrue(simulation.isPressingFromBehind)
        simulation.roster[1].state.position = Vector2(x: 2.4, y: -0.5)
        simulation.roster[2].state.position = Vector2(x: 0, y: 6)
        simulation.movement = Vector2(x: -0.8, y: 0.6)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertTrue(simulation.isPressingFromBehind)

        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertEqual(simulation.rearPressureProgress, 0)
        XCTAssertEqual(simulation.runningChallengeCount, 0)
    }
}
