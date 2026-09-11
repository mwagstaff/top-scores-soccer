import XCTest
@testable import TopScoresSoccer

final class CrossingIntegrationTests: XCTestCase {
    private let tick = 1.0 / 60

    private func wing(side: Double = 1) -> FootballSimulation {
        var game = FootballSimulation(mode: .passing)
        for id in game.roster.indices {
            game.roster[id].state = PlayerState(position: Vector2(x: Double(id % 3 - 1) * 20, y: -30))
        }
        game.roster[0].state = PlayerState(position: Vector2(x: side * 26, y: 36))
        game.roster[1].state = PlayerState(position: Vector2(x: 0, y: 41))
        game.ball = BallState(position: game.player.position + .up * 1.1)
        game.movement = .up
        return game
    }

    private func cross(_ game: inout FootballSimulation, heldFor: Double = 0.75) {
        game.pressAction()
        game.releaseAction(heldFor: heldFor)
    }

    func testForwardRunningHoldCrossesInwardFromBothWingsAndHandsControlToRunner() {
        for side in [-1.0, 1.0] {
            var game = wing(side: side)
            XCTAssertTrue(game.canCross)
            game.pressAction()
            game.updateActionHold(heldFor: 0.75)
            XCTAssertEqual(game.powerMeterKind, .cross)
            XCTAssertNotNil(game.powerMeterSweetSpot)
            game.releaseAction(heldFor: 0.75)
            XCTAssertEqual(game.crossCount, 1)
            XCTAssertEqual(game.lastKickKind, "cross")
            XCTAssertEqual(game.ball.mode, .pass)
            XCTAssertLessThan(game.ball.velocity.x * side, -15)
            XCTAssertGreaterThan(game.ball.verticalVelocity, 5)
            XCTAssertTrue(game.isCrossInFlight)
            XCTAssertEqual(game.selectedPlayerID, 1)
            XCTAssertEqual(game.aftertouchRemaining, 0)
            XCTAssertEqual(game.chipCount, 0)
            let before = game.player.position
            for _ in 0..<20 { game.step(dt: tick) }
            XCTAssertLessThan((game.player.position - before).length, 3,
                "Holding the winger's forward stick must not make the recipient sprint past the cross.")
            XCTAssertEqual(game.chipCount, 0)
        }
    }

    func testShortTapKeepsPassingAndCentralOrDefensiveHoldIsNotCross() {
        var tap = wing()
        cross(&tap, heldFor: 0.12)
        XCTAssertEqual(tap.crossCount, 0)
        XCTAssertNotEqual(tap.lastKickKind, "cross")
        for position in [Vector2(x: 0, y: 36), Vector2(x: 26, y: -20)] {
            var game = wing()
            game.player.position = position
            game.ball.position = position + .up * 1.1
            XCTAssertFalse(game.canCross)
            cross(&game)
            XCTAssertEqual(game.crossCount, 0)
        }
    }

    func testCrossRequiresAvailableAttackerAndPowerChangesActualRange() {
        var unavailable = wing()
        unavailable.roster[1].isInjured = true
        XCTAssertFalse(unavailable.canCross)
        var short = wing(), good = wing(), long = wing()
        cross(&short, heldFor: 0.3)
        cross(&good)
        long.pressAction()
        long.updateActionHold(heldFor: 1.5)
        XCTAssertTrue(long.isOverchargingPower)
        long.releaseAction(heldFor: 1.5)
        XCTAssertLessThan(short.ball.velocity.length, good.ball.velocity.length * 0.65)
        XCTAssertGreaterThan(long.ball.velocity.length, good.ball.velocity.length * 1.5)
        for _ in 0..<60 { short.step(dt: tick); good.step(dt: tick); long.step(dt: tick) }
        XCTAssertGreaterThan(short.ball.position.x, good.ball.position.x + 7)
        XCTAssertLessThan(long.ball.position.x, good.ball.position.x - 7)
    }

