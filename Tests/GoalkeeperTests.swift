import XCTest
@testable import TopScoresSoccer

final class GoalkeeperTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func keeper(_ position: Vector2 = Vector2(x: 0, y: -50.3)) -> PlayerState {
        PlayerState(position: position, velocity: .zero, facing: .up)
    }

    private func ball(_ position: Vector2, velocity: Vector2 = .zero,
                      height: Double = 0, lift: Double = 0) -> BallState {
        BallState(position: position, velocity: velocity, mode: .free,
                  height: height, verticalVelocity: lift)
    }

    private func move(_ keeper: inout PlayerState, intent: GoalkeeperAI.Intent) {
        keeper.velocity = intent.velocity
        keeper.position += intent.velocity * tick
        keeper.facing = intent.facing
    }

    func testBothTeamsTrackTheBallBetweenTheirOwnGoalAndPlay() {
        var blue = keeper()
        var red = keeper(-blue.position)
        var blueState = GoalkeeperAI.State()
        var redState = GoalkeeperAI.State()
        let blueBall = ball(Vector2(x: 16, y: -20))
        let redBall = ball(-blueBall.position)
        for _ in 0..<120 {
            let a = GoalkeeperAI.step(state: &blueState, keeper: blue, team: .blue,
                                      ball: blueBall, ownsBall: false, dt: tick)
            let b = GoalkeeperAI.step(state: &redState, keeper: red, team: .red,
                                      ball: redBall, ownsBall: false, dt: tick)
            XCTAssertEqual(a.velocity.x, -b.velocity.x, accuracy: 0.000001)
            XCTAssertEqual(a.velocity.y, -b.velocity.y, accuracy: 0.000001)
            move(&blue, intent: a)
            move(&red, intent: b)
        }
        XCTAssertGreaterThan(blue.position.x, 0.5)
        XCTAssertLessThan(blue.position.x, blueBall.position.x)
        XCTAssertGreaterThan(blue.position.y, -Pitch.length / 2)
        XCTAssertLessThan(blue.position.y, blueBall.position.y)
        XCTAssertTrue(GoalkeeperAI.isInOwnBox(blue.position, team: .blue))
        XCTAssertTrue(GoalkeeperAI.isInOwnBox(red.position, team: .red))
    }

    func testSlowBallInOwnBoxIsApproachedWithoutLeavingTheBox() {
        var player = keeper()
        var state = GoalkeeperAI.State()
        let loose = ball(Vector2(x: 6, y: -44))
        let initialDistance = (loose.position - player.position).length
        for _ in 0..<90 {
            let intent = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                           ball: loose, ownsBall: false, dt: tick)
            XCTAssertLessThanOrEqual(intent.velocity.length, GoalkeeperAI.Configuration.defaults.movementSpeed + 0.000001)
            move(&player, intent: intent)
            XCTAssertTrue(GoalkeeperAI.isInOwnBox(player.position, team: .blue))
        }
        XCTAssertLessThan((loose.position - player.position).length, initialDistance - 4)
    }

    func testDistantBallDoesNotPullKeeperOutOfPosition() {
        var player = keeper()
        var state = GoalkeeperAI.State()
        for _ in 0..<300 {
            let intent = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                           ball: ball(Vector2(x: 30, y: 25)), ownsBall: false, dt: tick)
            move(&player, intent: intent)
            XCTAssertTrue(GoalkeeperAI.isInOwnBox(player.position, team: .blue))
        }
        XCTAssertLessThan(player.position.y, -47)
        XCTAssertLessThan(abs(player.position.x), Pitch.goalWidth / 2)
    }

    func testDiveCommitsInOneDirectionAndCannotTeleportOrInstantlyDiveAgain() {
        var player = keeper()
        var state = GoalkeeperAI.State()
        let shot = ball(Vector2(x: 3, y: -40), velocity: Vector2(x: 0, y: -35))
        let start = player.position
        let first = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                      ball: shot, ownsBall: false, dt: tick)
        XCTAssertTrue(first.isDiving)
        XCTAssertGreaterThan(first.facing.x, 0.99)
        XCTAssertGreaterThan(first.diveProgress, 0)
        XCTAssertEqual(first.saveReach, GoalkeeperAI.Configuration.defaults.diveReach)
        move(&player, intent: first)
        XCTAssertLessThanOrEqual((player.position - start).length,
                                GoalkeeperAI.Configuration.defaults.diveSpeed * tick + 0.000001)
        XCTAssertGreaterThan((shot.position - player.position).length, 8)

        let oppositeShot = ball(Vector2(x: -3, y: -40), velocity: Vector2(x: 0, y: -35))
        let next = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                     ball: oppositeShot, ownsBall: false, dt: tick)
        XCTAssertTrue(next.isDiving)
        XCTAssertGreaterThan(next.facing.x, 0.99, "A committed dive cannot reverse to follow a different shot.")
        move(&player, intent: next)
        for _ in 0..<20 {
            let intent = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                           ball: oppositeShot, ownsBall: false, dt: tick)
            move(&player, intent: intent)
        }
        XCTAssertEqual(state.diveRemaining, 0)
        XCTAssertGreaterThan(state.recoveryRemaining, 0)
        let recovering = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                          ball: shot, ownsBall: false, dt: tick)
        XCTAssertFalse(recovering.isDiving)
        XCTAssertEqual(recovering.saveReach, GoalkeeperAI.Configuration.defaults.recoveryReach)
        XCTAssertLessThan(recovering.velocity.length, GoalkeeperAI.Configuration.defaults.movementSpeed * 0.5)
    }

    func testUnreachableOrRisingLobDoesNotTriggerAHorizontalDive() {
        for attempt in [ball(Vector2(x: 9, y: -40), velocity: Vector2(x: 0, y: -35)),
                        ball(Vector2(x: 3, y: -40), velocity: Vector2(x: 0, y: -35), height: 1.8, lift: 8)] {
            var state = GoalkeeperAI.State()
            let intent = GoalkeeperAI.step(state: &state, keeper: keeper(), team: .blue,
                                           ball: attempt, ownsBall: false, dt: tick)
            XCTAssertFalse(intent.isDiving)
            XCTAssertEqual(state.diveRemaining, 0)
        }
    }

    func testReachableLowModerateSpeedBallCanBeCaught() {
        let player = keeper()
        let incoming = ball(player.position + Vector2(x: 0.2, y: 0.8),
                            velocity: Vector2(x: 0, y: -12), height: 1.2)
        XCTAssertEqual(GoalkeeperAI.saveOutcome(ball: incoming, keeper: player, team: .blue,
                                                state: GoalkeeperAI.State()), .catchBall)
    }

    func testHardShotIsParriedUpfieldAndSidewaysWithLimitedPace() {
        for team in [Team.blue, .red] {
            let attack = team == .blue ? 1.0 : -1.0
            let player = keeper(Vector2(x: 0, y: -50.3 * attack))
            let incoming = ball(player.position + Vector2(x: 0.3, y: 0.7 * attack),
                                velocity: Vector2(x: 0, y: -35 * attack))
            guard case .parry(let velocity, let lift) = GoalkeeperAI.saveOutcome(
                ball: incoming, keeper: player, team: team, state: GoalkeeperAI.State()) else {
                return XCTFail("A reachable powerful shot should rebound rather than becoming a guaranteed catch.")
            }
            XCTAssertGreaterThan(velocity.y * attack, 0)
            XCTAssertGreaterThan(abs(velocity.x), 5)
            XCTAssertLessThan(velocity.length, incoming.velocity.length)
            XCTAssertLessThanOrEqual(velocity.length, 24)
            XCTAssertGreaterThan(lift, 0)
        }
    }

    func testHighShotCanBeParriedButLobAboveReachIsMissed() {
        let player = keeper()
        let point = player.position + .up * 0.7
        let reachableHigh = ball(point, velocity: -.up * 12, height: 2)
        guard case .parry = GoalkeeperAI.saveOutcome(ball: reachableHigh, keeper: player, team: .blue,
                                                     state: GoalkeeperAI.State()) else {
            return XCTFail("A standing keeper can reach a high ball without necessarily holding it.")
        }
        let lob = ball(point, velocity: -.up * 20, height: 2.3)
        XCTAssertLessThan(lob.height, Pitch.crossbarHeight)
        XCTAssertNil(GoalkeeperAI.saveOutcome(ball: lob, keeper: player, team: .blue,
                                              state: GoalkeeperAI.State()))
        var diving = GoalkeeperAI.State()
        diving.diveRemaining = 0.1
        XCTAssertNil(GoalkeeperAI.saveOutcome(ball: reachableHigh, keeper: player, team: .blue, state: diving))
    }

    func testDistantOutOfBoxAndAlreadyCrossedBallsCannotBeCaught() {
        let player = keeper()
        let examples: [(PlayerState, BallState)] = [
            (player, ball(player.position + .up * 3)),
            (keeper(Vector2(x: 0, y: -30)), ball(Vector2(x: 0, y: -30.2))),
            (keeper(Vector2(x: 21, y: -45)), ball(Vector2(x: 21, y: -45.2))),
            (keeper(Vector2(x: 0, y: -52)), ball(Vector2(x: 0, y: -53))),
            (player, ball(player.position + .up * 0.5, height: .nan))
        ]
        for (position, incoming) in examples {
            XCTAssertNil(GoalkeeperAI.saveOutcome(ball: incoming, keeper: position, team: .blue,
                                                  state: GoalkeeperAI.State()))
        }
    }

    func testCatchWaitsBeforeDistributionAndEachNewPossessionGetsItsOwnDelay() {
        var state = GoalkeeperAI.State()
        GoalkeeperAI.recordSave(state: &state, outcome: .catchBall)
        let player = keeper()
        let held = ball(player.position)
        for _ in 0..<38 {
            let intent = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                           ball: held, ownsBall: true, dt: tick)
            XCTAssertFalse(intent.shouldDistribute)
            XCTAssertEqual(intent.velocity, .zero)
            XCTAssertEqual(intent.facing, .up)
            XCTAssertFalse(intent.isDiving)
        }
        let ready = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                      ball: held, ownsBall: true, dt: tick)
        XCTAssertTrue(ready.shouldDistribute)
        _ = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                              ball: held, ownsBall: false, dt: tick)
        let newCatch = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                         ball: held, ownsBall: true, dt: tick)
        XCTAssertFalse(newCatch.shouldDistribute)
        XCTAssertEqual(state.holdingElapsed, tick, accuracy: 0.000001)
    }

    func testDivingCatchKeepsPoseAndDirectionUntilRecoveryBeforeDistribution() {
        var player = keeper()
        var state = GoalkeeperAI.State()
        var configuration = GoalkeeperAI.Configuration.defaults
        configuration.distributionDelay = 0.2 // The physical recovery must still finish first.
        let shot = ball(Vector2(x: -3, y: -40), velocity: Vector2(x: 0, y: -35))
        var extent = 0.0
        for _ in 0..<8 {
            let intent = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                           ball: shot, ownsBall: false, dt: tick, configuration: configuration)
            move(&player, intent: intent)
            extent = intent.diveProgress
        }
        XCTAssertGreaterThan(extent, 0.5)
        GoalkeeperAI.recordSave(state: &state, outcome: .catchBall, configuration: configuration)
        var previousExtent = extent
        for _ in 0..<38 {
            let intent = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                           ball: ball(player.position), ownsBall: true, dt: tick,
                                           configuration: configuration)
            XCTAssertGreaterThan(intent.diveProgress, 0)
            XCTAssertLessThanOrEqual(intent.diveProgress, previousExtent)
            XCTAssertEqual(intent.facing, Vector2(x: -1, y: 0))
            XCTAssertFalse(intent.isDiving)
            XCTAssertFalse(intent.shouldDistribute)
            XCTAssertEqual(intent.velocity, .zero)
            previousExtent = intent.diveProgress
        }
        let recovered = GoalkeeperAI.step(state: &state, keeper: player, team: .blue,
                                          ball: ball(player.position), ownsBall: true, dt: tick,
                                          configuration: configuration)
        XCTAssertTrue(recovered.shouldDistribute)
        XCTAssertEqual(recovered.diveProgress, 0, accuracy: 0.000001)
    }

    func testParryStartsRecoveryAndInvalidStepCannotAdvanceItsTimers() {
        var state = GoalkeeperAI.State()
        GoalkeeperAI.recordSave(state: &state, outcome: .parry(velocity: Vector2(x: 8, y: 6), verticalVelocity: 1))
        XCTAssertEqual(state.recoveryRemaining, GoalkeeperAI.Configuration.defaults.recoveryDuration)
        let initial = state
        for dt in [0, -tick, Double.nan, .infinity] {
            let intent = GoalkeeperAI.step(state: &state, keeper: keeper(), team: .blue,
                                           ball: ball(.zero), ownsBall: true, dt: dt)
            XCTAssertEqual(state, initial)
            XCTAssertEqual(intent.velocity, .zero)
            XCTAssertFalse(intent.shouldDistribute)
        }
        XCTAssertEqual(GoalkeeperAI.contactProfile(state: state).reach,
                       GoalkeeperAI.Configuration.defaults.recoveryReach)
    }
}
