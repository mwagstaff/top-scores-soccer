import XCTest
@testable import TopScoresSoccer

/// Independent input-order and complete-play checks for the quick-passing revision.
final class QuickPassingRegressionTests: XCTestCase {
    private let tick = 1.0 / 60.0
    private let right = Vector2(x: 1, y: 0)

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    private func exercise(aiSpeed: Double = 0) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = aiSpeed
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.player.facing = .up
        simulation.ball.position = .up * 1.25
        simulation.roster[1].state.position = .up * 14
        simulation.roster[2].state.position = Vector2(x: -25, y: -25)
        simulation.roster[3].state.position = Vector2(x: -25, y: 40)
        simulation.roster[4].state.position = Vector2(x: 25, y: 40)
        simulation.roster[5].state.position = Vector2(x: 0, y: 48)
        for id in 1..<simulation.roster.count { simulation.roster[id].state.velocity = .zero }
        return simulation
    }

    private func incomingSolo() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.ballFriction = 0
        var simulation = FootballSimulation(tuning: tuning)
        simulation.ball.position = Vector2(x: 20, y: 20)
        simulation.step(dt: tick)
        simulation.player.position = .zero
        simulation.player.velocity = .zero
        simulation.player.facing = .up
        simulation.ball.position = Vector2(x: -5, y: 0)
        simulation.ball.velocity = Vector2(x: 10, y: 0)
        simulation.ball.mode = .pass
        return simulation
    }

    func testBriefFirmReleasePassesInPossessionButLongerReleaseStillShoots() {
        var passing = exercise()
        passing.movement = .up
        passing.pressAction()
        passing.updateActionHold(heldFor: 0.23)
        XCTAssertEqual(passing.actionStatus, .pressed)
        XCTAssertEqual(passing.chargeFraction, 0)
        passing.releaseAction(heldFor: 0.23)
        XCTAssertEqual(passing.lastKick, .pass)
        XCTAssertEqual(passing.lastKickKind, "pass")
        XCTAssertEqual(passing.passTargetID, 1)
        XCTAssertEqual(passing.slideCount, 0)

        var shooting = exercise()
        shooting.player.position = Vector2(x: 0, y: 30)
        shooting.ball.position = shooting.player.position + .up * 1.25
        shooting.movement = .up
        shooting.pressAction()
        shooting.releaseAction(heldFor: 0.30)
        XCTAssertEqual(shooting.lastKick, .shot)
        XCTAssertEqual(shooting.lastKickKind, "shot")
        XCTAssertGreaterThan(shooting.ball.velocity.length, shooting.tuning.shotMinSpeed)
        XCTAssertEqual(shooting.slideCount, 0)
    }

    func testDefensiveHoldKeepsItsEarlierSlideThreshold() {
        var simulation = exercise()
        simulation.ball.position = Vector2(x: 25, y: -25)
        simulation.step(dt: tick)
        simulation.roster[0].state.position = .zero
        simulation.roster[3].state.position = .up * 5
        simulation.ball.position = .up * 4.1
        simulation.ball.velocity = .zero
        simulation.ball.mode = .free
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .red)
        simulation.movement = .up
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.23)
        XCTAssertEqual(simulation.slideCount, 1)
        simulation.releaseAction(heldFor: 0.23)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testAimChangedAndLiftedBetweenTicksSurvivesActionRelease() {
        for releaseStick in [Vector2.zero, Vector2(x: -0.05, y: 0.03)] {
            var simulation = FootballSimulation()
            simulation.player.facing = .up
            simulation.pressAction()
            simulation.movement = right
            simulation.movement = releaseStick
            // There is deliberately no physics tick between the two independent touch events.
            simulation.releaseAction(heldFor: 0.08)
            XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(right), 0.999)
            XCTAssertEqual(simulation.kickCount, 1)
        }
    }

    func testDeliberateReleaseDirectionOverridesCapturedAim() {
        var simulation = FootballSimulation()
        simulation.movement = right
        simulation.pressAction()
        simulation.movement = -right * 0.6
        simulation.releaseAction(heldFor: 0.08)
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(-right), 0.999)
        XCTAssertEqual(simulation.lastKickKind, "knock ahead")
    }

    func testLiftImmediatelyBeforePressRemembersAimButCancellationClearsIt() {
        var simulation = FootballSimulation()
        simulation.movement = right
        simulation.movement = .zero
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.08)
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(right), 0.999)

        var cancelled = FootballSimulation()
        cancelled.movement = right
        cancelled.pressAction()
        cancelled.cancelInput()
        cancelled.releaseAction(heldFor: 0.08)
        XCTAssertEqual(cancelled.kickCount, 0)
        cancelled.pressAction()
        cancelled.releaseAction(heldFor: 0.08)
        XCTAssertGreaterThan(cancelled.ball.velocity.normalized.dot(.up), 0.999)
    }

    func testWideRoughAimFindsReceiverAndBallReachesTheirFeet() {
        var simulation = exercise()
        let angle = 70.0 * Double.pi / 180
        simulation.roster[1].state.position = Vector2(x: sin(angle), y: cos(angle)) * 14
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        simulation.movement = .zero
        for _ in 0..<120 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.kickCount, 1)
        // Close arrival enables an immediate return pass before the cushioning roll finishes.
        advance(&simulation, frames: 30)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertLessThan((simulation.ball.position - simulation.player.position).length, 2.5)
    }

    func testCloseQuickOptionBeatsDistantPerfectAimButDoesNotPassBackwards() {
        var simulation = exercise()
        simulation.roster[1].state.position = Vector2(x: 4, y: 10)
        simulation.roster[2].state.position = .up * 38
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.08)
        XCTAssertEqual(simulation.passTargetID, 1)

        var openSpace = exercise()
        openSpace.roster[1].state.position = -.up * 4
        openSpace.roster[2].state.position = Vector2(x: -3, y: -6)
        openSpace.movement = .up
        openSpace.pressAction()
        openSpace.releaseAction(heldFor: 0.08)
        XCTAssertEqual(openSpace.lastKickKind, "knock ahead")
        XCTAssertGreaterThan(openSpace.ball.velocity.normalized.dot(.up), 0.999)
    }

    func testPassAssistanceSkipsACommittedOrFallenTeammate() {
        for falling in [false, true] {
            var simulation = exercise()
            simulation.roster[1].state.position = .up * 7
            simulation.roster[1].isTackling = !falling
            simulation.roster[1].isSliding = !falling
            simulation.roster[1].fallProgress = falling ? 0.5 : 0
            simulation.roster[2].state.position = Vector2(x: 5, y: 12)
            simulation.movement = .up
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.08)
            XCTAssertEqual(simulation.passTargetID, 2)
            XCTAssertEqual(simulation.selectedPlayerID, 2)
        }
    }

    func testReceivingTapGraceSavesOutgoingAimWithoutInheritingApproachAsChip() {
        var simulation = incomingSolo()
        XCTAssertEqual(simulation.receivingPlayerID, 0)
        simulation.pressAction()
        simulation.movement = .up
        simulation.movement = Vector2(x: -0.04, y: 0)
        simulation.releaseAction(heldFor: 0.23)
        XCTAssertEqual(simulation.queuedActionKind, "pass")
        XCTAssertEqual(simulation.queuedPassPlayerID, 0)
        simulation.movement = .zero
        advance(&simulation, frames: 18)
        simulation.movement = -.up
        for _ in 0..<45 where simulation.kickCount == 0 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.lastKick, .pass)
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(.up), 0.999)
        advance(&simulation, frames: 2)
        XCTAssertEqual(simulation.chipCount, 0)
        XCTAssertEqual(simulation.ball.height, 0, accuracy: 0.0001)
        XCTAssertEqual(simulation.slideCount, 0)

        simulation.movement = right
        simulation.step(dt: tick)
        simulation.movement = -.up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.chipCount, 1, "A new pull-back gesture after reception must still chip.")
        XCTAssertGreaterThan(simulation.ball.height, 0)
    }

    func testReceivingHoldAbovePassGraceQueuesShotWithoutSliding() {
        var simulation = incomingSolo()
        simulation.movement = right
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.30)
        simulation.releaseAction(heldFor: 0.30)
        XCTAssertEqual(simulation.queuedActionKind, "shot")
        XCTAssertEqual(simulation.slideCount, 0)
        simulation.movement = .zero
        for _ in 0..<60 where simulation.kickCount == 0 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.lastKick, .shot)
        XCTAssertEqual(simulation.lastKickKind, "long kick")
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(right), 0.999)
        let clearance = KickMechanics.longKick(heldFor: 0.30, tuning: simulation.tuning)
        XCTAssertEqual(simulation.ball.velocity.length, clearance.speed, accuracy: 0.0001)
        XCTAssertGreaterThan(simulation.ball.height, 0)
        XCTAssertEqual(simulation.ball.verticalVelocity, clearance.verticalVelocity,
                       accuracy: simulation.tuning.ballGravity * tick)
        XCTAssertEqual(simulation.slideCount, 0)
    }

    func testPasserMovesIntoSupportAndCanReceiveTheImmediateReturn() {
        var simulation = exercise(aiSpeed: GameplayTuning.defaults.aiSpeedScale)
        let passerStart = simulation.roster[0].state.position
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.23)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        simulation.movement = .zero
        for _ in 0..<150 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        let support = simulation.roster[0].state.position
        XCTAssertGreaterThan((support - passerStart).length, 1)
        XCTAssertGreaterThan(support.y, passerStart.y + 1)
        XCTAssertGreaterThan(abs(support.x), 0.5, "The passer should offer a return lane beside the travelling pass.")

        simulation.movement = (support - simulation.ball.position).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.23)
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertEqual(simulation.passTargetID, 0)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        simulation.movement = .zero
        for _ in 0..<150 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl, "A quick one-two must complete through real reception of both passes.")
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertEqual(simulation.kickCount, 2)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertEqual(simulation.chipCount, 0)
    }
}
