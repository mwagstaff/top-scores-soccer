import XCTest
@testable import TopScoresSoccer

final class SetPieceIntegrationTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func throwIn(team: Team = .blue, side: Double = 1) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        let lastTouch = team == .blue ? 5 : 0
        simulation.ball = BallState(position: simulation.roster[lastTouch].state.position
            + (team == .blue ? -.up : .up) * 1.2, mode: .free)
        simulation.step(dt: tick)
        simulation.ball = BallState(position: Vector2(x: side * 34.2, y: 10),
                                    velocity: Vector2(x: side * 100, y: 0), mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.matchRestart?.kind, .throwIn)
        XCTAssertEqual(simulation.matchRestart?.team, team)
        for _ in 0..<90 where simulation.phase != .playing { simulation.step(dt: tick) }
        simulation.tuning.aiSpeedScale = GameplayTuning.defaults.aiSpeedScale
        return simulation
    }

    private func freeKick() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = .zero
        simulation.ball.position = Vector2(x: 0.9, y: -0.9)
        simulation.roster[3].state = PlayerState(position: Vector2(x: 0, y: -1.44), facing: .up)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .foulContact(team: .blue))
        for _ in 0..<300 where simulation.phase != .playing { simulation.step(dt: tick) }
        simulation.tuning.aiSpeedScale = GameplayTuning.defaults.aiSpeedScale
        return simulation
    }

    func testThrowInOutletsRunCloseWhileThrowerBallAndClockStayStillOnBothTouchlines() {
        for side in [-1.0, 1.0] {
            var simulation = throwIn(side: side)
            let spot = simulation.ball.position
            let taker = simulation.selectedPlayerID
            let takerPosition = simulation.player.position
            let time = simulation.matchTimeElapsed
            let ids = simulation.restartShortOutletIDs
            XCTAssertEqual(ids.count, 2)
            let starts = ids.map { simulation.roster[$0].state.position }
            for _ in 0..<300 {
                simulation.step(dt: tick)
                XCTAssertEqual(simulation.restartShortOutletIDs, ids, "The same outlets finish their runs.")
                XCTAssertTrue(simulation.roster.allSatisfy {
                    abs($0.state.position.x) <= Pitch.width / 2 && abs($0.state.position.y) <= Pitch.length / 2
                })
            }
            XCTAssertEqual(simulation.player.position, takerPosition)
            XCTAssertEqual(simulation.selectedPlayerID, taker)
            XCTAssertEqual(simulation.ball.position, spot)
            XCTAssertEqual(simulation.matchTimeElapsed, time)
            for (index, id) in ids.enumerated() {
                let receiver = simulation.roster[id]
                XCTAssertLessThan((receiver.state.position - spot).length, 9.5)
                XCTAssertGreaterThan((receiver.state.position - spot).length, 4)
                XCTAssertGreaterThan((receiver.state.position - starts[index]).length, 1)
                XCTAssertFalse(receiver.isGoalkeeper)
                XCTAssertEqual(receiver.team, .blue)
            }
            if ids.count == 2 {
                XCTAssertGreaterThan((simulation.roster[ids[0]].state.position
                    - simulation.roster[ids[1]].state.position).length, 4)
            }
            simulation.movement = Vector2(x: -side, y: 0)
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.12)
            XCTAssertNil(simulation.matchRestart)
            XCTAssertTrue(simulation.restartShortOutletIDs.isEmpty)
            XCTAssertGreaterThan(simulation.ball.verticalVelocity, 0)
        }
    }

    func testFreeKickOutletsOfferReceivableShortPassAndDefendersStayTenYardsAway() {
        var simulation = freeKick()
        let spot = simulation.ball.position
        let taker = simulation.selectedPlayerID
        let takerPosition = simulation.player.position
        for _ in 0..<240 {
            simulation.step(dt: tick)
            for opponent in simulation.roster where opponent.team == .red {
                XCTAssertGreaterThanOrEqual((opponent.state.position - spot).length, 9.15 - 0.00001)
            }
        }
        XCTAssertEqual(simulation.restartShortOutletIDs.count, 2)
        XCTAssertEqual(simulation.player.position, takerPosition)
        XCTAssertEqual(simulation.ball.position, spot)
        guard let receiver = simulation.restartShortOutletIDs.first else { return }
        XCTAssertLessThan((simulation.roster[receiver].state.position - spot).length, 9.5)
        simulation.movement = (simulation.roster[receiver].state.position - spot).normalized
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.selectedPlayerID, receiver)
        XCTAssertNotEqual(simulation.selectedPlayerID, taker)
        XCTAssertTrue(simulation.restartShortOutletIDs.isEmpty)
        simulation.movement = .zero
        for _ in 0..<120 where !simulation.hasControl { simulation.step(dt: tick) }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, receiver)
    }

    func testOpponentThrowInWaitsForSupportThenReleasesWithoutStalling() {
        var simulation = throwIn(team: .red)
        let before = simulation.roster.map(\.state.position)
        let outlets = simulation.restartShortOutletIDs
        XCTAssertEqual(outlets.count, 2)
        var elapsed = 0.0
        while simulation.matchRestart != nil && elapsed < 4 {
            simulation.step(dt: tick)
            elapsed += tick
        }
        XCTAssertNil(simulation.matchRestart)
        XCTAssertGreaterThanOrEqual(elapsed, 0.6)
        XCTAssertLessThan(elapsed, 3.5)
        XCTAssertTrue(outlets.contains { (simulation.roster[$0].state.position - before[$0]).length > 1 })
        XCTAssertTrue(simulation.restartShortOutletIDs.isEmpty)
        XCTAssertTrue(simulation.passTargetID.map(outlets.contains) == true)
        for _ in 0..<120 where simulation.possessionTeam != .red { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.possessionTeam, .red, "A short throw should be controllable by its nearby outlet.")
        XCTAssertNil(simulation.lastHeaderPlayerID, "Neither thrower nor recipient should head a controllable short throw away.")
    }

    func testSentOffOutletIsReplacedAndResetDiscardsSupportState() {
        var simulation = throwIn()
        guard let first = simulation.restartShortOutletIDs.first else { return XCTFail("No support player.") }
        simulation.roster[first].isSentOff = true
        simulation.step(dt: tick)
        XCTAssertFalse(simulation.restartShortOutletIDs.contains(first))
        XCTAssertEqual(simulation.restartShortOutletIDs.count, 2)
        simulation.reset()
        XCTAssertTrue(simulation.restartShortOutletIDs.isEmpty)
        XCTAssertEqual(simulation.matchRestart?.kind, .kickoff)
    }
}
