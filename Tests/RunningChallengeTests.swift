import XCTest
@testable import TopScoresSoccer

/// Independent 60 Hz scenarios for movement-based challenges and rear pressure.
final class RunningChallengeTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func stageCarrier(_ simulation: inout FootballSimulation, id: Int = 3) {
        let positions = [Vector2(x: -25, y: -25), Vector2(x: -25, y: -30),
                         Vector2(x: 25, y: -30), Vector2(x: -28, y: 40),
                         Vector2(x: 28, y: 40), Vector2(x: 0, y: 45)]
        for index in simulation.roster.indices {
            simulation.roster[index].state.position = positions[index]
            simulation.roster[index].state.velocity = .zero
            simulation.roster[index].state.facing = .up
        }
        simulation.roster[id].state.position = .zero
        simulation.movement = .zero
        simulation.ball.position = .up * 0.9
        simulation.ball.velocity = .zero
        simulation.ball.mode = .free
        simulation.ball.height = 0
        simulation.ball.verticalVelocity = 0
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, simulation.roster[id].team)
        if simulation.roster[id].team == .blue {
            XCTAssertEqual(simulation.selectedPlayerID, id)
            XCTAssertTrue(simulation.hasControl)
        } else {
            XCTAssertFalse(simulation.hasControl)
        }
    }

    private func exercise(carrierID: Int = 3) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.playerTurnRate = 0 // Keep front/rear geometry fixed for these contact fixtures.
        tuning.switchCandidateDuration = 10
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        stageCarrier(&simulation, id: carrierID)
        return simulation
    }

    private func approach(_ simulation: inout FootballSimulation, from position: Vector2, direction: Vector2,
                          speed: Double = 8) {
        simulation.player.position = position
        simulation.player.velocity = direction * speed
        simulation.player.facing = direction
        simulation.movement = direction
    }

    /// Hold the same relative contact geometry so the test measures continuous
    /// pressure time independently from the carrier's AI dribbling decisions.
    private func rearStep(_ simulation: inout FootballSimulation, carrier: Int = 3, ballOffset: Double = 0.9) {
        simulation.roster[carrier].state.position = .zero
        simulation.roster[carrier].state.velocity = .zero
        simulation.roster[carrier].state.facing = .up
        simulation.ball.position = .up * ballOffset
        simulation.ball.velocity = .zero
        simulation.ball.mode = .controlled
        approach(&simulation, from: -.up * 1.6, direction: .up, speed: 5)
        simulation.step(dt: tick)
    }

    func testFrontAndBothSideApproachesWinWithoutAction() {
        let approaches: [(Vector2, Vector2)] = [
            (.up * 2.8, -.up),
            (Vector2(x: -2.05, y: 0.7), Vector2(x: 1, y: 0)),
            (Vector2(x: 2.05, y: 0.7), Vector2(x: -1, y: 0))
        ]
        for (position, direction) in approaches {
            var simulation = exercise()
            approach(&simulation, from: position, direction: direction)
            for _ in 0..<12 where !simulation.hasControl { simulation.step(dt: tick) }
            XCTAssertTrue(simulation.hasControl, "A direct front/side run should win a reachable protected ball.")
            XCTAssertEqual(simulation.possessionTeam, .blue)
            XCTAssertEqual(simulation.runningChallengeCount, 1)
            XCTAssertEqual(simulation.kickCount, 0)
            XCTAssertEqual(simulation.tackleCount, 0)
            XCTAssertEqual(simulation.foulCount, 0)
        }
    }

    func testHeadOnRunningCarrierCanBeChallengedQuickly() {
        var simulation = exercise()
        simulation.roster[3].state.facing = -.up
        simulation.roster[3].state.velocity = -.up * 7
        simulation.ball.position = -.up * 0.9
        simulation.ball.velocity = -.up * 7
        approach(&simulation, from: -.up * 2.9, direction: .up, speed: 10)
        for _ in 0..<6 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl, "A head-on challenge should not require the rear-pressure delay.")
        XCTAssertEqual(simulation.runningChallengeCount, 1)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertEqual(simulation.foulCount, 0)
    }

    func testCleanWinIsNotImmediatelyReturnedToThePreviousCarrier() {
        var simulation = exercise()
        approach(&simulation, from: .up * 2.8, direction: -.up)
        for _ in 0..<12 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        simulation.movement = .zero
        simulation.player.velocity = .zero
        let newOwnerPosition = simulation.player.position
        for _ in 0..<12 {
            simulation.ball.position = newOwnerPosition - .up * 0.9
            simulation.ball.velocity = .zero
            simulation.roster[3].state.position = simulation.ball.position - .up * 1.25
            simulation.roster[3].state.velocity = .up * 8
            simulation.roster[3].state.facing = .up
            simulation.step(dt: tick)
            XCTAssertTrue(simulation.hasControl, "A clean win needs a brief chance to settle before the old carrier can win it straight back.")
        }
        XCTAssertEqual(simulation.runningChallengeCount, 1)
        XCTAssertEqual(simulation.foulCount, 0)
    }

    func testRearChallengeNeedsSustainedClosePressure() {
        var simulation = exercise()
        for _ in 0..<12 { rearStep(&simulation) }
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertTrue(simulation.isPressingFromBehind)
        XCTAssertGreaterThan(simulation.rearPressureProgress, 0)
        XCTAssertLessThan(simulation.rearPressureProgress, 0.75)
        XCTAssertEqual(simulation.runningChallengeCount, 0)

        for _ in 0..<27 where !simulation.hasControl { rearStep(&simulation) }
        XCTAssertTrue(simulation.hasControl, "Maintaining the same rear challenge for roughly half a second should win the ball.")
        XCTAssertEqual(simulation.runningChallengeCount, 1)
        XCTAssertEqual(simulation.foulCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testRearPhysicalBallContactCannotBypassPressureDelay() {
        var simulation = exercise()
        // The ball has drifted behind its carrier and overlaps the chasing
        // player's normal collision radius, but the approach is still rearward.
        for _ in 0..<10 {
            rearStep(&simulation, ballOffset: -0.75)
            XCTAssertFalse(simulation.hasControl)
            XCTAssertEqual(simulation.possessionTeam, .red)
        }
        XCTAssertGreaterThan(simulation.rearPressureProgress, 0)
        XCTAssertEqual(simulation.runningChallengeCount, 0)
        XCTAssertEqual(simulation.tackleCount, 0)
    }

    func testBrokenRearPressureRestartsRatherThanAccumulatingAcrossAttempts() {
        enum Interruption: CaseIterable, Equatable { case release, moveAway, cancel, ownerChange, reset }
        for interruption in Interruption.allCases {
            var simulation = exercise()
            for _ in 0..<18 { rearStep(&simulation) }
            XCTAssertGreaterThan(simulation.rearPressureProgress, 0, "Before \(interruption)")
            var carrier = 3
            switch interruption {
            case .release:
                simulation.movement = .zero
                // Retain some momentum: a released stick must not keep building pressure.
                simulation.step(dt: tick)
            case .moveAway:
                simulation.player.position = -.up * 10
                simulation.step(dt: tick)
            case .cancel:
                simulation.cancelInput()
            case .ownerChange:
                carrier = 4
                // Keep the challenger moving in the same relative geometry;
                // only the identity of the carrier changes on this step.
                simulation.roster[3].state.position = Vector2(x: -28, y: 40)
                rearStep(&simulation, carrier: carrier)
            case .reset:
                simulation.reset()
            }
            if interruption == .ownerChange {
                XCTAssertLessThanOrEqual(simulation.rearPressureProgress, 0.05,
                                         "The new carrier can accrue only this frame's pressure.")
            } else {
                XCTAssertEqual(simulation.rearPressureProgress, 0, accuracy: 0.0001, "After \(interruption)")
                XCTAssertFalse(simulation.isPressingFromBehind, "After \(interruption)")
            }
            if interruption == .reset { stageCarrier(&simulation) }
            for _ in 0..<18 { rearStep(&simulation, carrier: carrier) }
            XCTAssertFalse(simulation.hasControl, "A fresh attempt must earn its own dwell time after \(interruption).")
            XCTAssertEqual(simulation.runningChallengeCount, 0)
            XCTAssertLessThan(simulation.rearPressureProgress, 0.75)
        }
    }

    func testStationaryFrontProximityDoesNotStealProtectedPossession() {
        var simulation = exercise()
        approach(&simulation, from: .up * 2.3, direction: -.up, speed: 0)
        simulation.movement = .zero
        for _ in 0..<20 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.runningChallengeCount, 0)
        XCTAssertEqual(simulation.rearPressureProgress, 0)
    }

    func testAirborneBallAndIneligiblePlayersCannotMakeRunningSteals() {
        for exclusion in ["airborne", "goalkeeper", "sent off"] {
            var simulation = exercise()
            approach(&simulation, from: .up * 2.5, direction: -.up)
            switch exclusion {
            case "airborne": simulation.ball.height = simulation.tuning.airborneContactHeight + 1
            case "goalkeeper": simulation.roster[0].isGoalkeeper = true
            default: simulation.roster[0].isSentOff = true
            }
            simulation.step(dt: tick)
            XCTAssertFalse(simulation.hasControl, exclusion)
            XCTAssertNotEqual(simulation.possessionTeam, .blue, exclusion)
            XCTAssertEqual(simulation.runningChallengeCount, 0, exclusion)
            XCTAssertEqual(simulation.rearPressureProgress, 0, exclusion)
        }
    }

    func testRunningIntoTeammatesBallDoesNotTakeTheirProtectedClaim() {
        var simulation = exercise(carrierID: 1)
        simulation.roster[0].state.position = Vector2(x: 0.15, y: 1.6)
        simulation.roster[0].state.velocity = -.up * 8
        simulation.roster[0].state.facing = -.up
        simulation.movement = .zero
        for _ in 0..<3 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertTrue(simulation.hasControl, "The selected carrier's claim survives a teammate's incidental overlap.")
        XCTAssertEqual(simulation.runningChallengeCount, 0)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testShortDefensiveTapDoesNothingButHeldSlideStillCommits() {
        var simulation = exercise()
        approach(&simulation, from: .up * 2.8, direction: -.up, speed: 0)
        simulation.movement = .zero
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.standingTackleCount, 0)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
        XCTAssertEqual(simulation.possessionTeam, .red)

        simulation.pressAction()
        simulation.updateActionHold(heldFor: simulation.tuning.slideHoldThreshold + 0.05)
        simulation.releaseAction(heldFor: simulation.tuning.slideHoldThreshold + 0.05)
        XCTAssertTrue(simulation.isSliding)
        XCTAssertEqual(simulation.slideCount, 1)
        XCTAssertEqual(simulation.tackleCount, 1)
        XCTAssertEqual(simulation.standingTackleCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
    }
}
