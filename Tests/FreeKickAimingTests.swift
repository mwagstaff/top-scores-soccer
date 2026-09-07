import XCTest
@testable import TopScoresSoccer

/// A real foul and restart exercise aiming separately from running or striking.
final class FreeKickAimingTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    private func blueFreeKick() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = .zero
        simulation.ball.position = Vector2(x: 0.9, y: -0.9)
        // Red's standing poke meets the blue carrier before the off-axis ball.
        simulation.roster[3].state.position = Vector2(x: 0, y: -1.44)
        simulation.roster[3].state.facing = .up
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        let frames = Int(ceil((tuning.foulContactDuration + tuning.freeKickDelay) / tick)) + 2
        for _ in 0..<frames where simulation.phase != .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .playing)
        XCTAssertEqual(simulation.lastFoul?.awardedTeam, .blue)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.kickCount, 0)
        return simulation
    }

    func testJoystickTurnsFreeKickTakerWithoutMovingTheSetPiece() {
        let directions = [Vector2(x: -1, y: 0), Vector2(x: 1, y: 0), -.up,
                          Vector2(x: 1, y: -1).normalized, Vector2(x: -1, y: 1).normalized]
        for direction in directions {
            var simulation = blueFreeKick()
            let positions = simulation.roster.map(\.state.position)
            let ballPosition = simulation.ball.position
            let selected = simulation.selectedPlayerID
            simulation.movement = direction
            advance(&simulation, frames: 30)

            XCTAssertGreaterThan(simulation.player.facing.dot(direction), 0.999)
            XCTAssertEqual(simulation.roster.map(\.state.position), positions)
            XCTAssertTrue(simulation.roster.allSatisfy { $0.state.velocity == .zero })
            XCTAssertEqual(simulation.ball.position, ballPosition)
            XCTAssertEqual(simulation.ball.velocity, .zero)
            XCTAssertEqual(simulation.selectedPlayerID, selected)
            XCTAssertEqual(simulation.kickCount, 0)
            XCTAssertTrue(simulation.hasControl)
        }
    }

    func testNeutralStickKeepsTurnedFacingForAnUntargetedFreeKickTap() {
        var simulation = blueFreeKick()
        simulation.movement = -.up
        advance(&simulation, frames: 30)
        let facing = simulation.player.facing
        let spot = simulation.ball.position
        simulation.movement = .zero
        advance(&simulation, frames: 60)
        XCTAssertEqual(simulation.player.facing, facing)
        XCTAssertGreaterThan(facing.dot(-.up), 0.999)
        XCTAssertEqual(simulation.ball.position, spot)
        XCTAssertEqual(simulation.kickCount, 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.05)

        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.lastKickKind, "knock ahead")
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(-.up), 0.999)
        XCTAssertNil(simulation.queuedActionKind)
    }

    func testChargingCanChangeFacingAndNeutralReleaseUsesItsLastDirection() {
        var simulation = blueFreeKick()
        let left = Vector2(x: -1, y: 0)
        let spot = simulation.ball.position
        let takerPosition = simulation.player.position
        simulation.pressAction()
        simulation.movement = Vector2(x: 1, y: 0)
        advance(&simulation, frames: 20)
        XCTAssertGreaterThan(simulation.player.facing.x, 0.99)
        simulation.movement = left
        advance(&simulation, frames: 25)
        XCTAssertGreaterThan(simulation.player.facing.dot(left), 0.999)
        simulation.movement = .zero
        advance(&simulation, frames: 30)
        XCTAssertEqual(simulation.chargeFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(simulation.kickCount, 0, "Reaching full charge must not take the free kick automatically.")
        XCTAssertEqual(simulation.ball.position, spot)
        XCTAssertEqual(simulation.player.position, takerPosition)
        XCTAssertEqual(simulation.ball.velocity, .zero)
        simulation.releaseAction(heldFor: 1.25)

        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertEqual(simulation.lastKickKind, "long kick")
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(left), 0.999)
        let flight = KickMechanics.longKick(heldFor: 1.25, tuning: simulation.tuning)
        XCTAssertEqual(simulation.ball.velocity.length, flight.speed, accuracy: 0.0001)
        XCTAssertEqual(simulation.ball.verticalVelocity, flight.verticalVelocity, accuracy: 0.0001)
        XCTAssertEqual(simulation.slideCount, 0)
    }

    func testCancellingFreeKickChargeRetainsFacingButRequiresFreshAction() {
        var simulation = blueFreeKick()
        let left = Vector2(x: -1, y: 0)
        simulation.movement = left
        advance(&simulation, frames: 30)
        simulation.pressAction()
        advance(&simulation, frames: 18)
        let facing = simulation.player.facing
        let spot = simulation.ball.position
        let takerPosition = simulation.player.position
        simulation.cancelInput() // The simulation's pause/interruption input contract.
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 30)

        XCTAssertEqual(simulation.player.facing, facing)
        XCTAssertGreaterThan(facing.dot(left), 0.999)
        XCTAssertEqual(simulation.player.position, takerPosition)
        XCTAssertEqual(simulation.ball.position, spot)
        XCTAssertEqual(simulation.ball.velocity, .zero)
        XCTAssertEqual(simulation.kickCount, 0)
        XCTAssertEqual(simulation.chargeFraction, 0)
        XCTAssertNil(simulation.queuedActionKind)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.4)
        XCTAssertEqual(simulation.kickCount, 1)
        XCTAssertGreaterThan(simulation.ball.velocity.normalized.dot(left), 0.999)
    }
}
