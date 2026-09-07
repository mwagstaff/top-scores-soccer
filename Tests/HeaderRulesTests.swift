import XCTest
@testable import TopScoresSoccer

final class HeaderRulesTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func isolatedExercise() -> FootballSimulation {
        var simulation = FootballSimulation(mode: .passing)
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -25 : 25,
                                                           y: simulation.roster[id].team == .blue ? -30 : 30)
            simulation.roster[id].state.velocity = .zero
        }
        return simulation
    }

    private func requestHeader(_ simulation: inout FootballSimulation, aim: Vector2) {
        simulation.movement = aim
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.1)
        simulation.movement = .zero
    }

    func testRedAIHeadsReachableDescendingBallWithoutHumanAction() {
        var simulation = isolatedExercise()
        simulation.roster[3].state.position = .zero
        simulation.roster[3].state.facing = -.up
        simulation.ball = BallState(position: .up * 1.8, velocity: -.up * 8,
                                    mode: .pass, height: 1.8, verticalVelocity: -1)
        for _ in 0..<12 where simulation.lastHeaderPlayerID == nil { simulation.step(dt: tick) }

        XCTAssertEqual(simulation.lastHeaderPlayerID, 3)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        XCTAssertEqual(simulation.lastDeliberatePlayTeam, .red)
        XCTAssertLessThan(simulation.ball.velocity.y, -15)
        XCTAssertGreaterThan(simulation.ball.height, HeadingMechanics.minimumHeight)
        XCTAssertGreaterThan(simulation.roster[3].headingProgress, 0)
        XCTAssertEqual(simulation.headerCount, 0, "The human's action diagnostic must not count an AI header")
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.phase, .playing)
    }

    func testEarlierOppositionHeaderCancelsQueuedHumanHeaderEvenIfBallStillArrives() {
        var simulation = isolatedExercise()
        simulation.roster[0].state.position = Vector2(x: 0, y: -4)
        simulation.roster[3].state.position = .zero
        simulation.ball = BallState(position: .up * 2, velocity: -.up * 12,
                                    mode: .pass, height: 3, verticalVelocity: 0)
        XCTAssertEqual(simulation.headingPlayerID, 0)
        requestHeader(&simulation, aim: Vector2(x: 1, y: 0))
        XCTAssertEqual(simulation.queuedActionKind, "header")
        XCTAssertEqual(simulation.headerCount, 0)
        for _ in 0..<25 where simulation.lastHeaderPlayerID == nil { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.lastHeaderPlayerID, 3)
        XCTAssertNil(simulation.queuedActionKind)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        for _ in 0..<25 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.headerCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertLessThan(simulation.ball.position.y, -5)
        XCTAssertNil(simulation.queuedActionKind)
        XCTAssertEqual(simulation.slideCount, 0)
    }

    func testHeadedBlueBackpassCanBeCaughtAfterEarlierDeliberateFootKick() {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12) // A real foot kick initially restricts blue handling.
        simulation.cancelInput()
        XCTAssertEqual(simulation.lastDeliberatePlayTeam, .blue)
        let previousKicks = simulation.kickCount
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -25 : 25,
                                                           y: simulation.roster[id].team == .blue ? -15 : 25)
            simulation.roster[id].state.velocity = .zero
        }
        simulation.roster[1].state.position = Vector2(x: 0, y: -39)
        simulation.roster[4].state.position = Vector2(x: 0, y: -46)
        simulation.roster[9].state.position = Vector2(x: 0, y: 49)
        simulation.ball = BallState(position: Vector2(x: 0, y: -40), velocity: -.up * 6,
                                    mode: .pass, height: 1.6, verticalVelocity: -1)
        XCTAssertEqual(simulation.headingPlayerID, 1)
        requestHeader(&simulation, aim: -.up)
        XCTAssertEqual(simulation.lastHeaderPlayerID, 1)
        XCTAssertEqual(simulation.headerCount, 1)
        XCTAssertEqual(simulation.kickCount, previousKicks + 1)
        XCTAssertEqual(simulation.lastDeliberatePlayTeam, .blue)
        for _ in 0..<90 where simulation.goalkeeperHoldingID == nil { simulation.step(dt: tick) }

        XCTAssertEqual(simulation.goalkeeperHoldingID, 4)
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertEqual(simulation.offsideCount, 0)
        XCTAssertEqual(simulation.phase, .playing)
    }

    func testQueuedHeaderHeightContactCompetesWithWholeBallCrossingInTheSameTick() {
        for height in [2.67, 2.70] {
            var simulation = FootballSimulation()
            simulation.player.position = Vector2(x: Pitch.width / 2 - Pitch.playerRadius, y: 0)
            simulation.player.velocity = .zero
            simulation.ball = BallState(position: Vector2(x: 33.3, y: 0), velocity: Vector2(x: 60, y: 0),
                                        mode: .pass, height: height, verticalVelocity: -2)
            XCTAssertEqual(simulation.headingPlayerID, 0)
            requestHeader(&simulation, aim: Vector2(x: -1, y: 0))
            XCTAssertEqual(simulation.queuedActionKind, "header")
            XCTAssertEqual(simulation.headerCount, 0, "The ball initially remains above header reach")
            for _ in 0..<3 where simulation.phase == .playing && simulation.headerCount == 0 {
                simulation.step(dt: tick)
            }
            if height < 2.7 {
                XCTAssertEqual(simulation.headerCount, 1)
                XCTAssertEqual(simulation.phase, .playing)
                XCTAssertLessThan(simulation.ball.velocity.x, 0)
                XCTAssertLessThan(simulation.ball.position.x, Pitch.width / 2 + Pitch.ballRadius)
            } else {
                XCTAssertEqual(simulation.headerCount, 0)
                XCTAssertEqual(simulation.phase, .outOfPlay)
                XCTAssertEqual(simulation.ball.position.x, Pitch.width / 2 + Pitch.ballRadius, accuracy: 0.000001)
                XCTAssertGreaterThan(simulation.ball.height, HeadingMechanics.maximumHeight)
            }
            XCTAssertNil(simulation.queuedActionKind)
        }
    }
}