    func testWellTimedCrossHeaderGoesTowardGoalOnPressAndCanScore() {
        var game = wing()
        cross(&game)
        var attempted = false
        for _ in 0..<150 where game.headerCount == 0 {
            let offset = game.ball.position - game.player.position
            if !attempted, game.headingPlayerID != nil,
               game.ball.verticalVelocity < 0, game.ball.height < 2.5,
               offset.length < 3.7 {
                let kicksBefore = game.kickCount
                game.pressAction()
                // A press captures the goal-directed attempt even while the stick stays forward.
                XCTAssertTrue(game.isPreparingHeader || game.headerCount == 1)
                game.releaseAction(heldFor: 0.08)
                XCTAssertLessThanOrEqual(game.kickCount, kicksBefore + 1)
                attempted = true
            }
            game.step(dt: tick)
        }
        XCTAssertTrue(attempted)
        XCTAssertEqual(game.headerCount, 1)
        XCTAssertEqual(game.lastKickKind, "header")
        XCTAssertEqual(game.ball.mode, .shot)
        XCTAssertGreaterThan(game.ball.velocity.y, 12)
        XCTAssertFalse(game.isCrossInFlight)
        XCTAssertEqual(game.slideCount, 0)
        for _ in 0..<100 where game.phase == .playing { game.step(dt: tick) }
        XCTAssertEqual(game.northGoals, 1, "A timed header must be able to score through normal goal-line physics.")
    }

    func testNoActionDoesNotAutomaticallyHeadAndCancelClearsPreparedHeader() {
        var untouched = wing()
        cross(&untouched)
        for _ in 0..<110 { untouched.step(dt: tick) }
        XCTAssertEqual(untouched.headerCount, 0)

        var cancelled = wing()
        cross(&cancelled)
        for _ in 0..<90 where cancelled.headingPlayerID == nil { cancelled.step(dt: tick) }
        cancelled.pressAction()
        cancelled.cancelInput()
        let count = cancelled.headerCount
        for _ in 0..<60 { cancelled.step(dt: tick) }
        XCTAssertEqual(cancelled.headerCount, count)
        XCTAssertNil(cancelled.queuedActionKind)
        cancelled.reset(clearScore: true)
        XCTAssertEqual(cancelled.crossCount, 0)
        XCTAssertFalse(cancelled.isCrossInFlight)
    }

    func testTimingChangesOutcomeAndHoldingAnEarlyAttemptCannotRetryIt() {
        var early = wing(), timed = wing()
        cross(&early); cross(&timed)
        for _ in 0..<100 where early.headingPlayerID == nil { early.step(dt: tick) }
        early.pressAction()
        for _ in 0..<150 where early.phase == .playing { early.step(dt: tick) }
        early.releaseAction(heldFor: 1.5)
        XCTAssertEqual(early.headerCount, 1)
        XCTAssertEqual(early.northGoals, 0, "Jumping at the first distant opportunity should mistime this delivery.")
        XCTAssertEqual(early.slideCount, 0)
        for _ in 0..<100 {
            if timed.headingPlayerID != nil, timed.ball.verticalVelocity < 0,
               timed.ball.height < 2.5, (timed.ball.position - timed.player.position).length < 3.7 { break }
            timed.step(dt: tick)
        }
        timed.pressAction(); timed.releaseAction(heldFor: 0.08)
        for _ in 0..<150 where timed.phase == .playing { timed.step(dt: tick) }
        XCTAssertEqual(timed.headerCount, 1)
        XCTAssertEqual(timed.northGoals, 1)
    }

    func testCrossIgnoresAimAndFreshReceiverSteeringTakesOver() {
        var deliveries: [Vector2] = []
        for aim in [Vector2.up, -Vector2.up, Vector2(x: 1, y: 0)] {
            var game = wing()
            game.movement = aim
            cross(&game)
            deliveries.append(game.ball.velocity)
        }
        XCTAssertEqual(deliveries[0], deliveries[1])
        XCTAssertEqual(deliveries[0], deliveries[2])
        var game = wing()
        cross(&game)
        game.movement = Vector2(x: -1, y: 0)
        let before = game.player.position
        for _ in 0..<20 { game.step(dt: tick) }
        XCTAssertLessThan(game.player.position.x, before.x - 1)
        XCTAssertEqual(game.chipCount, 0)
    }

    func testPlayerKeepsRunningDuringCrossCharge() {
        var game = wing()
        let before = game.player.position
        game.pressAction()
        for _ in 0..<42 { game.step(dt: tick) }
        XCTAssertGreaterThan(game.player.position.y, before.y + 2)
        XCTAssertTrue(game.hasControl)
        game.releaseAction(heldFor: 0.7)
        XCTAssertEqual(game.crossCount, 1)
        XCTAssertLessThan(game.ball.velocity.x, -10)
    }
}
