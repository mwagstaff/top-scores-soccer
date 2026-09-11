import XCTest
@testable import TopScoresSoccer

final class CrossingMatchTests: XCTestCase {
    private let tick = 1.0 / 60

    /// Take a real kickoff and acquire the winger's ball in live match play, leaving the
    /// normal offside snapshot, contact rules and scoring enabled throughout the test.
    private func matchWing(north: Bool, side: Double = 1) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var game = FootballSimulation(tuning: tuning, mode: .match, chooseStartingEnds: { north })
        game.pressAction()
        game.releaseAction(heldFor: 0.12)
        game.cancelInput()
        let attack = game.ends.attackSign(for: .blue)
        for id in game.roster.indices {
            game.roster[id].state = PlayerState(position: Vector2(x: id.isMultiple(of: 2) ? -28 : 28,
                y: (game.roster[id].team == .blue ? -30 : 46) * attack), facing: .up * attack)
        }
        game.roster[4].state.position = Vector2(x: 28, y: -49 * attack)
        game.roster[9].state.position = Vector2(x: 28, y: 50 * attack)
        game.roster[0].state.position = Vector2(x: side * 26, y: 36 * attack)
        game.roster[1].state.position = Vector2(x: 0, y: 41 * attack)
        for (id, role) in [(0, "M"), (1, "F")] {
            game.roster[id].clubPlayer = ClubPlayer(id: "cross-match-\(id)", name: "Cross player",
                position: role, rating: 95, appearance: .generated(for: "cross-match-\(id)"))
        }
        game.ball = BallState(position: game.roster[0].state.position + .up * (1.1 * attack), mode: .free)
        game.step(dt: tick)
        XCTAssertNil(game.matchRestart)
        XCTAssertEqual(game.selectedPlayerID, 0)
        XCTAssertTrue(game.hasControl)
        XCTAssertEqual(game.ends.blueAttacksNorth, north)
        game.movement = .up * attack
        return game
    }

    private func cross(_ game: inout FootballSimulation) {
        game.pressAction()
        game.releaseAction(heldFor: 0.75)
        XCTAssertEqual(game.crossCount, 1)
        XCTAssertEqual(game.lastKickKind, "cross")
        XCTAssertTrue(game.isCrossInFlight)
    }

    func testLiveMatchCrossAndTimedHeaderScoreForBlueAtEitherPhysicalGoal() {
        for north in [true, false] {
            var scoredForThisEnd = false
            for side in [-1.0, 1] {
                var game = matchWing(north: north, side: side)
                let attack = game.ends.attackSign(for: .blue)
                XCTAssertTrue(game.canCross)
                cross(&game)
                XCTAssertEqual(game.selectedPlayerID, 1)
                XCTAssertLessThan(game.ball.velocity.x * side, -15)
                var attempted = false
                for _ in 0..<150 where game.headerCount == 0 && game.phase == .playing {
                    if !attempted, game.headingPlayerID == 1, game.ball.verticalVelocity < 0,
                       let preparation = HeadingMechanics.preferredContactDelay(ball: game.ball,
                           player: game.roster[1], window: HeadingMechanics.prepareWindow, gravity: game.tuning.ballGravity),
                       (0.09...0.15).contains(preparation) {
                        game.pressAction()
                        game.releaseAction(heldFor: 0.08)
                        attempted = true
                    }
                    game.step(dt: tick)
                }
                XCTAssertTrue(attempted, "The physically delivered cross must offer a header at either end.")
                XCTAssertEqual(game.lastHeaderPlayerID, 1)
                XCTAssertEqual(game.headerCount, 1)
                XCTAssertEqual(game.ball.mode, .shot)
                XCTAssertGreaterThan(game.ball.velocity.y * attack, 12)
                XCTAssertEqual(game.lastTouchTeam, .blue)
                XCTAssertEqual(game.lastDeliberatePlayTeam, .blue)
                XCTAssertEqual(game.offsideCount, 0)
                for _ in 0..<100 where game.phase == .playing { game.step(dt: tick) }
                if case .goal(let physicalNorth) = game.phase {
                    scoredForThisEnd = true
                    XCTAssertEqual(physicalNorth, north)
                    XCTAssertEqual(game.northGoals, 1, "The match score belongs to blue even when blue attacks south.")
                }
                XCTAssertEqual(game.southGoals, 0)
            }
            XCTAssertTrue(scoredForThisEnd, "Well-prepared headers must have a physical scoring chance at both ends.")
        }
    }

    func testCrossExcludesOffsideStrikerAndChoosesAnOnsideRunnerAtBothEnds() {
        for north in [true, false] {
            var game = matchWing(north: north)
            let attack = game.ends.attackSign(for: .blue)
            for id in 5..<9 { game.roster[id].state.position.y = 39 * attack }
            game.roster[1].state.position.y = 45 * attack
            XCTAssertFalse(game.canCross, "An offside striker alone cannot enable an assisted cross.")
            game.roster[3].state.position = Vector2(x: 4, y: 37.5 * attack)
            XCTAssertTrue(game.canCross)
            cross(&game)
            XCTAssertEqual(game.selectedPlayerID, 3)
            XCTAssertEqual(game.offsideCount, 0, "Offside position itself does not stop an uninvolved cross.")
            XCTAssertEqual(game.phase, .playing)
        }
    }

    func testOffsideAttackerReturningToCrossStillCannotHeadItAtEitherEnd() {
        for north in [true, false] {
            var game = matchWing(north: north)
            let attack = game.ends.attackSign(for: .blue)
            for id in 5..<9 { game.roster[id].state.position.y = 39 * attack }
            game.roster[1].state.position.y = 45 * attack
            game.roster[3].state.position = Vector2(x: 4, y: 37.5 * attack)
            cross(&game)
            XCTAssertEqual(game.selectedPlayerID, 3)
            // Bring the excluded striker back onside after release and put the actual
            // crossing ball at header contact. The launch snapshot must still apply.
            let returned = Vector2(x: 0, y: 38 * attack)
            game.roster[1].state = PlayerState(position: returned, facing: .up * attack)
            game.ball = BallState(position: returned + .up * attack,
                velocity: .up * (6 * attack), mode: .pass, height: 1.7, verticalVelocity: -1)
            XCTAssertEqual(game.headingPlayerID, 1)
            game.pressAction()
            game.releaseAction(heldFor: 0.08)
            XCTAssertEqual(game.phase, .restart(kind: .offside, team: .red))
            XCTAssertEqual(game.matchRestart?.position, returned)
            XCTAssertEqual(game.offsideCount, 1)
            XCTAssertEqual(game.headerCount, 0)
            XCTAssertNil(game.lastHeaderPlayerID)
            XCTAssertEqual(game.northGoals + game.southGoals, 0)
            XCTAssertEqual(game.foulCount, 0)
            XCTAssertFalse(game.isCrossInFlight)
        }
    }

    func testOppositionCanCrossAndHeadTowardItsAttackingGoalAtBothEnds() {
        for north in [true, false] {
            var game = matchWing(north: north)
            let attack = game.ends.attackSign(for: .red)
            game.movement = .zero
            game.tuning.aiSpeedScale = 0.1 // Keep the isolated shape stable while enabling autonomous headers.
            for id in game.roster.indices {
                game.roster[id].state = PlayerState(position: Vector2(x: id.isMultiple(of: 2) ? -28 : 28,
                    y: (game.roster[id].team == .red ? -30 : 46) * attack), facing: .up * attack)
            }
            game.roster[4].state.position = Vector2(x: 28, y: 50 * attack)
            game.roster[9].state.position = Vector2(x: 28, y: -49 * attack)
            game.roster[5].state.position = Vector2(x: 26, y: 36 * attack)
            game.roster[6].state.position = Vector2(x: 0, y: 41 * attack)
            for (id, role) in [(5, "M"), (6, "F")] {
                game.roster[id].clubPlayer = ClubPlayer(id: "red-cross-\(id)", name: "Opposition player",
                    position: role, rating: 95, appearance: .generated(for: "red-cross-\(id)"))
            }
            game.ball = BallState(position: game.roster[5].state.position + .up * (1.1 * attack), mode: .free)
            var sawCross = false
            for _ in 0..<180 where game.lastHeaderPlayerID == nil && game.phase == .playing {
                game.step(dt: tick)
                if game.isCrossInFlight && !sawCross {
                    sawCross = true
                    XCTAssertLessThan(game.ball.velocity.x, -15)
                }
            }
            XCTAssertTrue(sawCross)
            XCTAssertEqual(game.lastHeaderPlayerID, 6)
            XCTAssertEqual(game.ball.mode, .shot)
            XCTAssertGreaterThan(game.ball.velocity.y * attack, 12)
            XCTAssertEqual(game.lastTouchTeam, .red)
            XCTAssertEqual(game.lastDeliberatePlayTeam, .red)
            XCTAssertEqual(game.offsideCount, 0)
            XCTAssertEqual(game.crossCount, 0, "Human action diagnostics must not count an autonomous cross.")
            XCTAssertEqual(game.headerCount, 0)
        }
    }
}
