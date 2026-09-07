import XCTest
@testable import TopScoresSoccer

final class HeaderTests: XCTestCase {
    private let tick = 1.0 / 60

    private func airborne(offset: Vector2 = .up, height: Double = 1.6,
                          velocity: Vector2 = -.up * 8, lift: Double = -1) -> FootballSimulation {
        var simulation = FootballSimulation()
        simulation.player.position = .zero
        simulation.ball = BallState(position: offset, velocity: velocity, mode: .pass,
                                    height: height, verticalVelocity: lift)
        return simulation
    }

    private func tap(_ simulation: inout FootballSimulation, aim: Vector2) {
        simulation.movement = aim
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.1)
        simulation.movement = .zero
    }

    func testReachableHeaderUsesJoypadDirectionAndActualContactHeightOnce() {
        for aim in [Vector2.up, -.up, Vector2(x: 1, y: 0), Vector2(x: -1, y: 0)] {
            var simulation = airborne()
            XCTAssertEqual(simulation.headingPlayerID, 0)
            let contact = simulation.ball.position
            tap(&simulation, aim: aim)
            XCTAssertEqual(simulation.headerCount, 1)
            XCTAssertEqual(simulation.kickCount, 1)
            XCTAssertEqual(simulation.lastKickKind, "header")
            XCTAssertEqual(simulation.ball.position, contact, "A header must not teleport the ball to the player.")
            XCTAssertEqual(simulation.ball.height, 1.6)
            XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(aim), 0.999)
            XCTAssertGreaterThan(simulation.roster[0].headingProgress, 0)
            XCTAssertEqual(simulation.slideCount, 0)
            simulation.releaseAction(heldFor: 0.1)
            for _ in 0..<30 { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.headerCount, 1)
            XCTAssertEqual(simulation.roster[0].headingProgress, 0)
        }
    }

    func testEarlyTapWaitsForPhysicalArrivalAndCapturesOutgoingAim() {
        var simulation = airborne(offset: .up * 3, height: 2.5)
        tap(&simulation, aim: Vector2(x: 1, y: 0))
        XCTAssertEqual(simulation.queuedActionKind, "header")
        XCTAssertEqual(simulation.headerCount, 0)
        XCTAssertEqual(simulation.roster[0].headingProgress, 0)
        for _ in 0..<30 where simulation.headerCount == 0 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.headerCount, 1)
        XCTAssertGreaterThan(simulation.ball.velocity.x, 15)
        XCTAssertEqual(simulation.slideCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testDescendingBallCanEnterHeadHeightWhileAlreadyWithinHorizontalReach() {
        var simulation = airborne(offset: .up, height: 3.1, velocity: .zero, lift: -1)
        tap(&simulation, aim: Vector2(x: -1, y: 0))
        XCTAssertEqual(simulation.headerCount, 0)
        for _ in 0..<30 where simulation.headerCount == 0 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.headerCount, 1)
        XCTAssertLessThan(simulation.ball.velocity.x, 0)
        // Contact occurs inside this tick; the outgoing header rises for its remainder.
        XCTAssertLessThanOrEqual(simulation.ball.height, HeadingMechanics.maximumHeight + 1.5 * tick)
        XCTAssertGreaterThan(simulation.ball.height, HeadingMechanics.minimumHeight)
    }

    func testHighUnreachableBallBypassesPlayerAndDoesNotCreateHeaderOrFootPickup() {
        var simulation = airborne(offset: .up * 2, height: 5, velocity: -.up * 20, lift: 4)
        XCTAssertNil(simulation.headingPlayerID)
        tap(&simulation, aim: .up)
        simulation.step(dt: 0.2)
        XCTAssertEqual(simulation.headerCount, 0)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertFalse(simulation.hasControl)
        XCTAssertLessThan(simulation.ball.position.y, 0)
        XCTAssertGreaterThan(simulation.ball.height, HeadingMechanics.maximumHeight)
    }

    func testCancelledExpiredOrDeflectedHeaderCannotFireLater() {
        for cancellation in 0..<3 {
            var simulation = airborne(offset: .up * 3, height: 2.5)
            tap(&simulation, aim: Vector2(x: 1, y: 0))
            if cancellation == 0 { simulation.cancelInput() }
            else if cancellation == 1 { simulation.ball.velocity = .up * 20 }
            else { simulation.reset(clearScore: true) }
            for _ in 0..<45 { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.headerCount, 0)
            XCTAssertNil(simulation.queuedActionKind)
        }
    }

    func testHoldingDuringAerialOpportunityNeverStartsSlideOrGroundShot() {
        var simulation = airborne(offset: .up * 3, height: 2.5)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.9)
        XCTAssertTrue(simulation.isPreparingHeader)
        XCTAssertNil(simulation.powerMeterKind)
        XCTAssertEqual(simulation.slideCount, 0)
        simulation.releaseAction(heldFor: 0.9)
        for _ in 0..<30 where simulation.headerCount == 0 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.headerCount, 1)
        XCTAssertEqual(simulation.lastKickKind, "header")
    }

    func testHeaderContactMustPrecedeBoundaryAndCannotRescueBallAlreadyOut() {
        var simulation = airborne(offset: .up * 3, height: 2.5)
        tap(&simulation, aim: .up)
        simulation.ball.position = Vector2(x: Pitch.width / 2 + Pitch.ballRadius + 0.1, y: 0)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .outOfPlay)
        XCTAssertEqual(simulation.headerCount, 0)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testDismissedFallenSlidingAndGoalkeeperPlayersDoNotOfferHeader() {
        for unavailable in 0..<4 {
            var simulation = airborne()
            switch unavailable {
            case 0: simulation.roster[0].isSentOff = true
            case 1: simulation.roster[0].fallProgress = 0.5
            case 2: simulation.roster[0].isTackling = true
            default: simulation.roster[0].isGoalkeeper = true
            }
            XCTAssertNil(simulation.headingPlayerID)
        }
    }

    func testSweptHeaderGeometryFindsHeightAndHorizontalOverlapTogether() {
        let ball = BallState(position: .zero, mode: .pass, height: 3.1, verticalVelocity: -1)
        let fraction = HeadingMechanics.contactFraction(ball: ball, relativeOffset: Vector2(x: 4, y: 0),
            relativeTravel: Vector2(x: -8, y: 0), duration: 0.4, gravity: 18)
        XCTAssertNotNil(fraction)
        if let fraction {
            let height = BallFlight.height(after: fraction * 0.4, ball: ball)
            XCTAssertGreaterThanOrEqual(height, HeadingMechanics.minimumHeight - 0.00001)
            XCTAssertLessThanOrEqual(height, HeadingMechanics.maximumHeight + 0.00001)
            XCTAssertLessThanOrEqual(abs(4 - 8 * fraction), HeadingMechanics.reach + 0.00001)
        }
        XCTAssertNil(HeadingMechanics.contactFraction(ball: ball, relativeOffset: Vector2(x: 4, y: 4),
            relativeTravel: Vector2(x: -8, y: 0), duration: 0.4, gravity: 18))
    }

    func testOffsideHeaderAwardsFreeKickBeforeContactWithoutCard() {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction(); simulation.releaseAction(heldFor: 0.1); simulation.cancelInput()
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = Vector2(x: Double(id % 4 - 2) * 10,
                y: simulation.roster[id].team == .blue ? -30 : 10)
            simulation.roster[id].state.velocity = .zero
        }
        simulation.roster[4].state.position = Vector2(x: 0, y: -50)
        simulation.roster[9].state.position = Vector2(x: 0, y: 50)
        simulation.roster[0].state.position = Vector2(x: 0, y: 4)
        simulation.roster[1].state.position = Vector2(x: 0, y: 20)
        simulation.ball = BallState(position: Vector2(x: 0, y: 5), mode: .free)
        simulation.step(dt: tick)
        simulation.ball = BallState(position: Vector2(x: 0, y: 19), velocity: .up * 6,
                                    mode: .pass, height: 1.6, verticalVelocity: -1)
        tap(&simulation, aim: .up)
        XCTAssertEqual(simulation.phase, .restart(kind: .offside, team: .red))
        XCTAssertEqual(simulation.offsideCount, 1)
        XCTAssertEqual(simulation.headerCount, 0)
        XCTAssertEqual(simulation.foulCount, 0)
    }
}
