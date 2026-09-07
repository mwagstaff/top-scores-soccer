import XCTest
@testable import TopScoresSoccer

final class KeeperDistributionIntegrationTests: XCTestCase {
    private let tick = 1.0 / 60

    private func liveMatch() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state = PlayerState(
                position: Vector2(x: id.isMultiple(of: 2) ? -29 : 29, y: 16 + Double(id % 3) * 6))
        }
        // A genuine opposition touch restores the blue keeper's handling eligibility.
        simulation.ball = BallState(position: simulation.roster[5].state.position + .up,
                                    velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        return simulation
    }

    private func prepared(hands: Bool, distance: Double, rating: Double? = nil) -> FootballSimulation {
        var simulation = liveMatch()
        simulation.roster[4].state = PlayerState(position: Vector2(x: 0, y: -47))
        if let rating {
            simulation.roster[4].clubPlayer = ClubPlayer(id: "keeper-\(rating)", name: "Keeper",
                position: "G", jerseyNumber: 1, rating: rating, appearance: .generated(for: "keeper"))
        }
        if hands {
            simulation.ball = BallState(position: Vector2(x: 0, y: -45.9), velocity: -.up * 4, mode: .free)
            for _ in 0..<30 { simulation.step(dt: tick) }
            XCTAssertTrue(simulation.isHoldingGoalkeeper)
        } else {
            simulation.ball = BallState(position: Vector2(x: 17, y: -52), velocity: -.up * 90, mode: .free)
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.matchRestart?.kind, .goalKick)
            for _ in 0..<120 where simulation.phase != .playing { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.matchRestart?.kind, .goalKick)
            XCTAssertTrue(simulation.isTakingRestart)
            XCTAssertFalse(simulation.isHoldingGoalkeeper)
        }
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        simulation.roster[0].state = PlayerState(position: simulation.ball.position + .up * distance)
        // Leave the main lane open; other teammates remain available in unrelated directions.
        for id in [1, 2, 3] {
            simulation.roster[id].state = PlayerState(position: Vector2(x: id.isMultiple(of: 2) ? -29 : 29, y: -48))
        }
        simulation.movement = .up * 0.35
        return simulation
    }

    private func receiveAndRetain(_ simulation: inout FootballSimulation, movement: Vector2,
                                  context: String, file: StaticString = #filePath, line: UInt = #line) {
        simulation.movement = movement
        var received = false
        for _ in 0..<360 {
            simulation.step(dt: tick)
            if simulation.selectedPlayerID == 0 && simulation.hasControl { received = true; break }
            if simulation.phase != .playing { break }
        }
        XCTAssertTrue(received, "Intended recipient should collect: \(context)", file: file, line: line)
        guard received else { return }
        for _ in 0..<120 {
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.selectedPlayerID, 0, context, file: file, line: line)
            XCTAssertTrue(simulation.hasControl, context, file: file, line: line)
        }
        XCTAssertLessThan((simulation.ball.position - simulation.player.position).length, 2.5,
                          context, file: file, line: line)
    }

    func testTappedThrowsAndGoalKicksReachSelectedReceiverAndRetainControl() {
        for hands in [true, false] {
            for distance in hands ? [6.0, 18, 30] : [8.0, 22, 38] {
                for movement in [Vector2.zero, .up * 0.35, .up] {
                    var simulation = prepared(hands: hands, distance: distance)
                    XCTAssertEqual(simulation.passTargetID, 0)
                    simulation.pressAction()
                    simulation.movement = movement
                    simulation.releaseAction(heldFor: 0.12)
                    XCTAssertEqual(simulation.selectedPlayerID, 0)
                    XCTAssertEqual(simulation.passTargetID, 0)
                    XCTAssertTrue(simulation.isControllingPassReceiver)
                    XCTAssertFalse(simulation.isHoldingGoalkeeper)
                    XCTAssertNil(simulation.matchRestart)
                    let start = simulation.player.position
                    simulation.step(dt: tick)
                    if movement.length > 0 { XCTAssertGreaterThan(simulation.player.position.y, start.y) }
                    receiveAndRetain(&simulation, movement: movement,
                        context: "hands=\(hands) distance=\(distance) movement=\(movement)")
                }
            }
        }
    }

    func testCloseOpenThrowIsUnderarmAndFartherThrowIsOverarm() {
        var close = prepared(hands: true, distance: 6)
        XCTAssertEqual(close.distributionPreviewKind, .underarmThrow)
        close.pressAction()
        close.movement = .zero
        close.releaseAction(heldFor: 0.12)
        XCTAssertEqual(close.lastDistributionKind, .underarmThrow)
        var far = prepared(hands: true, distance: 22)
        XCTAssertEqual(far.distributionPreviewKind, .overarmThrow)
        far.pressAction()
        far.movement = .zero
        far.releaseAction(heldFor: 0.12)
        XCTAssertEqual(far.lastDistributionKind, .overarmThrow)
        XCTAssertGreaterThan(far.ball.height, close.ball.height)
        receiveAndRetain(&close, movement: .zero, context: "underarm")
        receiveAndRetain(&far, movement: .zero, context: "overarm")
    }

    func testTapKeepsHighlightedTeammateWhenThumbStartsHisRunBeforeRelease() {
        for hands in [true, false] {
            var simulation = prepared(hands: hands, distance: 22)
            simulation.roster[1].state = PlayerState(position: simulation.ball.position + Vector2(x: 18, y: 3))
            simulation.movement = .up
            XCTAssertEqual(simulation.passTargetID, 0)
            simulation.pressAction()
            simulation.movement = Vector2(x: 0.35, y: 0)
            XCTAssertEqual(simulation.passTargetID, 0)
            simulation.releaseAction(heldFor: 0.12)
            XCTAssertEqual(simulation.passTargetID, 0)
            XCTAssertEqual(simulation.selectedPlayerID, 0)
            let before = simulation.player.position
            simulation.step(dt: tick)
            XCTAssertGreaterThan(simulation.player.position.x, before.x)
            receiveAndRetain(&simulation, movement: Vector2(x: 0.35, y: 0), context: "committed target hands=\(hands)")
        }
    }

    func testCentralOpponentCausesPhysicalLoftWithoutChangingRecipient() {
        for hands in [true, false] {
            var simulation = prepared(hands: hands, distance: 24)
            let opponentY = simulation.ball.position.y + 12
            simulation.roster[5].state = PlayerState(position: Vector2(x: 0, y: opponentY))
            simulation.movement = .up * 0.1
            XCTAssertEqual(simulation.passTargetID, 0)
            simulation.pressAction()
            simulation.movement = .zero
            simulation.releaseAction(heldFor: 0.12)
            XCTAssertEqual(simulation.lastDistributionKind, hands ? .highThrow : .loftedGoalKick)
            XCTAssertEqual(simulation.passTargetID, 0)
            var crossed = false
            var crossingHeight = 0.0
            for _ in 0..<240 {
                simulation.step(dt: tick)
                if simulation.ball.position.y >= opponentY {
                    crossed = true
                    crossingHeight = simulation.ball.height
                    break
                }
                if simulation.possessionTeam == .red || simulation.phase != .playing { break }
            }
            XCTAssertTrue(crossed)
            XCTAssertGreaterThan(crossingHeight, 2.4, "The ball should actually clear heading height in the blocked middle lane")
            XCTAssertNotEqual(simulation.possessionTeam, .red)
            receiveAndRetain(&simulation, movement: .zero, context: "loft over opponent hands=\(hands)")
        }
    }

    private func firstLandingRange(_ simulation: FootballSimulation) -> Double {
        let ball = simulation.ball
        let gravity = simulation.tuning.ballGravity
        let time = (ball.verticalVelocity + sqrt(ball.verticalVelocity * ball.verticalVelocity + 2 * gravity * ball.height)) / gravity
        return ball.velocity.length * time
    }

    func testHoldingForcesLongHighDeliveryAndMoreHoldAddsRange() {
        for hands in [true, false] {
            var short = prepared(hands: hands, distance: 7)
            short.pressAction()
            short.movement = .zero
            short.releaseAction(heldFor: 0.12)
            var modest = prepared(hands: hands, distance: 7)
            modest.pressAction()
            modest.updateActionHold(heldFor: 0.4)
            XCTAssertEqual(modest.distributionPreviewKind, hands ? .longThrow : .longGoalKick)
            modest.releaseAction(heldFor: 0.4)
            var full = prepared(hands: hands, distance: 7)
            full.pressAction()
            full.updateActionHold(heldFor: 1.0)
            full.releaseAction(heldFor: 1.0)
            XCTAssertEqual(full.lastDistributionKind, hands ? .longThrow : .longGoalKick)
            XCTAssertGreaterThan(modest.ball.verticalVelocity, short.ball.verticalVelocity)
            XCTAssertGreaterThan(full.ball.verticalVelocity, modest.ball.verticalVelocity)
            XCTAssertGreaterThan(firstLandingRange(modest), firstLandingRange(short) + 8)
            XCTAssertGreaterThan(firstLandingRange(full), firstLandingRange(modest) + 5)
            XCTAssertNotEqual(full.passTargetID, 0, "A forced long delivery must not remain a seven-metre pass")
            XCTAssertGreaterThan(full.aftertouchRemaining, 0)
            let original = full.ball.velocity.normalized
            full.movement = original.perpendicular
            for _ in 0..<6 { full.step(dt: tick) }
            XCTAssertGreaterThan(full.ball.velocity.normalized.dot(original.perpendicular), 0.01)
        }
    }

    func testLowerRatedKeeperStillCompletesRoutineSelectedDeliveries() {
        for hands in [true, false] {
            for rating in [55.0, 78, 95] {
                var simulation = prepared(hands: hands, distance: 18, rating: rating)
                XCTAssertEqual(simulation.passTargetID, 0)
                simulation.pressAction()
                simulation.movement = .zero
                simulation.releaseAction(heldFor: 0.12)
                XCTAssertEqual(simulation.selectedPlayerID, 0)
                receiveAndRetain(&simulation, movement: .zero, context: "rating=\(rating), hands=\(hands)")
            }
        }
    }
}
