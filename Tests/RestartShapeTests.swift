import XCTest
@testable import TopScoresSoccer

final class RestartShapeTests: XCTestCase {
    private let tick = 1.0 / 60

    private func configuration() -> FriendlyMatchConfiguration {
        func team(_ id: String) -> ClubTeam {
            let roles = ["G", "D", "D", "D", "D", "M", "M", "M", "M", "F", "F"]
            let players = roles.enumerated().map { slot, role in
                ClubPlayer(id: "\(id)-\(slot)", name: "Player \(slot)", position: role,
                           jerseyNumber: slot + 1, rating: 78, appearance: .generated(for: "\(id)-\(slot)"))
            }
            return ClubTeam(id: id, name: id, primaryHex: "#2244CC", secondaryHex: "#FFFFFF", players: players)
        }
        return FriendlyMatchConfiguration(home: .autoSelect(team: team("Home"), formation: .fourFourTwo),
                                           away: .autoSelect(team: team("Away"), formation: .fourThreeThree))
    }

    private func match(eleven: Bool) -> FootballSimulation {
        FootballSimulation(mode: .match, configuration: eleven ? configuration() : nil)
    }

    private func assertKickoffShape(_ simulation: FootballSimulation, team: Team,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let circle = simulation.roster.filter { !$0.isSentOff && !$0.isGoalkeeper && $0.state.position.length < 9.15 }
        XCTAssertEqual(circle.count, 2, file: file, line: line)
        XCTAssertTrue(circle.allSatisfy { $0.team == team }, file: file, line: line)
        XCTAssertEqual(circle[0].state.position.y, circle[1].state.position.y, accuracy: 0.000001, file: file, line: line)
        XCTAssertGreaterThan(abs(circle[0].state.position.x - circle[1].state.position.x), 4, file: file, line: line)
        let attack = team == .blue ? 1.0 : -1.0
        XCTAssertTrue(simulation.roster.contains { $0.team == team && !$0.isGoalkeeper
            && $0.state.position.y * attack < -9 && $0.state.position.length < 35 }, file: file, line: line)
    }

