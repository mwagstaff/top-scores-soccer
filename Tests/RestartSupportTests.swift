import XCTest
@testable import TopScoresSoccer

final class RestartSupportTests: XCTestCase {
    private func roster(teamSize: Int = 5) -> [Footballer] {
        (0..<(teamSize * 2)).map { id in
            let blue = id < teamSize
            return Footballer(id: id, team: blue ? .blue : .red,
                state: PlayerState(position: Vector2(x: Double(id % 3 - 1) * 8, y: blue ? -14 : 14)),
                isGoalkeeper: id == teamSize - 1 || id == teamSize * 2 - 1)
        }
    }

    private func restart(_ kind: MatchRestartKind = .freeKick, team: Team = .blue,
                         position: Vector2 = .zero, taker: Int = 0) -> MatchRestart {
        MatchRestart(kind: kind, team: team, position: position, takerID: taker)
    }

    private func assertShortTargets(_ layout: RestartSupport.Layout, origin: Vector2,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(layout.outletIDs.count, 2, file: file, line: line)
        XCTAssertEqual(layout.outletTargets.count, 2, file: file, line: line)
        let targets = layout.outletIDs.compactMap { layout.outletTargets[$0] }
        for target in targets {
            XCTAssertLessThanOrEqual(abs(target.x), Pitch.width / 2 - 1.19, file: file, line: line)
            XCTAssertLessThanOrEqual(abs(target.y), Pitch.length / 2 - 1.19, file: file, line: line)
            XCTAssertGreaterThanOrEqual((target - origin).length, 5 - 0.000001, file: file, line: line)
            XCTAssertLessThanOrEqual((target - origin).length, 9 + 0.000001, file: file, line: line)
        }
        if targets.count == 2 {
            XCTAssertGreaterThanOrEqual((targets[0] - targets[1]).length, 4.5, file: file, line: line)
        }
    }

    func testTwoNearestHealthyOutfieldPlayersOfferSupportWithoutPullingWholeTeamIn() {
        for teamSize in [5, 11] {
            var players = roster(teamSize: teamSize)
            players[1].state.position = Vector2(x: 3, y: 0)
            players[2].state.position = Vector2(x: -4, y: -1)
            players[teamSize - 1].state.position = .up
            players[teamSize].state.position = Vector2(x: 1, y: 0)
            let result = RestartSupport.layout(for: restart(), roster: players)
            XCTAssertEqual(Set(result.outletIDs), [1, 2])
            XCTAssertEqual(result.outletTargets.count, 2)
            XCTAssertNil(result.outletTargets[0])
            XCTAssertNil(result.outletTargets[teamSize - 1])
            XCTAssertEqual(result.opponentTargets.count, teamSize)
        }
    }

    func testExistingOutletIdentitySurvivesMovementAndReplacesUnavailablePlayers() {
        var players = roster(teamSize: 11)
        players[1].state.position = Vector2(x: 3, y: 0)
        players[2].state.position = Vector2(x: -4, y: 0)
        let initial = RestartSupport.layout(for: restart(), roster: players)
        XCTAssertEqual(initial.outletIDs, [1, 2])
        players[3].state.position = Vector2(x: 1, y: 0)
        let stable = RestartSupport.layout(for: restart(), roster: players, previousOutletIDs: initial.outletIDs)
        XCTAssertEqual(stable.outletIDs, initial.outletIDs)
        players[1].isSentOff = true
        players[2].fallProgress = 0.5
        players[3].isTackling = true
        players[4].recoveryProgress = 0.5
        let changed = RestartSupport.layout(for: restart(), roster: players, unavailableIDs: [5],
            previousOutletIDs: initial.outletIDs)
        XCTAssertEqual(changed.outletIDs.count, 2)
        XCTAssertTrue(Set(changed.outletIDs).isDisjoint(with: [0, 1, 2, 3, 4, 5, 10]))
    }

    func testOnlyOneEligibleTeammateStillOffersOneUsefulOutlet() {
        var players = roster()
        players[2].isSentOff = true
        players[3].isSliding = true
        let result = RestartSupport.layout(for: restart(.throwIn, position: Vector2(x: 34, y: 0)), roster: players)
        XCTAssertEqual(result.outletIDs, [1])
        XCTAssertNotNil(result.outletTargets[1])
    }

