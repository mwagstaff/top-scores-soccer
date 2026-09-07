import XCTest
@testable import TopScoresSoccer

final class AttackingSupportTests: XCTestCase {
    private func player(_ id: Int, _ x: Double, _ y: Double, team: Team = .blue,
                        keeper: Bool = false) -> Footballer {
        var state = PlayerState()
        state.position = Vector2(x: x, y: y)
        return Footballer(id: id, team: team, state: state, isGoalkeeper: keeper)
    }

    private var smallTeam: [Footballer] {
        [player(0, 0, 0), player(1, -10, -5), player(2, 15, -15), player(3, 8, 12),
         player(4, 0, -46, keeper: true), player(5, -15, 38, team: .red),
         player(6, 14, 40, team: .red), player(7, 0, 49, team: .red, keeper: true)]
    }

    private var smallBases: [Int: Vector2] {
        [1: Vector2(x: -14, y: -14), 2: Vector2(x: 14, y: -14), 3: Vector2(x: 12, y: 17)]
    }

    private func targets(_ roster: [Footballer], bases: [Int: Vector2],
                         ball: Vector2 = .zero, line: Double = 42,
                         pass: AttackingSupport.ReleasedPass? = nil) -> [Int: Vector2] {
        var state = BallState()
        state.position = ball
        return AttackingSupport.targets(roster: roster, team: .blue, carrierID: 0,
                                        ball: state, baseTargets: bases, releasedPass: pass,
                                        offsideLine: line)
    }

    func testFiveAsideOffersShortPassForwardRunAndRetainsDefensiveShape() {
        let result = targets(smallTeam, bases: smallBases)
        XCTAssertNil(result[0], "The carrier must keep their own movement intent")
        XCTAssertNil(result[4], "Keeper positioning has its own controller")
        XCTAssertEqual(result.count, 3)
        let short = result[1]!
        XCTAssertGreaterThan(short.length, 6)
        XCTAssertLessThan(short.length, 16)
        XCTAssertGreaterThan(result[3]!.y, 14)
        XCTAssertGreaterThan((result[3]! - short).length, 8)
        XCTAssertEqual(result[2], smallBases[2], "An extra defender keeps the formation's width and depth")
    }

    func testElevenAsideUsesTwoNearbyOptionsTwoRunsAndKeepsOtherPlayersInShape() {
        var roster = [player(0, 0, 0)]
        let positions = [Vector2(x: -25, y: -25), Vector2(x: -8, y: -25),
                         Vector2(x: 8, y: -25), Vector2(x: 25, y: -25),
                         Vector2(x: -10, y: -6), Vector2(x: 10, y: -6),
                         Vector2(x: 25, y: 0), Vector2(x: -9, y: 22), Vector2(x: 9, y: 22)]
        var bases: [Int: Vector2] = [:]
        for (index, position) in positions.enumerated() {
            let id = index + 1
            roster.append(player(id, position.x, position.y))
            bases[id] = position
        }
        roster.append(player(10, 0, -46, keeper: true))
        let result = targets(roster, bases: bases)
        let close = result.values.filter { $0.length < 16 }
        XCTAssertEqual(close.count, 2)
        XCTAssertLessThan(close[0].x * close[1].x, 0, "Short options should give the carrier both sides")
        XCTAssertGreaterThan(result[8]!.y, 15)
        XCTAssertGreaterThan(result[9]!.y, 15)
        XCTAssertGreaterThan(abs(result[8]!.x - result[9]!.x), 10)
        for id in 1...4 { XCTAssertEqual(result[id], bases[id]) }
        XCTAssertEqual(result[7], bases[7], "The wide midfielder must not become another ball chaser")
    }

    func testShortSupportMovesOutOfMarkedEndpointAndBlockedPassingLane() {
        let open = targets(smallTeam, bases: smallBases)[1]!
        var marked = smallTeam
        marked.append(player(8, open.x, open.y, team: .red))
        marked.append(player(9, open.x * 0.5, open.y * 0.5, team: .red))
        let offered = targets(marked, bases: smallBases)[1]!
        XCTAssertGreaterThan((offered - open).length, 5)
        XCTAssertGreaterThan((offered - marked[8].state.position).length, 4)
        XCTAssertGreaterThan(distance(marked[9].state.position, toSegmentFrom: .zero, to: offered), 2.8)
        XCTAssertLessThan(offered.length, 17, "Avoiding a marker should still create a short pass")
    }

    func testRunnerFindsDefenderGapInsteadOfRunningDirectlyAtMarker() {
        let open = targets(smallTeam, bases: smallBases)[3]!
        var marked = smallTeam
        marked.append(player(8, open.x, open.y, team: .red))
        let run = targets(marked, bases: smallBases)[3]!
        XCTAssertGreaterThan((run - open).length, 4)
        XCTAssertGreaterThan(run.y, 10, "The open alternative must remain a forward run")
        XCTAssertGreaterThan(abs(run.x - open.x), 3, "Find a different lane, not merely the marker's feet")
    }

    func testUnreleasedRunnerRecoversBehindLineWithRoomForBraking() {
        var roster = smallTeam
        roster[3].state.position = Vector2(x: 12, y: 31)
        roster[3].state.velocity = Vector2(x: 0, y: 9)
        var bases = smallBases
        bases[3] = Vector2(x: 12, y: 35)
        let result = targets(roster, bases: bases, line: 20)
        for destination in result.values { XCTAssertLessThanOrEqual(destination.y, 18.8 + 0.000001) }
        XCTAssertLessThan(result[3]!.y, roster[3].state.position.y)
        XCTAssertGreaterThan(result[3]!.y, 14, "The forward should stage near the line, not retreat into midfield")
    }

