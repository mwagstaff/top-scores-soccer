import XCTest
@testable import TopScoresSoccer

final class QueuedActionTests: XCTestCase {
    private let tick = 1.0 / 60.0

    func testQueueRemainsBoundToActorUntilAnotherTeammateReceives() {
        var simulation = looseExercise()
        simulation.movement = .up
        tapAction(&simulation)
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)

        // Being nearer alone must not transfer either selection or the pending action.
        simulation.roster[1].state.position = Vector2(x: 2.8, y: 4)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)
        XCTAssertEqual(simulation.kickCount, 0)

        // An actual reception by a teammate cancels the original actor's request.
        simulation.movement = .zero
        simulation.roster[1].state.position = simulation.ball.position - .up * 0.9
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "An actual reception gives immediate control to the new owner.")
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertNil(simulation.queuedPassPlayerID)
        XCTAssertEqual(simulation.kickCount, 0)
        for _ in 0..<45 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.kickCount, 0, "The receiver must not inherit somebody else's queued pass.")
    }

    func testSentOffActorCannotTransferQueuedPassToReplacement() {
        var simulation = looseExercise()
        simulation.movement = .up
        tapAction(&simulation)
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)

        simulation.roster[0].isSentOff = true
        simulation.roster[1].state.position = Vector2(x: 2, y: 4)
        simulation.movement = .zero
        simulation.step(dt: tick)

        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertNil(simulation.queuedPassPlayerID)
        simulation.ball.position = simulation.player.position + .up * 0.9
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.kickCount, 0)
    }

    func testQueuedFootContactCannotRescueEarlierWholeBallCrossing() {
        for direction in [-1.0, 1.0] {
            var simulation = looseSolo()
            simulation.tuning.ballFriction = 0
            simulation.player.position = Vector2(x: direction * 32.64, y: 0)
            simulation.player.velocity = Vector2(x: direction * 11.76, y: 0)
            simulation.player.facing = Vector2(x: direction, y: 0)
            simulation.ball.position = Vector2(x: direction * 34.1, y: 0)
            simulation.ball.velocity = Vector2(x: direction * 8, y: 0)
            simulation.movement = Vector2(x: direction, y: 0)
            tapAction(&simulation)
            XCTAssertEqual(simulation.queuedPassPlayerID, 0)

            // Both events fall within this step: the whole ball crosses after 0.03 s,
            // while the chasing foot would reach it only after roughly 0.043 s.
            simulation.step(dt: 0.05)

            XCTAssertEqual(simulation.phase, .outOfPlay)
            XCTAssertEqual(simulation.kickCount, 0)
            XCTAssertNil(simulation.queuedPassPlayerID)
            XCTAssertEqual(abs(simulation.ball.position.x), Pitch.width / 2 + Pitch.ballRadius,
                           accuracy: 0.000001)
        }
    }

    func testQueueExpiringWithinStepCannotKickAtLaterContactInThatStep() {
        var simulation = looseSolo()
        simulation.tuning.ballFriction = 0
        simulation.ball.position = simulation.player.position + .up * 4
        simulation.ball.velocity = -.up * 8
        simulation.movement = .up
        tapAction(&simulation)
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)

        simulation.ball.position = Vector2(x: 20, y: 20)
        simulation.ball.velocity = .zero
        simulation.movement = .zero
        let framesBeforeExpiry = max(0, Int(ceil(simulation.tuning.queuedPassDuration / tick)) - 1)
        for _ in 0..<framesBeforeExpiry { simulation.step(dt: tick) }
        XCTAssertGreaterThan(simulation.queuedPassRemaining, 0)
        XCTAssertLessThan(simulation.queuedPassRemaining, 0.02)

        // Less than 0.02 s remains, but this incoming ball needs 0.033 s to reach
        // the queued foot. Expiry must win even though both happen in one step.
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.ball.position = .up * 1.5
        simulation.ball.velocity = -.up * 6
        simulation.step(dt: 0.05)
        XCTAssertNil(simulation.queuedPassPlayerID)
        XCTAssertEqual(simulation.kickCount, 0)
        for _ in 0..<30 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.kickCount, 0, "A late physical arrival must not revive the expired request.")
    }

    private func tapAction(_ simulation: inout FootballSimulation) {
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
    }

    private func looseSolo() -> FootballSimulation {
        var simulation = FootballSimulation()
        simulation.ball.position = Vector2(x: 20, y: 20)
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertFalse(simulation.hasControl)
        return simulation
    }

    private func looseExercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.ballFriction = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        let positions = [Vector2.zero, Vector2(x: -20, y: -20), Vector2(x: 20, y: -20),
                         Vector2(x: -20, y: 30), Vector2(x: 20, y: 30), Vector2(x: 0, y: 40)]
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = positions[id]
            simulation.roster[id].state.velocity = .zero
        }
        simulation.ball.position = .up * 4
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertNil(simulation.possessionTeam)
        return simulation
    }
}
