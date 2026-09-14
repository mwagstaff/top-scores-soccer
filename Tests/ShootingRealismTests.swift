import XCTest
@testable import TopScoresSoccer

final class ShootingRealismTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func origin(distance: Double) -> Vector2 {
        Vector2(x: 0, y: Pitch.length / 2 - distance)
    }

    private func matchShot(distance: Double, aim: Vector2, aftertouch: Vector2?,
                           delayFrames: Int = 0) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match,
                                            chooseStartingEnds: { true })
        // Complete the opening restart, then isolate the shooter and opposing keeper.
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        for _ in 0..<40 { simulation.step(dt: tick) }
        let shooter = simulation.selectedPlayerID
        let keeper = simulation.roster.first {
            $0.team == .red && $0.isGoalkeeper
        }!.id
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -30 : 30,
                                                           y: 0)
            simulation.roster[id].state.velocity = .zero
        }
        let goal = Vector2(x: 0, y: Pitch.length / 2)
        simulation.ball = BallState(position: goal - .up * distance, mode: .controlled)
        simulation.roster[shooter].state.position = simulation.ball.position - .up * 1.1
        simulation.roster[shooter].state.facing = .up
        simulation.roster[keeper].state.position = Vector2(x: 0, y: Pitch.length / 2 - 2.2)
        simulation.roster[keeper].state.facing = -.up
        let profile = KickMechanics.distancePower(distance: distance, heldFor: 0,
                                                   tuning: tuning)
        let hold = (profile.sweetSpot.lowerBound + profile.sweetSpot.upperBound) / 2
            * tuning.shotChargeDuration
        simulation.movement = aim
        simulation.pressAction(button: .shoot)
        simulation.releaseAction(heldFor: hold)
        for frame in 0..<180 where simulation.phase == .playing {
            if let aftertouch, frame >= delayFrames { simulation.movement = aftertouch }
            simulation.step(dt: tick)
        }
        return simulation
    }

    func testDistancePowerAsksForAFirmStrikeAndNarrowsWithRange() {
        var previousCentre = 0.0
        var previousWidth = 1.0
        for distance in [6.0, 18, 27.432, 35] {
            let profile = KickMechanics.distancePower(distance: distance, heldFor: 0,
                                                       tuning: .defaults)
            let centre = (profile.sweetSpot.lowerBound + profile.sweetSpot.upperBound) / 2
            let width = profile.sweetSpot.upperBound - profile.sweetSpot.lowerBound
            XCTAssertGreaterThan(centre, 0.55)
            XCTAssertGreaterThan(centre, previousCentre)
            XCTAssertLessThan(width, previousWidth)
            XCTAssertGreaterThan(profile.overhitStart, profile.sweetSpot.upperBound)
            previousCentre = centre
            previousWidth = width
        }
    }

    func testTooMuchPowerRaisesAThirtyYardShotOverTheBar() throws {
        let distance = 27.432 // 30 yards in metres.
        let start = origin(distance: distance)
        let profile = KickMechanics.distancePower(distance: distance, heldFor: 0,
                                                   tuning: .defaults)
        let idealHold = (profile.sweetSpot.lowerBound + profile.sweetSpot.upperBound) / 2
            * GameplayTuning.defaults.shotChargeDuration
        let ideal = try XCTUnwrap(KickMechanics.chargedShot(origin: start, aim: .up,
            facing: .up, team: .blue, heldFor: idealHold, tuning: .defaults,
            ends: MatchEnds(), sequence: 0))
        let overhit = try XCTUnwrap(KickMechanics.chargedShot(origin: start, aim: .up,
            facing: .up, team: .blue, heldFor: 2, tuning: .defaults,
            ends: MatchEnds(), sequence: 0))

        func heightAtGoal(_ shot: KickMechanics.Shot) -> Double {
            let time = (Pitch.length / 2 + Pitch.ballRadius - start.y)
                / (shot.direction.y * shot.speed)
            let ball = BallState(position: start, velocity: shot.direction * shot.speed,
                                 mode: .shot, verticalVelocity: shot.verticalVelocity)
            return BallFlight.height(after: time, ball: ball,
                                     gravity: GameplayTuning.defaults.ballGravity)
        }

        XCTAssertFalse(ideal.isOverhit)
        XCTAssertLessThan(heightAtGoal(ideal) + Pitch.ballRadius * 2, Pitch.crossbarHeight)
        XCTAssertTrue(overhit.isOverhit)
        XCTAssertGreaterThan(heightAtGoal(overhit) + Pitch.ballRadius * 2, Pitch.crossbarHeight)
    }

    func testLongShotGivesKeeperMoreTimeToSetThanCloseShot() {
        func lateralTravel(distance: Double) -> Double {
            var keeper = PlayerState(position: Vector2(x: 0, y: -50.3),
                                     velocity: .zero, facing: .up)
            var state = GoalkeeperAI.State()
            let intercept = 3.4
            let direction = Vector2(x: intercept, y: -distance).normalized
            var ball = BallState(position: keeper.position + .up * distance,
                                 velocity: direction * 38, mode: .shot)
            for _ in 0..<180 where ball.position.y > keeper.position.y + 0.2 {
                let intent = GoalkeeperAI.step(state: &state, keeper: keeper, team: .blue,
                    ball: ball, ownsBall: false, dt: tick)
                keeper.velocity = intent.velocity
                keeper.position += intent.velocity * tick
                keeper.facing = intent.facing
                ball.position += ball.velocity * tick
                BallFlight.advance(&ball, dt: tick)
            }
            return abs(keeper.position.x)
        }

        let close = lateralTravel(distance: 8)
        let long = lateralTravel(distance: 30)
        XCTAssertGreaterThan(long, close + 1,
            "A readable long shot should let the keeper cover substantially more of the goal.")
    }

    func testEquivalentDiveContactIsHarderToMakeBesideThePostThanCentrally() {
        let centralKeeper = PlayerState(position: Vector2(x: -1.6, y: -50.3),
                                        velocity: .zero, facing: .up)
        let cornerKeeper = PlayerState(position: Vector2(x: 1.8, y: -50.3),
                                       velocity: .zero, facing: .up)
        let central = BallState(position: Vector2(x: 0, y: -49.8),
                                velocity: -.up * 34, mode: .shot, height: 0.8)
        let corner = BallState(position: Vector2(x: 3.4, y: -49.8),
                               velocity: -.up * 34, mode: .shot, height: 0.8)
        var diving = GoalkeeperAI.State()
        diving.diveRemaining = 0.1
        XCTAssertNotNil(GoalkeeperAI.saveOutcome(ball: central, keeper: centralKeeper,
                                                 team: .blue, state: diving))
        XCTAssertNil(GoalkeeperAI.saveOutcome(ball: corner, keeper: cornerKeeper,
                                              team: .blue, state: diving))
    }

    func testThirtyYardWorldieIsPossibleWithLateAftertouchTowardTheCorner() {
        let distance = 27.432
        let straight = matchShot(distance: distance, aim: .up, aftertouch: nil)
        let curled = matchShot(distance: distance, aim: .up,
                               aftertouch: Vector2(x: -1, y: 0), delayFrames: 5)
        XCTAssertEqual(straight.goalkeeperSaveCount, 1,
                       "A readable central shot from 30 yards should normally be saved.")
        XCTAssertEqual(curled.northGoals, 1,
                       "A well-timed, bounded swerve toward the post must leave a rare worldie possible.")
    }

}