    func testThrowInOptionsStayInsideAndApartAtBothTouchlinesAndCorners() {
        for teamSize in [5, 11] {
            for team in [Team.blue, .red] {
                for side in [-1.0, 1.0] {
                    for y in [-52.2, 0, 52.2] {
                        let origin = Vector2(x: 34 * side, y: y)
                        let context = restart(.throwIn, team: team, position: origin, taker: team == .blue ? 0 : teamSize)
                        let players = roster(teamSize: teamSize)
                        let result = RestartSupport.layout(for: context, roster: players)
                        assertShortTargets(result, origin: origin)
                        for (id, target) in result.opponentTargets {
                            XCTAssertTrue(RestartSupport.isLegalOpponentPosition(target, team: players[id].team, restart: context))
                            XCTAssertGreaterThanOrEqual((target - origin).length, 2 - 0.000001)
                        }
                    }
                }
            }
        }
    }

    func testCentralFreeKickSupportLeavesForwardShootingLaneOpenForBothTeams() {
        for team in [Team.blue, .red] {
            let players = roster()
            let context = restart(team: team, taker: team == .blue ? 0 : 5)
            let result = RestartSupport.layout(for: context, roster: players)
            assertShortTargets(result, origin: .zero)
            let attack = team == .blue ? 1.0 : -1.0
            for target in result.outletTargets.values {
                XCTAssertLessThanOrEqual(target.y * attack, 0.000001)
                XCTAssertTrue(target.y * attack < -2.5 || abs(target.x) > 2.5)
            }
        }
    }

    func testFreeKickShortOptionsRemainPossibleAtEveryCorner() {
        for team in [Team.blue, .red] {
            for x in [-33.5, 33.5] {
                for y in [-52.0, 52.0] {
                    let spot = Vector2(x: x, y: y)
                    let result = RestartSupport.layout(for: restart(.freeKick, team: team,
                        position: spot, taker: team == .blue ? 0 : 5), roster: roster())
                    assertShortTargets(result, origin: spot)
                }
            }
        }
    }

    func testCoincidentOpponentsRetreatToDistinctLegalPositionsAtPitchEdges() {
        for spot in [Vector2.zero, Vector2(x: 33.5, y: 51.5), Vector2(x: -33.5, y: -51.5)] {
            var players = roster(teamSize: 11)
            for id in 11..<22 { players[id].state.position = spot }
            let context = restart(position: spot)
            let result = RestartSupport.layout(for: context, roster: players, freeKickStandBack: 6)
            let targets = (11..<22).compactMap { result.opponentTargets[$0] }
            XCTAssertEqual(targets.count, 11)
            for (index, point) in targets.enumerated() {
                XCTAssertTrue(RestartSupport.isLegalOpponentPosition(point, team: .red, restart: context))
                XCTAssertGreaterThanOrEqual((point - spot).length, 9.15 - 0.000001)
                for earlier in targets.prefix(index) {
                    XCTAssertGreaterThanOrEqual((earlier - point).length, Pitch.playerRadius * 2 + 0.19)
                }
            }
        }
    }

    func testGoalLineExceptionPreservesLegalDefenderWithoutAllowingOtherClosePositions() {
        for team in [Team.blue, .red] {
            let sign = team == .blue ? -1.0 : 1.0
            let context = restart(team: team == .blue ? .red : .blue, position: Vector2(x: 0, y: 47 * sign))
            let onLine = Vector2(x: 1, y: Pitch.length / 2 * sign)
            XCTAssertTrue(RestartSupport.isLegalOpponentPosition(onLine, team: team, restart: context))
            XCTAssertEqual(RestartSupport.legalOpponentTarget(from: onLine, team: team, restart: context), onLine)
            let close = Vector2(x: 1, y: 51 * sign)
            XCTAssertFalse(RestartSupport.isLegalOpponentPosition(close, team: team, restart: context))
            let target = RestartSupport.legalOpponentTarget(from: close, team: team, restart: context)
            XCTAssertTrue(RestartSupport.isLegalOpponentPosition(target, team: team, restart: context))
            XCTAssertEqual(target.y, Pitch.length / 2 * sign)
            XCTAssertFalse(RestartSupport.isLegalOpponentPosition(Vector2(x: 7, y: onLine.y), team: team, restart: context))
            XCTAssertFalse(RestartSupport.isLegalOpponentPosition(onLine, team: team,
                restart: restart(.throwIn, team: team == .blue ? .red : .blue,
                    position: Vector2(x: 34, y: onLine.y))))
        }
    }

    func testDefensiveFreeKickRequiresOpponentsOutsidePenaltyAreaAsWellAsTenYards() {
        for takingTeam in [Team.blue, .red] {
            let sign = takingTeam == .blue ? -1.0 : 1.0
            let opponent: Team = takingTeam == .blue ? .red : .blue
            let context = restart(team: takingTeam, position: Vector2(x: 0, y: sign * 48))
            let inside = Vector2(x: 15, y: sign * 44)
            XCTAssertGreaterThan((inside - context.position).length, 9.15)
            XCTAssertFalse(RestartSupport.isLegalOpponentPosition(inside, team: opponent, restart: context))
            let target = RestartSupport.legalOpponentTarget(from: inside, team: opponent, restart: context)
            XCTAssertTrue(RestartSupport.isLegalOpponentPosition(target, team: opponent, restart: context))
            XCTAssertTrue(abs(target.x) > 20.16 || target.y * sign < Pitch.length / 2 - 16.5)
        }
    }

