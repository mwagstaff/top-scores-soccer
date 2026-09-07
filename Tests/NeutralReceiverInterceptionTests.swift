import XCTest
@testable import TopScoresSoccer

final class NeutralReceiverInterceptionTests: XCTestCase {
    private let tick = 1.0 / 60

    private func lockedSidewaysPass(distance: Double) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.passEarlyAdjustmentEnabled = false
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.roster[0].state = PlayerState(position: Vector2(x: 0, y: -40))
        simulation.ball = BallState(position: Vector2(x: 0, y: -38.75), mode: .controlled)
        simulation.roster[1].state = PlayerState(position: simulation.ball.position + .up * distance)
        simulation.roster[2].state = PlayerState(position: Vector2(x: 18, y: -38))
        for id in 3..<6 {
            simulation.roster[id].state = PlayerState(position: Vector2(x: Double(id - 4) * 27, y: -49))
        }
        simulation.step(dt: tick)
        simulation.updateMovement(.up, timestamp: 1000)
        simulation.pressAction(timestamp: 1000)
        simulation.updateMovement(Vector2(x: 1, y: 0), timestamp: 1000.06)
        simulation.releaseAction(heldFor: 0.12)
        simulation.updateMovement(.zero, timestamp: 1000.13)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertEqual(simulation.passTargetID, 1)
        return simulation
    }

    func testNeutralMeetsLockedSidewaysDeliveryAtTenTwentyFiveAndFortyMetres() {
        for distance in [10.0, 25, 40] {
            var simulation = lockedSidewaysPass(distance: distance)
            var received = false
            for _ in 0..<360 {
                simulation.step(dt: tick)
                XCTAssertEqual(simulation.selectedPlayerID, 1, "Distance \(distance)")
                XCTAssertEqual(simulation.phase, .playing)
                if simulation.hasControl { received = true; break }
            }
            XCTAssertTrue(received, "Neutral must meet a delivery planned for the previous rightward command: \(distance)m")
            guard received else { continue }
            for _ in 0..<120 {
                simulation.step(dt: tick)
                XCTAssertTrue(simulation.hasControl)
                XCTAssertEqual(simulation.selectedPlayerID, 1)
            }
            XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
            XCTAssertEqual(simulation.chipCount, 0)
            XCTAssertEqual(simulation.kickCount, 1)
            XCTAssertEqual(simulation.movement, .zero)
            XCTAssertLessThan((simulation.ball.position - simulation.player.position).length, 2)
        }
    }

    func testFutureMeetingIsBeyondTheTooEarlyOrthogonalPoint() throws {
        let ball = BallState(position: Vector2(x: 0, y: -38.75),
                             velocity: Vector2(x: 13.366, y: 24.292), mode: .pass)
        let receiver = PlayerState(position: Vector2(x: 0, y: 1.25))
        let meeting = try XCTUnwrap(ReceiverInterception.meeting(ball: ball, receiver: receiver,
            speed: 11.76, acceleration: 42, deceleration: 30, reach: 2.85,
            friction: 5, gravity: 18, maximumHeight: 0.65, horizon: 2.5))
        let direction = ball.velocity.normalized
        let projection = (receiver.position - ball.position).dot(direction)
        XCTAssertGreaterThan((meeting.position - ball.position).dot(direction), projection + 1)
        XCTAssertGreaterThan(meeting.time, 1.3)
        XCTAssertLessThan(meeting.time, 1.9)
    }

    func testNoMeetingCanBePromisedAfterBallCrossesTheBoundary() {
        let meeting = ReceiverInterception.meeting(
            ball: BallState(position: Vector2(x: 34.2, y: 0), velocity: Vector2(x: 12, y: 0), mode: .pass),
            receiver: PlayerState(position: Vector2(x: 31, y: -3)), speed: 11.76,
            acceleration: 42, deceleration: 30, reach: 1.3,
            friction: 5, gravity: 18, maximumHeight: 0.65, horizon: 1)
        XCTAssertNil(meeting)
    }

    func testIntendedReceiverHandoffDoesNotRemoveTheKickersOwnReboundGuard() {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.roster[0].state = PlayerState(position: .zero)
        simulation.roster[1].state = PlayerState(position: .up * 20)
        simulation.roster[2].state = PlayerState(position: Vector2(x: 28, y: 35))
        for id in 3..<6 {
            simulation.roster[id].state = PlayerState(position: Vector2(x: Double(id - 4) * 27, y: -49))
        }
        simulation.ball = BallState(position: .up * 1.25, mode: .controlled)
        simulation.movement = .up
        simulation.pressAction()
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        // Put a rebound back at the original kicker's feet, without another player's touch.
        simulation.ball = BallState(position: .up * 1.25, mode: .pass)
        for _ in 0..<12 {
            simulation.step(dt: tick)
            XCTAssertNil(simulation.possessionTeam)
            XCTAssertEqual(simulation.ball.mode, .pass)
        }
        for _ in 0..<12 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertEqual(simulation.ball.mode, .controlled)
        XCTAssertEqual(simulation.kickCount, 1)
    }

    func testFreshNonzeroMovementStillOverridesAutomaticMeetingImmediately() {
        var simulation = lockedSidewaysPass(distance: 40)
        simulation.movement = Vector2(x: -0.04, y: 0)
        let start = simulation.player.position
        simulation.step(dt: tick)
        XCTAssertLessThan(simulation.player.position.x, start.x)
        XCTAssertEqual(simulation.player.position.y, start.y, accuracy: 0.000001)
        XCTAssertEqual(simulation.selectedPlayerID, 1)
        XCTAssertFalse(simulation.hasControl)
    }
}