    private func catchBall(_ team: Team, eleven: Bool) -> FootballSimulation {
        var simulation = match(eleven: eleven)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -26 : 26,
                                                           y: Double(id % 4) * 4)
            simulation.roster[id].state.velocity = .zero
        }
        if team == .blue {
            let opponent = simulation.roster.first { $0.team == .red && !$0.isGoalkeeper }!.id
            simulation.ball = BallState(position: simulation.roster[opponent].state.position + .up,
                                        velocity: .zero, mode: .free)
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.lastTouchTeam, .red)
        }
        let keeper = simulation.roster.first { $0.team == team && $0.isGoalkeeper }!.id
        let attack = team == .blue ? 1.0 : -1.0
        simulation.roster[keeper].state.position = Vector2(x: 0, y: -47 * attack)
        simulation.roster[keeper].state.velocity = .zero
        simulation.ball = BallState(position: Vector2(x: 0, y: -45.9 * attack),
                                    velocity: Vector2(x: 0, y: -4 * attack), mode: .free)
        for _ in 0..<8 where simulation.goalkeeperHoldingID == nil { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.goalkeeperHoldingID, keeper)
        return simulation
    }

    func testKickoffOffersSideBySideLateralPassAndBackwardsAlternativesInBothSizes() {
        for eleven in [false, true] {
            let initial = match(eleven: eleven)
            assertKickoffShape(initial, team: .blue)
            let taker = initial.selectedPlayerID
            let partner = initial.roster.first { $0.team == .blue && !$0.isGoalkeeper && $0.id != taker
                && $0.state.position.length < 9.15 }!.id
            var lateral = initial
            lateral.pressAction()
            lateral.releaseAction(heldFor: 0.12)
            XCTAssertEqual(lateral.passTargetID, partner)
            XCTAssertGreaterThan(lateral.ball.velocity.x, 0)
            XCTAssertLessThan(abs(lateral.ball.velocity.y), 1)
            XCTAssertEqual(lateral.lastKick, .pass)
            var backward = initial
            backward.movement = -.up
            backward.pressAction()
            backward.releaseAction(heldFor: 0.12)
            XCTAssertNotNil(backward.passTargetID)
            XCTAssertLessThan(backward.ball.velocity.y, 0)
            XCTAssertEqual(backward.lastKick, .pass)
        }
    }

    func testConcedingRedTeamGetsSameShapeAndAutomaticLateralKickoff() {
        for eleven in [false, true] {
            var simulation = match(eleven: eleven)
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.12)
            simulation.cancelInput()
            let keeper = simulation.roster.first { $0.team == .red && $0.isGoalkeeper }!.id
            simulation.roster[keeper].state.position = Vector2(x: 15, y: 46)
            simulation.ball = BallState(position: Vector2(x: 0, y: 52), velocity: .up * 120, mode: .shot)
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.phase, .goal(north: true))
            for _ in 0..<100 where simulation.phase != .playing { simulation.step(dt: tick) }
            XCTAssertEqual(simulation.matchRestart?.team, .red)
            assertKickoffShape(simulation, team: .red)
            for _ in 0..<90 where simulation.isTakingRestart { simulation.step(dt: tick) }
            XCTAssertNil(simulation.matchRestart)
            XCTAssertLessThan(simulation.ball.velocity.x, 0)
            XCTAssertLessThan(abs(simulation.ball.velocity.y), 1)
            XCTAssertEqual(simulation.lastTouchTeam, .red)
        }
    }

    func testBlueCatchWithdrawsEveryOpponentAndKeepsExactlyOneCloseOutletWithoutTeleporting() {
        for eleven in [false, true] {
            var simulation = catchBall(.blue, eleven: eleven)
            let keeper = simulation.goalkeeperHoldingID!
            let opponents = simulation.roster.filter { $0.team == .red && !$0.isGoalkeeper }.map(\.id)
            for (slot, id) in opponents.enumerated() {
                simulation.roster[id].state.position = Vector2(x: Double(slot % 5 - 2) * 3.5,
                                                               y: -44 + Double(slot / 5) * 4)
                simulation.roster[id].state.velocity = .zero
            }
            let before = simulation.roster.map(\.state.position)
            simulation.step(dt: tick)
            let outlet = simulation.keeperShortOutletID!
            XCTAssertEqual(simulation.roster[outlet].team, .blue)
            for id in opponents {
                XCTAssertGreaterThan(simulation.roster[id].state.position.y, before[id].y)
                XCTAssertLessThan((simulation.roster[id].state.position - before[id]).length, 0.3)
                let target = simulation.keeperRegroupTarget(for: id)!
                XCTAssertGreaterThan(target.y, -36)
            }
            let nearTargets = simulation.roster.filter { $0.team == .blue && !$0.isGoalkeeper }.filter {
                (simulation.keeperRegroupTarget(for: $0.id)! - simulation.roster[keeper].state.position).length < 12
            }
            XCTAssertEqual(nearTargets.map(\.id), [outlet])
            for _ in 0..<180 { simulation.step(dt: tick) }
            XCTAssertTrue(simulation.isHoldingGoalkeeper)
            XCTAssertEqual(simulation.keeperShortOutletID, outlet)
            XCTAssertTrue(opponents.allSatisfy { simulation.roster[$0].state.position.y > -36 })
            XCTAssertEqual(simulation.selectedPlayerID, keeper)
        }
    }

    func testRedCatchSteersSelectedOpponentOutButKeepsManualMovementElsewhere() {
        for eleven in [false, true] {
            var simulation = catchBall(.red, eleven: eleven)
            let selected = simulation.selectedPlayerID
            simulation.player.position = Vector2(x: 4, y: 44)
            simulation.player.velocity = .zero
            simulation.movement = .up
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.selectedPlayerID, selected)
            XCTAssertLessThan(simulation.player.velocity.y, 0, "Inward pressing yields to actual withdrawal movement.")
            XCTAssertEqual(simulation.roster[selected].team, .blue)
            XCTAssertEqual(simulation.goalkeeperPossessionTeam, .red)

            simulation.player.position = Vector2(x: 26, y: 25)
            simulation.player.velocity = .zero
            simulation.movement = Vector2(x: -1, y: 0)
            let before = simulation.player.position
            simulation.step(dt: tick)
            XCTAssertLessThan(simulation.player.position.x, before.x)
            XCTAssertEqual(simulation.player.position.y, before.y, accuracy: 0.00001)
        }
    }

    func testReleaseAndResetClearRegroupingImmediatelyAndNextCatchChoosesHealthyOutlet() {
        var simulation = catchBall(.blue, eleven: true)
        simulation.step(dt: tick)
        let firstOutlet = simulation.keeperShortOutletID!
        simulation.roster[firstOutlet].isSentOff = true
        simulation.step(dt: tick)
        XCTAssertNotEqual(simulation.keeperShortOutletID, firstOutlet)
        let teammate = simulation.keeperShortOutletID!
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.7)
        XCTAssertNil(simulation.keeperShortOutletID)
        XCTAssertNil(simulation.keeperRegroupTarget(for: teammate))
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        simulation.reset()
        XCTAssertNil(simulation.keeperShortOutletID)
        XCTAssertNil(simulation.keeperRegroupTarget(for: teammate))
        assertKickoffShape(simulation, team: .blue)
    }

    func testKeeperNearBoxSideStillHasOnlyOneNearbyOutletTarget() {
        var simulation = catchBall(.blue, eleven: true)
        simulation.player.position = Vector2(x: 19, y: -37)
        simulation.step(dt: tick)
        let keeper = simulation.goalkeeperHoldingID!
        let nearby = simulation.roster.filter { $0.team == .blue && !$0.isGoalkeeper }.filter {
            (simulation.keeperRegroupTarget(for: $0.id)! - simulation.roster[keeper].state.position).length < 12
        }
        XCTAssertEqual(nearby.map(\.id), [simulation.keeperShortOutletID!])
    }

    func testRedKeeperUsesReadyOutletPromptlyButAllowsWithdrawalBeforeBlockedRelease() {
        for blocked in [false, true] {
            var simulation = catchBall(.red, eleven: true)
            let keeper = simulation.goalkeeperHoldingID!
            let candidate = simulation.roster.first { $0.team == .red && !$0.isGoalkeeper }!.id
            simulation.roster[candidate].state.position = simulation.roster[keeper].state.position
                + Vector2(x: -6.5, y: -5.5)
            simulation.roster[candidate].state.velocity = .zero
            if blocked {
                simulation.player.position = Vector2(x: 3, y: 44)
                simulation.player.velocity = .zero
                simulation.movement = .up
            }
            for _ in 0..<54 { simulation.step(dt: tick) }
            if blocked {
                XCTAssertEqual(simulation.goalkeeperHoldingID, keeper, "A nearby opponent needs actual time to withdraw.")
                XCTAssertLessThan(simulation.player.position.y, 42)
                for _ in 0..<150 where simulation.goalkeeperHoldingID != nil { simulation.step(dt: tick) }
                XCTAssertNil(simulation.goalkeeperHoldingID, "The opposition cannot stall indefinitely waiting for a perfect shape.")
            } else {
                XCTAssertNil(simulation.goalkeeperHoldingID, "A ready safe outlet does not impose the fallback three-second wait.")
                XCTAssertEqual(simulation.ball.mode, .pass)
                XCTAssertEqual(simulation.lastTouchTeam, .red)
            }
            XCTAssertNil(simulation.keeperShortOutletID)
            XCTAssertNil(simulation.keeperRegroupTarget(for: candidate))
        }
    }
}