    func testReleasedReceiverPursuesThroughBallPastLineAndPasserOffersReturn() {
        var roster = smallTeam
        roster[3].state.position = Vector2(x: 12, y: 17)
        let destination = Vector2(x: 18, y: 35)
        let pass = AttackingSupport.ReleasedPass(receiverID: 3, destination: destination)
        let result = targets(roster, bases: smallBases, ball: Vector2(x: 5, y: 12), line: 20, pass: pass)
        XCTAssertEqual(result[3], destination, "Only kick-time eligibility matters after the pass is released")
        XCTAssertNotNil(result[0], "The passer must move into a return lane")
        XCTAssertGreaterThan(result[0]!.y, 8)
        XCTAssertGreaterThan((result[0]! - roster[3].state.position).length, 5)
        XCTAssertLessThan((result[0]! - roster[3].state.position).length, 17)
        for (id, target) in result where id != 3 { XCTAssertLessThanOrEqual(target.y, 18.8 + 0.000001) }
    }

    func testBothTeamsReceiveExactlyMirroredTargets() {
        let blue = targets(smallTeam, bases: smallBases, ball: Vector2(x: 3, y: 4), line: 22)
        var redRoster = smallTeam.map { source in
            var result = player(source.id, -source.state.position.x, -source.state.position.y,
                                team: source.team == .blue ? .red : .blue, keeper: source.isGoalkeeper)
            result.state.facing = -source.state.facing
            return result
        }
        redRoster.reverse()
        var ball = BallState()
        ball.position = Vector2(x: -3, y: -4)
        let red = AttackingSupport.targets(roster: redRoster, team: .red, carrierID: 0, ball: ball,
                                           baseTargets: smallBases.mapValues { -$0 }, offsideLine: 22)
        XCTAssertEqual(Set(blue.keys), Set(red.keys))
        for (id, destination) in blue { XCTAssertEqual(red[id], -destination) }
    }

    func testMissingExplicitLineUsesActiveSecondLastOpponentAndBall() {
        var roster = smallTeam
        roster[5].state.position.y = 18
        roster[6].state.position.y = 22
        roster[7].state.position.y = 49
        roster[6].isSentOff = true
        var ball = BallState()
        ball.position = .zero
        var bases = smallBases
        bases[3] = Vector2(x: 12, y: 40)
        let held = AttackingSupport.targets(roster: roster, team: .blue, carrierID: 0,
                                           ball: ball, baseTargets: bases)
        XCTAssertLessThanOrEqual(held[3]!.y, 16.8 + 0.000001)
        ball.position.y = 30
        let beyondDefenders = AttackingSupport.targets(roster: roster, team: .blue, carrierID: 0,
                                                       ball: ball, baseTargets: bases)
        XCTAssertGreaterThan(beyondDefenders[3]!.y, 24, "Players can advance behind a ball beyond the defenders")
        XCTAssertLessThanOrEqual(beyondDefenders[3]!.y, 28.8 + 0.000001)
    }

    func testSentOffFallenRecoveringAndSlidingPlayersAreNotGivenRunDuties() {
        var roster = smallTeam
        roster[1].isSentOff = true
        roster[2].recoveryProgress = 0.5
        roster[3].fallProgress = 0.7
        roster.append(player(8, -8, 4))
        roster[8].isSliding = true
        roster.append(player(9, 8, 4))
        let result = targets(roster, bases: smallBases)
        XCTAssertEqual(Set(result.keys), [9])
        XCTAssertGreaterThan(result[9]!.length, 6)
        XCTAssertLessThan(result[9]!.length, 16)
    }

    func testWideAttacksKeepTargetsInBoundsAndOfferAnInfieldPass() {
        let ball = Vector2(x: 32, y: 42)
        var roster = smallTeam
        roster[0].state.position = ball
        roster[1].state.position = Vector2(x: 29, y: 33)
        roster[3].state.position = Vector2(x: 20, y: 43)
        let bases = [1: Vector2(x: 29, y: 33), 2: Vector2(x: -20, y: 12), 3: Vector2(x: 28, y: 55)]
        let result = targets(roster, bases: bases, ball: ball, line: 50)
        for destination in result.values {
            XCTAssertLessThanOrEqual(abs(destination.x), 30)
            XCTAssertLessThanOrEqual(abs(destination.y), 48.5)
        }
        XCTAssertLessThan(result[1]!.x, ball.x - 5)
        XCTAssertGreaterThan((result[1]! - result[3]!).length, 4.5)
    }

    func testRosterOrderDoesNotChangeAssignmentsAndInputIsNotMutated() {
        let roster = smallTeam
        let first = targets(roster, bases: smallBases)
        XCTAssertEqual(first, targets(Array(roster.reversed()), bases: smallBases))
        XCTAssertEqual(first, targets(roster, bases: smallBases))
        XCTAssertEqual(roster[3].state.position, Vector2(x: 8, y: 12))
    }

    func testNoTeammatesProducesNoArtificialSupportPlayer() {
        XCTAssertTrue(targets([], bases: [:]).isEmpty)
        XCTAssertTrue(targets([player(0, 0, 0)], bases: [:]).isEmpty)
    }

    private func distance(_ point: Vector2, toSegmentFrom start: Vector2, to end: Vector2) -> Double {
        let segment = end - start
        let fraction = max(0, min(1, (point - start).dot(segment) / segment.lengthSquared))
        return (point - start - segment * fraction).length
    }
}
