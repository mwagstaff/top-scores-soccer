import XCTest
@testable import TopScoresSoccer

/// Integration checks for contacts and input transitions that span match restarts.
final class MatchRulesRegressionTests: XCTestCase {
    private let tick = 1.0 / 60.0

    private func advance(_ simulation: inout FootballSimulation, frames: Int) {
        for _ in 0..<frames { simulation.step(dt: tick) }
    }

    private func liveMatch() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.1)
        simulation.movement = .zero
        let positions = [Vector2(x: -20, y: -15), Vector2(x: 20, y: -15),
                         Vector2(x: -20, y: 10), Vector2(x: 20, y: 10),
                         Vector2(x: 0, y: -50), Vector2(x: -20, y: 25),
                         Vector2(x: 20, y: 25), Vector2(x: -20, y: 40),
                         Vector2(x: 20, y: 40), Vector2(x: 0, y: 50)]
        for id in simulation.roster.indices {
            simulation.roster[id].state.position = positions[id]
            simulation.roster[id].state.velocity = .zero
        }
        simulation.ball = BallState(position: .zero, velocity: .zero, mode: .free)
        advance(&simulation, frames: 20)
        XCTAssertNil(simulation.matchRestart)
        XCTAssertEqual(simulation.phase, .playing)
        return simulation
    }

    func testAttackingMissCreatesAutomaticOppositionKeeperGoalKick() {
        var simulation = liveMatch()
        XCTAssertEqual(simulation.lastTouchTeam, .blue)
        simulation.ball = BallState(position: Vector2(x: 12, y: 52.7),
                                    velocity: Vector2(x: 0, y: 30), mode: .shot)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .restart(kind: .goalKick, team: .red))
        XCTAssertEqual(simulation.matchRestart?.kind, .goalKick)
        XCTAssertEqual(simulation.northGoals, 0)
        let stoppedClock = simulation.matchTimeElapsed
        for _ in 0..<90 where !simulation.isTakingRestart { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.takerID, 9)
        XCTAssertTrue(simulation.roster[9].isGoalkeeper)
        XCTAssertFalse(simulation.roster[simulation.selectedPlayerID].isGoalkeeper)
        XCTAssertEqual(simulation.matchTimeElapsed, stoppedClock)
        for _ in 0..<90 where simulation.isTakingRestart { simulation.step(dt: tick) }
        XCTAssertFalse(simulation.isTakingRestart)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        XCTAssertGreaterThan(simulation.ball.velocity.length, 10)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertEqual(simulation.matchTimeElapsed, stoppedClock, "Waiting and releasing the automatic restart are dead-ball time.")
    }

    func testKeeperParryChangesLastTouchButPostDoesNotAndAwardsCorner() {
        var simulation = liveMatch()
        simulation.roster[9].state.position = Vector2(x: 0, y: 50)
        simulation.ball = BallState(position: Vector2(x: 0.3, y: 48.65),
                                    velocity: Vector2(x: 0, y: 47), mode: .shot)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertNil(simulation.goalkeeperPossessionTeam)

        // The following fixed step is a post contact, which must retain the keeper's last touch.
        simulation.ball = BallState(position: Vector2(x: Pitch.goalWidth / 2, y: 51.7),
                                    velocity: Vector2(x: 0, y: 20), mode: .free)
        simulation.step(dt: tick)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)

        simulation.ball = BallState(position: Vector2(x: 12, y: 52.7),
                                    velocity: Vector2(x: 0, y: 30), mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .restart(kind: .corner, team: .blue))
        XCTAssertEqual(simulation.matchRestart?.team, .blue)
        XCTAssertEqual(simulation.northGoals, 0)
    }

    func testBallAlreadyAcrossGoalCannotBeRescuedByNearbyKeeper() {
        var simulation = liveMatch()
        simulation.roster[9].state.position = Vector2(x: 0, y: Pitch.length / 2 - Pitch.playerRadius)
        simulation.ball = BallState(position: Vector2(x: 0, y: Pitch.length / 2 + Pitch.ballRadius + 0.01),
                                    velocity: Vector2(x: 0, y: -15), mode: .shot)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertEqual(simulation.phase, .goal(north: true))
        XCTAssertEqual(simulation.matchRestart?.kind, .kickoff)
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        XCTAssertNil(simulation.goalkeeperPossessionTeam)
    }

    func testBlueKeeperManuallyThrowsToAnOutfielderAndHandsOverMovementControl() {
        var simulation = liveMatch()
        simulation.ball = BallState(position: simulation.roster[5].state.position + .up,
                                    velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        simulation.roster[4].state.position = Vector2(x: 0, y: -50)
        simulation.roster[2].state.position = Vector2(x: 3, y: -42)
        simulation.ball = BallState(position: Vector2(x: 0.1, y: -48.75),
                                    velocity: Vector2(x: 0, y: -12), mode: .shot)
        for _ in 0..<5 where simulation.goalkeeperPossessionTeam == nil { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.goalkeeperPossessionTeam, .blue)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 1)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertTrue(simulation.isHoldingGoalkeeper)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        let humanKicks = simulation.kickCount
        advance(&simulation, frames: 80)
        XCTAssertEqual(simulation.goalkeeperPossessionTeam, .blue)
        XCTAssertEqual(simulation.kickCount, humanKicks)
        simulation.movement = .up
        XCTAssertEqual(simulation.passTargetID, 2)
        let delivery = simulation.distributionPreviewKind
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertNil(simulation.goalkeeperPossessionTeam)
        XCTAssertEqual(simulation.lastDistributionKind, delivery)
        let receiver = simulation.selectedPlayerID
        XCTAssertEqual(receiver, 2)
        XCTAssertEqual(simulation.passTargetID, receiver)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertEqual(simulation.kickCount, humanKicks + 1)
        let start = simulation.player.position
        simulation.movement = Vector2(x: -1, y: 0)
        advance(&simulation, frames: 4)
        XCTAssertEqual(simulation.selectedPlayerID, receiver)
        XCTAssertLessThan(simulation.player.position.x, start.x)
        XCTAssertFalse(simulation.roster[receiver].isGoalkeeper)
    }

    func testBackpassSelectsKeeperBeforeArrivalAndMustStayAtHisFeet() {
        assertKeeperBackpass(neutralBeforeRelease: false)
    }

    func testBackpassWithNeutralAlreadyAtLaunchReachesKeeperFeet() {
        assertKeeperBackpass(neutralBeforeRelease: true)
    }

    private func assertKeeperBackpass(neutralBeforeRelease: Bool) {
        var simulation = liveMatch()
        simulation.roster[2].state.position = Vector2(x: 0, y: -42)
        simulation.roster[1].state.position = Vector2(x: -4, y: -47)
        simulation.roster[4].state.position = Vector2(x: 0, y: -49)
        simulation.ball = BallState(position: Vector2(x: 0, y: -41), velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.selectedPlayerID, 2)
        XCTAssertTrue(simulation.hasControl)
        simulation.movement = -.up // Keeper is closer to this exact ray than the outfield option.
        simulation.pressAction()
        // Exercise both ordinary lift-after-release and an already-neutral handoff.
        if neutralBeforeRelease { simulation.movement = .zero }
        simulation.releaseAction(heldFor: 0.1)
        XCTAssertEqual(simulation.passTargetID, 4)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertTrue(simulation.isControllingPassReceiver)
        XCTAssertTrue(simulation.isControllingGoalkeeper)
        simulation.movement = .zero
        for _ in 0..<90 where !simulation.hasControl {
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.selectedPlayerID, 4)
            XCTAssertNil(simulation.goalkeeperPossessionTeam)
        }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
        XCTAssertFalse(simulation.isHoldingGoalkeeper)
        for _ in 0..<120 {
            simulation.step(dt: tick)
            XCTAssertTrue(simulation.hasControl)
            XCTAssertEqual(simulation.selectedPlayerID, 4)
            XCTAssertFalse(simulation.isHoldingGoalkeeper)
        }
    }

    func testHeldActionCannotLeakAcrossThrowInPlacementAndClockWaitsForFreshKick() {
        var simulation = liveMatch()
        simulation.roster[5].state.position = Vector2(x: 20, y: 0)
        simulation.ball = BallState(position: Vector2(x: 20, y: 0.8), velocity: .zero, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 0.1)
        simulation.ball = BallState(position: Vector2(x: 34.2, y: 2),
                                    velocity: Vector2(x: 20, y: 0), mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.phase, .restart(kind: .throwIn, team: .blue))
        let stoppedClock = simulation.matchTimeElapsed
        let kicks = simulation.kickCount
        for _ in 0..<90 where !simulation.isTakingRestart { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.matchRestart?.kind, .throwIn)
        XCTAssertTrue(simulation.hasControl)
        XCTAssertNil(simulation.queuedActionKind)
        XCTAssertEqual(simulation.actionStatus, .idle)
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 45)
        XCTAssertEqual(simulation.kickCount, kicks)
        XCTAssertEqual(simulation.ball.velocity, .zero)
        XCTAssertEqual(simulation.matchTimeElapsed, stoppedClock)
        simulation.movement = Vector2(x: -1, y: 0)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.1)
        XCTAssertEqual(simulation.kickCount, kicks + 1)
        XCTAssertFalse(simulation.isTakingRestart)
        simulation.step(dt: tick)
        XCTAssertGreaterThan(simulation.matchTimeElapsed, stoppedClock)
    }

    func testDescendingLobCanClearADivingKeeperThenFitUnderTheBar() {
        var simulation = liveMatch()
        simulation.roster[9].state.position = Vector2(x: 0, y: 50)
        simulation.ball = BallState(position: Vector2(x: 3, y: 40),
                                    velocity: Vector2(x: 0, y: 35), mode: .shot)
        simulation.step(dt: tick)
        XCTAssertGreaterThan(simulation.roster[9].goalkeeperDiveProgress, 0)
        simulation.ball = BallState(position: Vector2(x: 0, y: 48), velocity: Vector2(x: 0, y: 30),
                                    mode: .shot, height: 2.8, verticalVelocity: -9)
        for _ in 0..<30 where simulation.phase == .playing { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.goalkeeperSaveCount, 0)
        XCTAssertEqual(simulation.phase, .goal(north: true))
        XCTAssertEqual(simulation.northGoals, 1)
        XCTAssertLessThanOrEqual(simulation.ball.height + Pitch.ballRadius * 2, Pitch.crossbarHeight)
    }

    func testClockExcludesKickoffWaitAndFullTimeCannotRunOrFireAgain() {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        tuning.matchDuration = 1
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        advance(&simulation, frames: 120)
        XCTAssertEqual(simulation.matchTimeElapsed, 0)
        XCTAssertTrue(simulation.isTakingRestart)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.1)
        simulation.movement = .zero
        for _ in 0..<80 where simulation.phase != .fullTime { simulation.step(dt: tick) }
        XCTAssertEqual(simulation.phase, .fullTime)
        XCTAssertEqual(simulation.matchTimeElapsed, 1)
        XCTAssertEqual(simulation.matchTimeRemaining, 0)
        XCTAssertNil(simulation.matchRestart)
        let score = (simulation.northGoals, simulation.southGoals)
        let kicks = simulation.kickCount
        let position = simulation.ball.position
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 1)
        advance(&simulation, frames: 180)
        XCTAssertEqual(simulation.phase, .fullTime)
        XCTAssertEqual(simulation.matchTimeElapsed, 1)
        XCTAssertEqual(simulation.kickCount, kicks)
        XCTAssertEqual(simulation.ball.position, position)
        XCTAssertEqual(simulation.northGoals, score.0)
        XCTAssertEqual(simulation.southGoals, score.1)
    }
}
