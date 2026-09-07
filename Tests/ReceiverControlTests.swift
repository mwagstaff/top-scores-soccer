import XCTest
@testable import TopScoresSoccer

final class ReceiverControlTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func exercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        return FootballSimulation(tuning: tuning, mode: .passing)
    }

    private func passLeft(_ simulation: inout FootballSimulation) {
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
    }

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    func testAssistedPassImmediatelyHandsMovementToReceiverBeforeContact() {
        var simulation = exercise()
        let passerStart = simulation.roster[0].state.position
        let receiverStart = simulation.roster[1].state.position
        passLeft(&simulation)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.ball.mode, .pass)
        simulation.movement = Vector2(x: 1, y: 0)
        advance(&simulation, frames: 6)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertGreaterThan(simulation.roster[1].state.position.x, receiverStart.x + 0.15)
        XCTAssertEqual(simulation.roster[0].state.position, passerStart)
        XCTAssertFalse(simulation.hasControl, "The movement must happen while the pass is still travelling.")
        XCTAssertGreaterThan((simulation.ball.position - simulation.player.position).length, simulation.tuning.controlAcquireDistance)
    }

    func testIntendedReceiverStaysSelectedWhileAnotherBlueIsNearerToTravellingPass() {
        var simulation = exercise()
        passLeft(&simulation)
        simulation.movement = .zero
        // Keep the real flight intact: a ball stopped far from an immobile receiver is
        // now correctly released as unviable, rather than pinned to him for four seconds.
        advance(&simulation, frames: 8)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.switchCount, 1)
        XCTAssertLessThan((simulation.roster[0].state.position - simulation.ball.position).length,
                          (simulation.roster[1].state.position - simulation.ball.position).length)
    }

    func testReceiverCanPrepareAnotherKickDuringPassersChipWindowWithoutSwitchingAgain() {
        var simulation = exercise()
        passLeft(&simulation)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.movement = .zero
        advance(&simulation, frames: 8)
        XCTAssertEqual(simulation.receivingPlayerID, 1)
        XCTAssertGreaterThan(simulation.chipWindowRemaining, 0)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.pressAction()
        XCTAssertTrue(simulation.isPreparingReceivingKick)
        XCTAssertNotEqual(simulation.actionStatus, .cancelled)
        XCTAssertEqual(simulation.chipWindowRemaining, 0)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.queuedPassPlayerID, 1)
        simulation.movement = .zero
        for _ in 0..<120 {
            simulation.step(dt: tick)
            if simulation.kickCount == 2 { break }
        }
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertEqual(simulation.passTargetID, 2)
        XCTAssertEqual(simulation.selectedPlayerID, 2, "A first-time assisted pass hands control onward to its new receiver.")
        XCTAssertNil(simulation.queuedActionKind)
        XCTAssertEqual(simulation.slideCount, 0)
    }

    func testPassRetainsDeliberateChipWithoutOriginalStickCreatingOne() {
        var simulation = exercise()
        passLeft(&simulation)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 0)
        XCTAssertEqual(simulation.ball.height, 0)
        let pullback = -simulation.ball.velocity.normalized
        simulation.movement = pullback
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 1)
        XCTAssertGreaterThan(simulation.ball.height, 0)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertGreaterThan(simulation.player.velocity.dot(pullback), 0,
                             "The pullback can chip without taking joystick control away from the receiver.")
    }

    func testManualSwitchAndInterceptionReleaseReceiverSelection() {
        var manual = exercise()
        passLeft(&manual)
        manual.movement = .zero
        manual.ball.position = Vector2(x: 1, y: -5)
        manual.ball.velocity = .zero
        XCTAssertNil(manual.receivingPlayerID)
        XCTAssertTrue(manual.canSwitchToNearestPlayer)
        manual.pressAction()
        manual.releaseAction(heldFor: 0.05)
        XCTAssertEqual(manual.selectedPlayerID, 0)
        XCTAssertFalse(manual.isControllingPassReceiver)
        XCTAssertEqual(manual.kickCount, 1)
        XCTAssertNil(manual.queuedActionKind)
        advance(&manual, frames: 45)
        XCTAssertEqual(manual.selectedPlayerID, 0)

        var intercepted = exercise()
        passLeft(&intercepted)
        intercepted.movement = .zero
        intercepted.roster[2].state.position = Vector2(x: 18, y: 18)
        intercepted.ball.position = intercepted.roster[4].state.position - .up * 0.8
        intercepted.ball.velocity = .zero
        intercepted.step(dt: tick)
        XCTAssertEqual(intercepted.possessionTeam, .red)
        XCTAssertFalse(intercepted.isControllingPassReceiver)
        XCTAssertNil(intercepted.passTargetID)
        advance(&intercepted, frames: 45)
        XCTAssertEqual(intercepted.selectedPlayerID, 2)
    }

    func testReceiverLockExpiresAndResetClearsIt() {
        var simulation = exercise()
        // Keep the ball unreceived so this actually checks expiry, not successful pickup.
        simulation.tuning.playerMaxSpeed = 0
        passLeft(&simulation)
        simulation.movement = .zero
        simulation.ball.position = Vector2(x: 0, y: 0)
        simulation.ball.velocity = .zero
        advance(&simulation, frames: 200)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        advance(&simulation, frames: 90)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "Expired receiver priority leaves a still-relevant neutral selection stable.")
        XCTAssertFalse(simulation.isControllingPassReceiver)
        simulation.reset()
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.chipWindowRemaining, 0)
    }

    func testGoalkeepersAndDismissedPlayersAreNeverSelectedAsPassReceivers() {
        for ineligible in [0, 1] {
            var simulation = exercise()
            if ineligible == 0 { simulation.roster[1].isGoalkeeper = true }
            else { simulation.roster[1].isSentOff = true }
            passLeft(&simulation)
            XCTAssertNil(simulation.passTargetID)
            XCTAssertEqual(simulation.selectedPlayerID, 0)
            XCTAssertEqual(simulation.lastKickKind, "knock ahead")
        }
    }

    func testShotStillKeepsShooterDuringAftertouch() {
        var simulation = exercise()
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertNil(simulation.passTargetID)
        simulation.movement = Vector2(x: -1, y: 0)
        advance(&simulation, frames: 20)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertGreaterThan(simulation.aftertouchRemaining, 0)
        XCTAssertFalse(simulation.isControllingPassReceiver)
        XCTAssertLessThan(simulation.ball.velocity.x, 0)
    }
}