    func testThrowInDistanceUsesTouchlinePointAndDoesNotApplyFreeKickDistance() {
        let context = restart(.throwIn, position: Vector2(x: 33.5, y: 10))
        let legal = Vector2(x: 31.8, y: 10)
        XCTAssertTrue(RestartSupport.isLegalOpponentPosition(legal, team: .red, restart: context))
        XCTAssertEqual(RestartSupport.legalOpponentTarget(from: legal, team: .red, restart: context), legal)
        let illegal = Vector2(x: 32.3, y: 10)
        XCTAssertFalse(RestartSupport.isLegalOpponentPosition(illegal, team: .red, restart: context))
        let target = RestartSupport.legalOpponentTarget(from: illegal, team: .red, restart: context)
        XCTAssertGreaterThanOrEqual((target - Vector2(x: 34, y: 10)).length, 2 - 0.000001)
        XCTAssertLessThan((target - Vector2(x: 34, y: 10)).length, 3)
    }

    func testGoalKickPlacesOneDefenderAcrossSixYardBoxAndWithdrawsOpponents() throws {
        for teamSize in [5, 11] {
            for team in [Team.blue, .red] {
                for side in [-1.0, 1.0] {
                    var players = roster(teamSize: teamSize)
                    let taker = team == .blue ? teamSize - 1 : teamSize * 2 - 1
                    let attack = team == .blue ? 1.0 : -1.0
                    let position = Vector2(x: side * RestartSupport.goalAreaHalfWidth,
                        y: (-Pitch.length / 2 + RestartSupport.goalAreaDepth) * attack)
                    let opponent: Team = team == .blue ? .red : .blue
                    for id in players.indices where players[id].team == opponent {
                        players[id].state.position = Vector2(x: Double(id % 3 - 1) * 4,
                                                             y: (-Pitch.length / 2 + 10) * attack)
                    }
                    let context = restart(.goalKick, team: team, position: position, taker: taker)
                    let result = RestartSupport.layout(for: context, roster: players)

                    XCTAssertEqual(result.outletIDs.count, 1)
                    let defender = try XCTUnwrap(result.outletIDs.first)
                    let teamIDs = players.filter { $0.team == team && !$0.isGoalkeeper }
                        .sorted { $0.id < $1.id }.map(\.id)
                    XCTAssertTrue(Set(teamIDs.prefix(teamSize == 11 ? 4 : 2)).contains(defender))
                    XCTAssertEqual(result.outletTargets[defender],
                        Vector2(x: -side * RestartSupport.goalAreaHalfWidth, y: position.y))
                    XCTAssertEqual(result.opponentTargets.count, teamSize)
                    for (id, target) in result.opponentTargets {
                        XCTAssertTrue(RestartSupport.isLegalOpponentPosition(target,
                            team: players[id].team, restart: context))
                        XCTAssertFalse(PenaltyRules.insideOwnArea(target, team: team))
                    }
                }
            }
        }
    }

    func testReleaseAndUnrelatedRestartsHaveNoSupportContext() {
        let players = roster()
        XCTAssertTrue(RestartSupport.layout(for: nil, roster: players).outletTargets.isEmpty)
        for kind in [MatchRestartKind.kickoff, .corner, .penalty] {
            let result = RestartSupport.layout(for: restart(kind), roster: players, previousOutletIDs: [1, 2])
            XCTAssertTrue(result.outletIDs.isEmpty)
            XCTAssertTrue(result.outletTargets.isEmpty)
            XCTAssertTrue(result.opponentTargets.isEmpty)
        }
        for kind in [MatchRestartKind.offside, .indirectFreeKick] {
            XCTAssertEqual(RestartSupport.layout(for: restart(kind), roster: players).outletIDs.count, 2)
        }
    }

    func testLayoutIsIndependentOfRosterStorageOrder() {
        let players = roster(teamSize: 11)
        let context = restart(.throwIn, position: Vector2(x: -34, y: 8))
        let first = RestartSupport.layout(for: context, roster: players)
        let reverse = RestartSupport.layout(for: context, roster: players.reversed())
        XCTAssertEqual(first.outletIDs, reverse.outletIDs)
        XCTAssertEqual(first.outletTargets, reverse.outletTargets)
        XCTAssertEqual(first.opponentTargets, reverse.opponentTargets)
    }
}
