import XCTest
@testable import TopScoresSoccer

/// Behavior-level regressions for the collision sequence, deliberate selection
/// and more forgiving close control. Scene/audio delivery is tested separately.
final class GameplayFeelTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    private func stationaryExercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        return FootballSimulation(tuning: tuning, mode: .passing)
    }

    private func rearCollision(existingYellows: Int = 0) -> FootballSimulation {
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

    private func looseBallExercise() -> FootballSimulation {
        var simulation = stationaryExercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.step(dt: tick)
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.player.facing = .up
        simulation.ball.position = Vector2(x: 0, y: 1.7)
        simulation.ball.velocity = .zero
        simulation.ball.mode = .free
        return simulation
    }

    func testVictimFallsAndTacklerFollowsThroughBeforeSecondYellowDismissal() throws {
        var simulation = rearCollision(existingYellows: 1)
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertNil(simulation.lastFoul, "A contact is not yet a whistle/card announcement.")
        XCTAssertEqual(simulation.roster[0].yellowCards, 1)
        XCTAssertFalse(simulation.roster[0].isSentOff)
        XCTAssertTrue(simulation.roster[0].isSliding)
        let victimAtContact = simulation.roster[3].state.position
        let tacklerAtContact = simulation.roster[0].state.position
        let impactDirection = simulation.roster[3].fallDirection

        advance(&simulation, frames: 12)
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertGreaterThan(simulation.roster[3].fallProgress, 0.1)
        XCTAssertLessThan(simulation.roster[3].fallProgress, 0.5)
        XCTAssertGreaterThan((simulation.roster[3].state.position - victimAtContact).dot(impactDirection), 0.1)
        XCTAssertGreaterThan((simulation.roster[0].state.position - tacklerAtContact).length, 0.1)
        XCTAssertNil(simulation.lastFoul)
        XCTAssertEqual(simulation.roster[0].yellowCards, 1)
        XCTAssertFalse(simulation.roster[0].isSentOff)

        for _ in 0..<Int(ceil(simulation.tuning.foulContactDuration / tick)) + 1 where simulation.phase == .foulContact(team: .red) {
            simulation.step(dt: tick)
        }
        XCTAssertEqual(simulation.phase, .freeKick(team: .red))
        XCTAssertEqual(simulation.roster[3].fallProgress, 1)
        XCTAssertEqual(try XCTUnwrap(simulation.lastFoul).card, .red)
        XCTAssertEqual(simulation.roster[0].yellowCards, 2)
        XCTAssertTrue(simulation.roster[0].isSentOff)
    }

    func testCancellingTouchesDuringFallDoesNotSkipOrRepeatPendingFoul() throws {
        var simulation = rearCollision()
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        advance(&simulation, frames: 10)
        let progress = simulation.roster[3].fallProgress
        let collisionCount = simulation.foulCount
        simulation.cancelInput()
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertEqual(simulation.roster[3].fallProgress, progress)
        XCTAssertNil(simulation.lastFoul)
        XCTAssertEqual(simulation.roster[0].yellowCards, 0)

        // Touch events while play is stopped cannot arm the later restart.
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 5)
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertGreaterThan(simulation.roster[3].fallProgress, progress)
        XCTAssertNil(simulation.lastFoul)
        for _ in 0..<Int(ceil(simulation.tuning.foulContactDuration / tick)) + 1 where simulation.phase == .foulContact(team: .red) {
            simulation.step(dt: tick)
        }
        let whistle = try XCTUnwrap(simulation.lastFoul)
        XCTAssertEqual(simulation.phase, .freeKick(team: .red))
        XCTAssertEqual(simulation.foulCount, collisionCount)
        advance(&simulation, frames: 30)
        XCTAssertEqual(simulation.lastFoul, whistle)
        XCTAssertEqual(simulation.roster[0].yellowCards, 1)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testResetDuringFallDiscardsPendingDisciplineAndOldAction() {
        var simulation = rearCollision(existingYellows: 1)
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        advance(&simulation, frames: 10)
        simulation.reset()
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 150)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertNil(simulation.lastFoul)
        XCTAssertTrue(simulation.roster.allSatisfy { !$0.isSentOff && $0.yellowCards == 0 && $0.fallProgress == 0 })
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
        XCTAssertTrue(simulation.hasControl)
    }

    func testBlueFreeKickNeedsFreshActionAfterContactAndWhistleFeedback() {
        var simulation = stationaryExercise()
        simulation.player.position = .zero
        simulation.ball.position = Vector2(x: 0.9, y: -0.9)
        // The AI's foot ray reaches the carrier before this ball to its side.
        simulation.roster[3].state.position = Vector2(x: 0, y: -1.44)
        simulation.roster[3].state.facing = .up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        let stoppageFrames = Int(ceil((simulation.tuning.foulContactDuration + simulation.tuning.freeKickDelay) / tick)) + 2
        for _ in 0..<stoppageFrames where simulation.phase != .playing {
            simulation.step(dt: tick)
            // A held/released thumb while the referee sequence is active must
            // not survive placement and strike the free kick automatically.
            if simulation.phase != .playing {
                simulation.pressAction()
                simulation.releaseAction(heldFor: 0.05)
            }
        }
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.ball.velocity, .zero)
        XCTAssertTrue(simulation.roster.allSatisfy { $0.fallProgress == 0 })
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 10)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.ball.velocity, .zero)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.lastKick, .pass)
    }

    func testFoulStaysAtTheContactSpotForGroundReactionAndGetUpBeforeRestart() {
        var simulation = rearCollision()
        let generation = simulation.resetGeneration
        // The older half-second sequence is still showing the actual fall.
        advance(&simulation, frames: 42)
        XCTAssertEqual(simulation.phase, .foulContact(team: .red))
        XCTAssertNil(simulation.lastFoul)
        XCTAssertGreaterThan(simulation.roster[3].fallProgress, 0.4)
        XCTAssertLessThan(simulation.roster[3].fallProgress, 1)
        for _ in 0..<90 where simulation.lastFoul == nil { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .freeKick(team: .red))
        XCTAssertEqual(simulation.roster[3].recoveryProgress, 0)
        XCTAssertTrue(simulation.roster[0].isSliding, "The tackler must not snap upright at the whistle.")
        let downPosition = simulation.roster[3].state.position
        advance(&simulation, frames: 24)
        XCTAssertEqual(simulation.roster[3].recoveryProgress, 0, "Leave a readable ground reaction after the whistle.")
        advance(&simulation, frames: 54)
        let halfwayUp = simulation.roster[3].recoveryProgress
        XCTAssertGreaterThan(halfwayUp, 0.3)
        XCTAssertLessThan(halfwayUp, 0.8)
        XCTAssertEqual(simulation.roster[3].state.position, downPosition)
        XCTAssertEqual(simulation.resetGeneration, generation)
        simulation.cancelInput()
        XCTAssertEqual(simulation.roster[3].recoveryProgress, halfwayUp)
        XCTAssertTrue(simulation.roster[0].isSliding)
        advance(&simulation, frames: 57)
        XCTAssertEqual(simulation.phase, .freeKick(team: .red))
        XCTAssertEqual(simulation.roster[3].recoveryProgress, 1, "Finish standing before set-piece placement.")
        XCTAssertEqual(simulation.resetGeneration, generation)
        advance(&simulation, frames: 10)
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertGreaterThan(simulation.resetGeneration, generation)
        XCTAssertTrue(simulation.roster.allSatisfy { $0.fallProgress == 0 && $0.recoveryProgress == 0 && !$0.isSliding })
    }

    func testFinalPlayerDismissalStillFinishesTheVisibleFoulRecovery() {
        var simulation = rearCollision(existingYellows: 1)
        simulation.roster[1].isSentOff = true
        simulation.roster[2].isSentOff = true
        for _ in 0..<90 where simulation.lastFoul == nil { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.lastFoul?.card, .red)
        XCTAssertTrue(simulation.roster[0].isSentOff)
        XCTAssertTrue(simulation.roster[0].isSliding)
        XCTAssertEqual(simulation.phase, .freeKick(team: .red), "Finish the animation even when this card ends practice.")
        advance(&simulation, frames: 78)
        XCTAssertGreaterThan(simulation.roster[3].recoveryProgress, 0.3)
        XCTAssertEqual(simulation.phase, .freeKick(team: .red))
        for _ in 0..<90 where simulation.phase == .freeKick(team: .red) { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .practiceEnded(losingTeam: .blue))
        XCTAssertEqual(simulation.roster[3].recoveryProgress, 1)
        XCTAssertFalse(simulation.roster[0].isSliding)
        XCTAssertEqual(simulation.foulCount, 1)
        simulation.reset()
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertTrue(simulation.roster.allSatisfy { !$0.isSentOff && $0.fallProgress == 0 && $0.recoveryProgress == 0 })
    }

    func testOffBallTapConsumesManualFallbackAfterImmediateAutomaticSelection() {
        var simulation = stationaryExercise()
        simulation.ball.position = Vector2(x: -8, y: 2)
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "A clearly relevant nearby player is selected immediately.")
        XCTAssertEqual(simulation.switchCount, 1)

        // The ball changes location between ticks. A neutral tap can still request
        // the new nearby player, and that one press is consumed by the selection.
        simulation.ball.position = simulation.roster[2].state.position + .up * 3
        XCTAssertTrue(simulation.canSwitchToNearestPlayer)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertEqual(simulation.switchCount, 2)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)

        simulation.releaseAction(heldFor: 1)
        simulation.updateActionHold(heldFor: 1)
        advance(&simulation, frames: 10)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertEqual(simulation.standingTackleCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testCancelledBallPressCannotTurnIntoManualSelection() {
        var simulation = stationaryExercise()
        XCTAssertTrue(simulation.hasControl)
        simulation.pressAction()
        simulation.ball.position = Vector2(x: -8, y: 2)
        simulation.ball.velocity = .zero
        simulation.step(dt: tick)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 1, "Losing the ball cancels the press and allows automatic selection.")
        XCTAssertEqual(simulation.switchCount, 1)

        // Offer a different valid manual selection before releasing the old
        // on-ball press. Its cancellation must prevent that release from switching.
        simulation.ball.position = simulation.roster[2].state.position + .up * 3
        XCTAssertTrue(simulation.canSwitchToNearestPlayer)
        simulation.releaseAction(heldFor: 0.05)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.switchCount, 1)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.tackleCount, 0)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testWiderLooseBallPickupAcceptsReachableBallsWithoutAttractingEscapingFastOrHighBalls() {
        let cases: [(Vector2, Double, Bool)] = [
            (.zero, 0, true),
            (-.up * 8, 0, true),
            (.up * 8, 0, false),
            (-.up * 40, 0, false),
            (.zero, 1, false)
        ]
        for (velocity, height, shouldCollect) in cases {
            var simulation = looseBallExercise()
            simulation.ball.velocity = velocity
            simulation.ball.height = height
            simulation.ball.mode = velocity.length > 30 ? .shot : .free
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.hasControl, shouldCollect,
                           "Pickup at 1.7m, velocity \(velocity), height \(height)")
            XCTAssertEqual(simulation.possessionTeam == .blue, shouldCollect)
            XCTAssertEqual(simulation.kickCount, 0)
            XCTAssertEqual(simulation.tackleCount, 0)
        }
    }
}
