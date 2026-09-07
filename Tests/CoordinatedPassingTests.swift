import XCTest
@testable import TopScoresSoccer

/// Complete passing plays: reaching a teammate is only successful if the next dribble works.
final class CoordinatedPassingTests: XCTestCase {
    private let tick = 1.0 / 60
    private let ratings: [Double?] = [nil, 70, 78, 90]

    private func profile(_ rating: Double?) -> ClubPlayer? {
        guard let rating else { return nil }
        let id = "passing-regression-\(Int(rating))"
        return ClubPlayer(id: id, name: id, position: rating == 70 ? "F" : rating == 90 ? "D" : "M",
                          rating: rating, appearance: .generated(for: id))
    }

    private func exercise(distance: Double, direction: Vector2 = .up,
                          initialVelocity: Vector2 = .zero, rating: Double? = nil) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        let start = direction.x > 0.1 ? Vector2(x: -28, y: -38) : Vector2(x: 0, y: -40)
        for id in simulation.roster.indices {
            simulation.roster[id].state.velocity = .zero
            simulation.roster[id].clubPlayer = profile(rating)
        }
        simulation.roster[0].state.position = start
        simulation.roster[0].state.facing = direction
        simulation.ball = BallState(position: start + direction * 1.25, mode: .controlled)
        simulation.roster[1].state.position = simulation.ball.position + direction * distance
        simulation.roster[1].state.velocity = initialVelocity
        simulation.roster[2].state.position = Vector2(x: -28, y: 46)
        for id in 3..<6 {
            simulation.roster[id].state.position = Vector2(x: Double(id - 4) * 27, y: -49)
        }
        return simulation
    }

    private func launch(_ simulation: inout FootballSimulation, aim: Vector2, movement: Vector2) {
        simulation.movement = aim
        simulation.pressAction()
        // A neutral or gentle movement change retains the chosen pass aim. Movement is
        // already known when the kick leaves the foot, rather than changed after launch.
        simulation.movement = movement
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.lastKickKind, "pass")
    }

    private func receiveAndRetain(_ simulation: inout FootballSimulation, context: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var arrived = false
        for _ in 0..<300 {
            simulation.step(dt: tick)
            if simulation.selectedPlayerID == 1 && simulation.hasControl { arrived = true; break }
            if simulation.phase != .playing { break }
        }
        XCTAssertTrue(arrived, "No controlled reception: \(context)", file: file, line: line)
        guard arrived else { return }
        for frame in 0..<120 {
            simulation.step(dt: tick)
            guard simulation.hasControl && simulation.selectedPlayerID == 1 && simulation.phase == .playing else {
                XCTFail("Control lost after \(Double(frame + 1) * tick)s: \(context)", file: file, line: line)
                return
            }
        }
        XCTAssertEqual(simulation.kickCount, 1, file: file, line: line)
        XCTAssertEqual(simulation.chipCount, 0, file: file, line: line)
        XCTAssertEqual(simulation.slideCount, 0, file: file, line: line)
        XCTAssertLessThanOrEqual((simulation.ball.position - simulation.player.position).length,
                                simulation.tuning.controlReleaseDistance, file: file, line: line)
    }

    func testNeutralReceptionAndTwoSecondControlAcrossDistancesAndAbilities() {
        for rating in ratings {
            for distance in [10.0, 20, 30, 40] {
                for velocity in [Vector2.zero, Vector2(x: 6, y: 0), .up * 6] {
                    var simulation = exercise(distance: distance, initialVelocity: velocity, rating: rating)
                    launch(&simulation, aim: .up, movement: .zero)
                    receiveAndRetain(&simulation, context: "neutral rating=\(String(describing: rating)) distance=\(distance) velocity=\(velocity)")
                }
            }
        }
    }

    func testSustainedOriginalRunReceivesAndRetainsAcrossDistancesAndAbilities() {
        for rating in ratings {
            for distance in [10.0, 20, 30, 40] {
                for velocity in [Vector2.zero, Vector2(x: 6, y: 0), .up * 6] {
                    var simulation = exercise(distance: distance, initialVelocity: velocity, rating: rating)
                    launch(&simulation, aim: .up, movement: .up)
                    receiveAndRetain(&simulation, context: "held forward rating=\(String(describing: rating)) distance=\(distance) velocity=\(velocity)")
                }
            }
        }
    }

    func testGentleMovementKnownAtLaunchReceivesAndRetainsWithoutOldVelocityLead() {
        for rating in ratings {
            for distance in [10.0, 20, 30, 40] {
                for velocity in [Vector2.zero, Vector2(x: 6, y: 0), .up * 6] {
                    for movement in [Vector2(x: 0.2, y: 0), .up * 0.2, -.up * 0.2] {
                        var simulation = exercise(distance: distance, initialVelocity: velocity, rating: rating)
                        launch(&simulation, aim: .up, movement: movement)
                        receiveAndRetain(&simulation, context: "gentle rating=\(String(describing: rating)) distance=\(distance) velocity=\(velocity) input=\(movement)")
                    }
                }
            }
        }
    }

    func testDiagonalRunningReceptionKeepsControlForTwoSeconds() {
        let diagonal = Vector2(x: 1, y: 1).normalized
        for rating in ratings {
            for distance in [10.0, 20, 30] {
                for velocity in [Vector2.zero, Vector2(x: -4, y: 4)] {
                    var simulation = exercise(distance: distance, direction: diagonal, initialVelocity: velocity, rating: rating)
                    launch(&simulation, aim: diagonal, movement: diagonal)
                    receiveAndRetain(&simulation, context: "diagonal rating=\(String(describing: rating)) distance=\(distance) velocity=\(velocity)")
                }
            }
        }
    }

    func testSmallEarlySteeringChangeMovesReceiverWithoutHomingThePass() {
        for rating in ratings {
            for distance in [10.0, 20, 30] {
                var simulation = exercise(distance: distance, rating: rating)
                simulation.tuning.passEarlyAdjustmentEnabled = false
                launch(&simulation, aim: .up, movement: .up * 0.2)
                let direction = simulation.ball.velocity.normalized
                for _ in 0..<6 { simulation.step(dt: tick) }
                let before = simulation.player.position
                simulation.movement = Vector2(x: 0.08, y: 0.2)
                simulation.step(dt: tick)
                XCTAssertGreaterThan(simulation.player.position.x, before.x)
                XCTAssertEqual(simulation.selectedPlayerID, 1)
                XCTAssertEqual(simulation.ball.velocity.normalized.x, direction.x, accuracy: 0.000001)
                XCTAssertEqual(simulation.ball.velocity.normalized.y, direction.y, accuracy: 0.000001)
                receiveAndRetain(&simulation, context: "early steering rating=\(String(describing: rating)) distance=\(distance)")
            }
        }
    }

    func testTenQueuedPassesCompleteThroughRealContactsAcrossAbilities() {
        for rating in ratings {
            var simulation = exercise(distance: 17, rating: rating)
            simulation.roster[0].state.position = Vector2(x: 0, y: -12)
            simulation.roster[0].state.facing = .up
            simulation.ball = BallState(position: Vector2(x: 0, y: -10.75), mode: .controlled)
            simulation.roster[1].state.position = Vector2(x: 0, y: 5)
            simulation.roster[2].state.position = Vector2(x: 12, y: -5)
            launch(&simulation, aim: .up, movement: .zero)
            var expectedReceiver = 1
            for wantedKickCount in 2...10 {
                for _ in 0..<180 where !simulation.canPrepareReceivingKick && !simulation.hasControl {
                    simulation.step(dt: tick)
                }
                XCTAssertEqual(simulation.selectedPlayerID, expectedReceiver)
                XCTAssertFalse(simulation.hasControl, "Queue must be prepared before the actual reception")
                XCTAssertTrue(simulation.canPrepareReceivingKick)
                let next = (expectedReceiver + 1) % 3
                simulation.movement = (simulation.roster[next].state.position - simulation.player.position).normalized
                simulation.pressAction()
                simulation.movement = .zero
                simulation.releaseAction(heldFor: 0.12)
                XCTAssertEqual(simulation.queuedActionKind, "pass")
                XCTAssertEqual(simulation.queuedPassPlayerID, expectedReceiver)
                for _ in 0..<120 where simulation.kickCount < wantedKickCount { simulation.step(dt: tick) }
                XCTAssertEqual(simulation.kickCount, wantedKickCount, "rating=\(String(describing: rating))")
                if simulation.hasControl {
                    // The compact final return can be received inside the same fixed step.
                    XCTAssertEqual(simulation.ball.mode, .controlled)
                    XCTAssertLessThanOrEqual((simulation.ball.position - simulation.player.position).length,
                                             simulation.tuning.controlReleaseDistance)
                } else {
                    XCTAssertEqual(simulation.passTargetID, next)
                }
                XCTAssertEqual(simulation.selectedPlayerID, next)
                XCTAssertEqual(simulation.lastKickKind, "pass")
                expectedReceiver = next
            }
            for _ in 0..<180 where !simulation.hasControl { simulation.step(dt: tick) }
            XCTAssertTrue(simulation.hasControl)
            XCTAssertEqual(simulation.selectedPlayerID, expectedReceiver)
            for _ in 0..<120 {
                simulation.step(dt: tick)
                XCTAssertTrue(simulation.hasControl)
                XCTAssertEqual(simulation.selectedPlayerID, expectedReceiver)
            }
            XCTAssertEqual(simulation.kickCount, 10)
            XCTAssertEqual(simulation.queuedPassCount, 9)
            XCTAssertEqual(simulation.chipCount, 0)
            XCTAssertEqual(simulation.slideCount, 0)
        }
    }

    func testOnlyBlockedLaneRemainsPhysicallyInterceptable() {
        var simulation = exercise(distance: 20)
        simulation.roster[3].state.position = simulation.ball.position + .up * 8
        launch(&simulation, aim: .up, movement: .zero)
        for _ in 0..<120 where simulation.possessionTeam != .red { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testMovementChangeDuringPressPreservesTheChosenReceiverThroughReception() {
        var simulation = exercise(distance: 18)
        simulation.roster[2].state.position = Vector2(x: 20, y: -35)
        simulation.movement = .up
        simulation.pressAction()
        XCTAssertEqual(simulation.passTargetID, 1)
        simulation.movement = Vector2(x: 1, y: 0)
        XCTAssertEqual(simulation.passTargetID, 1, "The selected pass must remain understandable while moving.")
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.movement = .zero
        receiveAndRetain(&simulation, context: "receiver chosen before movement changed during ACTION")
    }

    func testVeryShortQueuedReturnRemainsAPassToTheOriginalPasser() {
        var simulation = exercise(distance: 4)
        launch(&simulation, aim: .up, movement: .zero)
        XCTAssertTrue(simulation.canPrepareReceivingKick)
        simulation.movement = -.up
        simulation.pressAction()
        XCTAssertEqual(simulation.passTargetID, 0, "The preview identifies the prepared return pass.")
        XCTAssertEqual(simulation.selectedPlayerID, 1, "The incoming receiver remains controlled until contact.")
        XCTAssertFalse(simulation.hasControl)
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 0.08)
        XCTAssertEqual(simulation.queuedActionKind, "pass")
        for _ in 0..<60 where simulation.kickCount < 2 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertEqual(simulation.passTargetID, 0)
        XCTAssertEqual(simulation.lastKickKind, "pass", "A brief self-reacquisition guard must not turn a return to feet into a long space pass.")
        for _ in 0..<120 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.chipCount, 0)
    }

    func testReceivingPlayerIsNotImmuneToAnOpponentsCloseFrontChallenge() {
        var simulation = exercise(distance: 10)
        launch(&simulation, aim: .up, movement: .up * 0.2)
        for _ in 0..<120 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        // Let the first touch bring the ball in front, while remaining inside the
        // first-touch settling period. This makes the challenger approach the carrier
        // from the front, rather than accidentally testing rear-pressure rules.
        for _ in 0..<30 { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertGreaterThan((simulation.ball.position - simulation.player.position).dot(.up), 0)
        simulation.roster[3].state.position = simulation.ball.position + .up * 1.75
        simulation.roster[3].state.velocity = -.up * 8
        simulation.roster[3].state.facing = -.up
        for _ in 0..<8 where simulation.possessionTeam != .red { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertFalse(simulation.hasControl)
    }
}
