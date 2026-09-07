import XCTest
@testable import TopScoresSoccer

final class PenaltyRulesTests: XCTestCase {
    func testOwnAreaIncludesPaintedLinesForBothTeamsOnly() {
        for team in [Team.blue, .red] {
            let attack = team == .blue ? 1.0 : -1.0
            let opposing: Team = team == .blue ? .red : .blue
            for x in [-20.16, 0, 20.16] {
                for depth in [0.0, 8, 16.5] {
                    let spot = Vector2(x: x, y: (-Pitch.length / 2 + depth) * attack)
                    XCTAssertTrue(PenaltyRules.awardsPenalty(at: spot, offender: team, awarded: opposing))
                    XCTAssertFalse(PenaltyRules.awardsPenalty(at: spot, offender: team, awarded: team))
                    XCTAssertFalse(PenaltyRules.awardsPenalty(at: -spot, offender: team, awarded: opposing))
                }
            }
            XCTAssertFalse(PenaltyRules.insideOwnArea(Vector2(x: 20.161, y: -45 * attack), team: team))
            XCTAssertFalse(PenaltyRules.insideOwnArea(Vector2(x: 0, y: (-Pitch.length / 2 + 16.501) * attack), team: team))
        }
    }

    func testNonfiniteCoordinatesCannotAwardPenalty() {
        XCTAssertFalse(PenaltyRules.insideOwnArea(Vector2(x: .nan, y: -42), team: .blue))
        XCTAssertFalse(PenaltyRules.insideOwnArea(Vector2(x: 0, y: -.infinity), team: .blue))
    }

    func testPenaltyMarkAndKeeperLineMirrorBothAttackingDirections() {
        for team in [Team.blue, .red] {
            let mark = PenaltyRules.mark(for: team)
            let keeper = PenaltyRules.goalkeeperPosition(defending: team)
            XCTAssertEqual((keeper - mark).length, 11)
            XCTAssertEqual(abs(keeper.y), Pitch.length / 2)
            XCTAssertEqual(mark.x, 0)
        }
    }

    func testWaitingPlayersStayBehindOutsideAreaAndBeyondPenaltyArc() {
        for team in [Team.blue, .red] {
            let attack = team == .blue ? 1.0 : -1.0
            let defender: Team = team == .blue ? .red : .blue
            for x in stride(from: -34.0, through: 34, by: 2) {
                for y in stride(from: -52.0, through: 52, by: 2) {
                    let point = PenaltyRules.waitingPosition(Vector2(x: x, y: y), attackingTeam: team)
                    XCTAssertFalse(PenaltyRules.insideOwnArea(point, team: defender))
                    XCTAssertLessThan(point.y * attack, PenaltyRules.mark(for: team).y * attack)
                    XCTAssertGreaterThanOrEqual((point - PenaltyRules.mark(for: team)).length, 9.15)
                    XCTAssertLessThanOrEqual(abs(point.x), Pitch.width / 2)
                    XCTAssertLessThanOrEqual(abs(point.y), Pitch.length / 2)
                }
            }
        }
    }

    func testCrowdedFullRostersReceiveDistinctLegalWaitingPositionsDeterministically() {
        for team in [Team.blue, .red] {
            let attack = team == .blue ? 1.0 : -1.0
            let defender: Team = team == .blue ? .red : .blue
            let participantPositions = [PenaltyRules.mark(for: team) - .up * attack * 1.2,
                                       PenaltyRules.goalkeeperPosition(defending: team)]
            func placement() -> [Vector2] {
                var occupied = participantPositions
                for _ in 0..<20 {
                    occupied.append(PenaltyRules.waitingPosition(Vector2(x: 0, y: 45 * attack),
                        attackingTeam: team, occupied: occupied))
                }
                return occupied
            }
            let result = placement()
            XCTAssertEqual(result, placement())
            for index in 2..<result.count {
                let point = result[index]
                XCTAssertFalse(PenaltyRules.insideOwnArea(point, team: defender))
                XCTAssertLessThan(point.y * attack, PenaltyRules.mark(for: team).y * attack)
                XCTAssertGreaterThanOrEqual((point - PenaltyRules.mark(for: team)).length, 9.15)
                for earlier in 0..<index {
                    XCTAssertGreaterThanOrEqual((point - result[earlier]).length, Pitch.playerRadius * 2 + 0.1)
                }
            }
            XCTAssertEqual(result[1], PenaltyRules.goalkeeperPosition(defending: team))
        }
    }

    func testTapAlwaysShootsGoalwardIncludingNeutralSidewaysAndBackwardAim() throws {
        for team in [Team.blue, .red] {
            let attack = team == .blue ? 1.0 : -1.0
            let mark = PenaltyRules.mark(for: team)
            for aim in [Vector2.zero, .up, -.up, Vector2(x: -1, y: 0), Vector2(x: 1, y: 0)] {
                let shot = try XCTUnwrap(PenaltyMechanics.shot(origin: mark, aim: aim,
                    team: team, heldFor: 0.12, tuning: .defaults))
                XCTAssertGreaterThan(shot.direction.y * attack, 0.8)
                XCTAssertGreaterThan(shot.speed, GameplayTuning.defaults.shotMinSpeed)
                XCTAssertGreaterThan(shot.verticalVelocity, 0)
                XCTAssertFalse(shot.isOverhit)
                if abs(aim.x) > 0 { XCTAssertGreaterThan(shot.direction.x * aim.x, 0) }
            }
        }
    }

    func testHeldPenaltyRetainsSweetSpotAndOverhitShotFlight() throws {
        for team in [Team.blue, .red] {
            let origin = PenaltyRules.mark(for: team)
            let aim = Vector2(x: 0.2, y: team == .blue ? 1 : -1)
            let sweet = try XCTUnwrap(PenaltyMechanics.shot(origin: origin, aim: aim, team: team,
                heldFor: 0.75, tuning: .defaults))
            let overhit = try XCTUnwrap(PenaltyMechanics.shot(origin: origin, aim: aim, team: team,
                heldFor: 1.3, tuning: .defaults))
            XCTAssertFalse(sweet.isOverhit)
            XCTAssertTrue(overhit.isOverhit)
            let sweetTime = (11 + Pitch.ballRadius) / abs(sweet.direction.y * sweet.speed)
            let highTime = (11 + Pitch.ballRadius) / abs(overhit.direction.y * overhit.speed)
            let sweetHeight = sweet.verticalVelocity * sweetTime - 9 * sweetTime * sweetTime
            let highHeight = overhit.verticalVelocity * highTime - 9 * highTime * highTime
            XCTAssertLessThan(sweetHeight + Pitch.ballRadius * 2, Pitch.crossbarHeight)
            XCTAssertGreaterThan(highHeight + Pitch.ballRadius * 2, Pitch.crossbarHeight)
        }
    }
}
