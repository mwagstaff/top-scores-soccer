import XCTest
@testable import TopScoresSoccer

final class KeeperPossessionTests: XCTestCase {
    private let tick = 1.0 / 60

    private func match() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -26 : 26,
                                                           y: id < 5 ? -15 : 20)
            simulation.roster[id].state.velocity = .zero
        }
        return simulation
    }

    private func acquireFeet(_ simulation: inout FootballSimulation) {
        simulation.roster[4].state.position = Vector2(x: 0, y: -47)
        simulation.roster[4].state.velocity = .zero
        simulation.ball = BallState(position: Vector2(x: 0, y: -45.9), velocity: -.up * 4, mode: .free)
        for _ in 0..<10 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
    }

    func testAssistedBackpassSelectsKeeperBeforeArrivalAndRemainsAFeetReception() {
        var simulation = match()
        simulation.roster[0].state.position = Vector2(x: 0, y: -35)
        simulation.roster[4].state.position = Vector2(x: 0, y: -47)
        simulation.ball = BallState(position: Vector2(x: 0, y: -36), velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        simulation.movement = -.up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 4)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertTrue(simulation.isControllingGoalkeeper)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertFalse(simulation.hasControl)
        let start = simulation.player.position
        simulation.movement = Vector2(x: 1, y: 0)
        for _ in 0..<8 { simulation.step(dt: tick) }
        XCTAssertGreaterThan(simulation.player.position.x, start.x + 0.1)
        simulation.movement = .zero
        for _ in 0..<120 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
    }

    func testKeeperFeetCanDribbleOutsideAreaWithoutRetreatOrHandling() {
        var simulation = match()
        acquireFeet(&simulation)
        simulation.movement = .up
        for _ in 0..<130 { simulation.step(dt: tick) }
        XCTAssertGreaterThan(simulation.player.position.y, -36)
        XCTAssertTrue(simulation.isControllingGoalkeeper)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
        XCTAssertLessThanOrEqual(simulation.player.velocity.length,
                                 simulation.tuning.playerMaxSpeed * simulation.tuning.keeperFootSpeedScale + 0.001)
        XCTAssertEqual(simulation.ball.height, 0)
    }

    func testOpponentRunningContactCanWinKeeperFeetPossession() {
        var simulation = match()
        acquireFeet(&simulation)
        simulation.roster[5].state.position = simulation.ball.position + .up * 1.8
        simulation.roster[5].state.velocity = -.up * 8
        simulation.roster[5].state.facing = -.up
        let contacts = simulation.challengeContactCount
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertEqual(simulation.challengeContactCount, contacts + 1)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertFalse(simulation.roster[simulation.selectedPlayerID].isGoalkeeper)
    }

    func testKeeperFootKickIsWeakerThanEquivalentOutfieldKick() {
        var keeper = match()
        acquireFeet(&keeper)
        keeper.movement = Vector2(x: 1, y: 0)
        keeper.pressAction()
        keeper.releaseAction(heldFor: 0.65)
        var outfield = FootballSimulation()
        outfield.movement = Vector2(x: 1, y: 0)
        outfield.pressAction()
        outfield.releaseAction(heldFor: 0.65)
        XCTAssertEqual(keeper.lastKickKind, "long kick")
        XCTAssertEqual(keeper.ball.velocity.length,
                       outfield.ball.velocity.length * keeper.tuning.keeperFootKickScale, accuracy: 0.00001)
    }

    func testRedKeeperStillReleasesAutomaticallyAndBlueNeverSelectsThem() {
        var simulation = match()
        simulation.roster[9].state.position = Vector2(x: 0, y: 47)
        simulation.ball = BallState(position: Vector2(x: 0, y: 45.9), velocity: .up * 4, mode: .pass)
        for _ in 0..<10 { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.goalkeeperHoldingID, 9)
        let humanKicks = simulation.kickCount
        for _ in 0..<90 where simulation.goalkeeperHoldingID != nil { simulation.step(dt: tick) }
        XCTAssertNil(simulation.goalkeeperHoldingID)
        XCTAssertEqual(simulation.ball.mode, .pass, "Automatic distribution is a throw with ordinary receiving physics.")
        XCTAssertNotNil(simulation.lastDistributionKind)
        XCTAssertGreaterThan(simulation.ball.height, 0)
        XCTAssertEqual(simulation.kickCount, humanKicks)
        XCTAssertNotEqual(simulation.selectedPlayerID, 9)
        XCTAssertEqual(simulation.lastDeliberatePlayTeam, .red)
    }

    func testKeeperOutsideOwnAreaUsesFeetEvenAfterOppositionTouch() {
        var simulation = match()
        simulation.ball = BallState(position: simulation.roster[5].state.position + .up,
                                    velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        simulation.roster[4].state.position = Vector2(x: 0, y: -32)
        simulation.roster[4].state.velocity = .zero
        simulation.ball = BallState(position: Vector2(x: 0, y: -30.9), velocity: -.up * 4, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
    }

    func testTappedHandDistributionDoesNotSelectAReceiverBeyondItsReach() {
        var simulation = match()
        simulation.ball = BallState(position: simulation.roster[5].state.position + .up,
                                    velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        simulation.roster[4].state.position = Vector2(x: 0, y: -47)
        simulation.ball = BallState(position: Vector2(x: 0, y: -45.9), velocity: -.up * 4, mode: .free)
        for _ in 0..<8 { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        simulation.roster[0].state.position = Vector2(x: 0, y: 45)
        for id in [1, 2, 3] {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -28 : 28, y: -49)
        }
        simulation.movement = .up
        XCTAssertNil(simulation.passTargetID)
        simulation.pressAction()
        XCTAssertEqual(simulation.powerMeterKind, .keeperDistribution)
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.lastDistributionKind, .overarmThrow)
        XCTAssertNil(simulation.passTargetID)
        XCTAssertFalse(simulation.isControllingPassReceiver)
        XCTAssertEqual(simulation.chipWindowRemaining, 0)
        XCTAssertEqual(simulation.aftertouchRemaining, 0)
    }
}
