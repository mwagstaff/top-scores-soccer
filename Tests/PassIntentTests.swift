import XCTest
@testable import TopScoresSoccer

final class PassIntentTests: XCTestCase {
    private let tick = 1.0 / 60

    private func exercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = Vector2(x: 0, y: -20)
        simulation.player.facing = .up
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.roster[1].state.position = Vector2(x: 0, y: 0)
        simulation.roster[2].state.position = Vector2(x: 18, y: -18)
        for id in 3..<6 { simulation.roster[id].state.position = Vector2(x: Double(id - 4) * 20, y: 40) }
        return simulation
    }

    func testRecipientStaysTheSameWhenStickPreparesANewRunDuringTap() {
        var simulation = exercise()
        simulation.movement = .up
        XCTAssertEqual(simulation.passTargetID, 1)
        simulation.pressAction()
        simulation.movement = Vector2(x: 1, y: 0)
        XCTAssertEqual(simulation.passTargetID, 1, "Button-down commits the indicated recipient.")
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertGreaterThan(simulation.ball.velocity.y, 10)
        let start = simulation.player.position
        simulation.step(dt: tick)
        XCTAssertGreaterThan(simulation.player.position.x, start.x)
        XCTAssertEqual(simulation.player.position.y, start.y, accuracy: 0.001)
        for _ in 0..<240 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
    }

    func testChargingLeavesRecipientLockAndUsesNewKickDirection() {
        var simulation = exercise()
        simulation.movement = .up
        simulation.pressAction()
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.releaseAction(heldFor: 0.7)
        XCTAssertEqual(simulation.lastKickKind, "long kick")
        XCTAssertNil(simulation.passTargetID)
        XCTAssertGreaterThan(simulation.ball.velocity.x, 20)
        XCTAssertEqual(simulation.ball.velocity.y, 0, accuracy: 0.0001)
    }

    func testCancellationClearsTargetCommitmentAndNeverKicks() {
        var simulation = exercise()
        simulation.movement = .up
        simulation.pressAction()
        simulation.cancelInput()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.movement = Vector2(x: 1, y: 0)
        simulation.pressAction()
        XCTAssertEqual(simulation.passTargetID, 2)
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
    }

    func testQueuedOnwardRecipientIsVisibleWhileIncomingReceiverStaysControlled() {
        var simulation = exercise()
        simulation.movement = .up
        simulation.pressAction()
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 0.12)
        for _ in 0..<100 where !simulation.canPrepareReceivingKick { simulation.step(dt: tick) }
        XCTAssertFalse(simulation.hasControl)
        simulation.movement = (simulation.roster[2].state.position - simulation.player.position).normalized
        simulation.pressAction()
        XCTAssertEqual(simulation.passTargetID, 2)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.queuedPassPlayerID, 1)
        XCTAssertEqual(simulation.passTargetID, 2)
        XCTAssertTrue(simulation.isControllingPassReceiver)
    }

    func testImpossibleFlightReleasesReceiverPreferencePromptly() {
        var simulation = exercise()
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.movement = .zero
        simulation.ball.position = Vector2(x: -30, y: -45)
        simulation.ball.velocity = Vector2(x: -25, y: 0)
        for _ in 0..<14 { simulation.step(dt: tick) }
        XCTAssertFalse(simulation.isControllingPassReceiver)
    }
}
