import Foundation
import XCTest
@testable import TopScoresSoccer

@MainActor
final class GameSceneInputTests: XCTestCase {
    private let tick = 1.0 / 60.0

    func testUptimeHoldCommitsOneSlideBeforeRenderFramesAccumulateAndReleaseDoesNotRepeatIt() {
        let scene = soloScene(ballDistance: 12)
        var frameTime = 100.0
        scene.update(frameTime)
        let heldDuration = scene.simulation.tuning.slideHoldThreshold + 0.1
        scene.pressAction(startedAt: ProcessInfo.processInfo.systemUptime - heldDuration)
        XCTAssertEqual(scene.simulation.slideCount, 0)

        advance(scene, frames: 1, time: &frameTime)

        XCTAssertEqual(scene.simulation.slideCount, 1,
                       "Touch uptime must commit the hold after one frame, without waiting for simulated hold time.")
        XCTAssertTrue(scene.simulation.isSliding)
        scene.releaseAction(heldFor: heldDuration)
        scene.releaseAction(heldFor: heldDuration + 1)
        advance(scene, frames: 120, time: &frameTime)
        XCTAssertEqual(scene.simulation.slideCount, 1)
        XCTAssertEqual(scene.simulation.tackleCount, 1)
        XCTAssertEqual(scene.simulation.standingTackleCount, 0)
        XCTAssertEqual(scene.simulation.kickCount, 0)
        XCTAssertNil(scene.simulation.queuedActionKind)
    }

    func testPauseAndCancellationClearPendingHoldWithoutDelayedSlide() {
        for pause in [false, true] {
            let scene = soloScene(ballDistance: 12)
            var touchResets = 0
            scene.onResetInput = { touchResets += 1 }
            let heldDuration = scene.simulation.tuning.slideHoldThreshold + 0.1
            scene.setMovement(.up)
            scene.pressAction(startedAt: ProcessInfo.processInfo.systemUptime - heldDuration)

            // Interrupt before the next frame can consume the already-expired hold.
            if pause { scene.setGameplayPaused(true) }
            else { scene.cancelTouches() }
            XCTAssertGreaterThan(touchResets, 0)
            XCTAssertEqual(scene.simulation.movement, .zero)
            if pause { scene.setGameplayPaused(false) }
            var frameTime = 200.0
            advance(scene, frames: 120, time: &frameTime)
            scene.releaseAction(heldFor: heldDuration + 10)

            XCTAssertEqual(scene.simulation.slideCount, 0)
            XCTAssertEqual(scene.simulation.tackleCount, 0)
            XCTAssertEqual(scene.simulation.kickCount, 0)
            XCTAssertEqual(scene.simulation.actionStatus, .idle)
        }
    }

    func testPauseAndCancellationRemoveQueuedPassBeforeBallArrives() {
        for pause in [false, true] {
            let scene = soloScene(ballDistance: 4)
            scene.setMovement(.up)
            scene.pressAction()
            scene.releaseAction(heldFor: 0.05)
            XCTAssertEqual(scene.simulation.queuedActionKind, "pass")
            XCTAssertEqual(scene.simulation.queuedPassPlayerID, scene.simulation.selectedPlayerID)

            if pause { scene.setGameplayPaused(true) }
            else { scene.cancelTouches() }
            XCTAssertNil(scene.simulation.queuedActionKind)
            // Put the incoming ball inside contact range. A stale queue would fire
            // on the first resumed frame rather than simply establish control.
            scene.simulation.ball.position = scene.simulation.player.position + .up * 0.9
            scene.simulation.ball.velocity = .zero
            if pause { scene.setGameplayPaused(false) }
            var frameTime = 300.0
            advance(scene, frames: 45, time: &frameTime)

            XCTAssertTrue(scene.simulation.hasControl)
            XCTAssertNil(scene.simulation.queuedActionKind)
            XCTAssertEqual(scene.simulation.kickCount, 0)
            XCTAssertEqual(scene.simulation.slideCount, 0)
        }
    }

    func testAutomaticRestartClearsTouchesAndOldReleaseRequiresFreshPress() {
        let scene = soloScene(ballDistance: 12)
        // A generous threshold isolates restart cancellation from wall-clock test
        // execution speed; no sleeping or timing-sensitive assertion is needed.
        scene.simulation.tuning.slideHoldThreshold = 100
        scene.simulation.tuning.restartDelay = 0.12
        var frameTime = 400.0
        scene.update(frameTime)
        var touchResets = 0
        scene.onResetInput = { touchResets += 1 }
        let generation = scene.simulation.resetGeneration
        scene.pressAction()
        scene.simulation.ball.position = Vector2(x: Pitch.width / 2 + Pitch.ballRadius + 1, y: 0)
        scene.simulation.ball.velocity = .zero
        frameTime += 0.02
        scene.update(frameTime)

        XCTAssertEqual(scene.simulation.phase, .outOfPlay)
        XCTAssertGreaterThan(touchResets, 0, "Entering restart feedback must release captured touches immediately.")
        let resetsAtBoundary = touchResets
        advance(scene, frames: 30, time: &frameTime)
        XCTAssertEqual(scene.simulation.phase, .playing)
        XCTAssertGreaterThan(scene.simulation.resetGeneration, generation)
        XCTAssertGreaterThan(touchResets, resetsAtBoundary,
                             "The automatic restart must invalidate touch ownership again at the new state.")
        scene.releaseAction(heldFor: 101)
        advance(scene, frames: 5, time: &frameTime)
        XCTAssertEqual(scene.simulation.slideCount, 0)
        XCTAssertEqual(scene.simulation.kickCount, 0)
        XCTAssertNil(scene.simulation.queuedActionKind)
        XCTAssertTrue(scene.simulation.canKick)

        scene.pressAction()
        scene.releaseAction(heldFor: 0.05)
        XCTAssertEqual(scene.simulation.kickCount, 1, "A fresh press must remain usable after cancellation.")
        XCTAssertEqual(scene.simulation.lastKick, .pass)
    }

    func testTimestampedReceivingHoldQueuesPowerWithoutCommittingASlide() {
        let scene = incomingScene()
        scene.setMovement(.up)
        let heldDuration = 0.36
        scene.pressAction(startedAt: ProcessInfo.processInfo.systemUptime - heldDuration)
        var frameTime = 500.0
        scene.update(frameTime)
        XCTAssertTrue(scene.simulation.isPreparingReceivingKick)
        XCTAssertEqual(scene.simulation.actionStatus, .charging)
        XCTAssertEqual(scene.simulation.slideCount, 0)
        scene.releaseAction(heldFor: heldDuration)
        XCTAssertEqual(scene.simulation.queuedActionKind, "shot")
        XCTAssertEqual(scene.simulation.kickCount, 0)
        // Returning the stick to neutral must not erase the prepared direction.
        scene.setMovement(.zero)
        for _ in 0..<90 where scene.simulation.kickCount == 0 {
            advance(scene, frames: 1, time: &frameTime)
        }
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertEqual(scene.simulation.slideCount, 0)
        XCTAssertEqual(scene.simulation.lastKick, .shot)
        XCTAssertGreaterThan(scene.simulation.ball.velocity.y, 25)
        XCTAssertNil(scene.simulation.queuedActionKind)
        scene.releaseAction(heldFor: 2)
        XCTAssertEqual(scene.simulation.kickCount, 1)
    }

    func testPausingCancelsPreparedPowerBeforeIncomingBallArrives() {
        let scene = incomingScene()
        scene.setMovement(.up)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.36)
        XCTAssertEqual(scene.simulation.queuedActionKind, "shot")
        scene.setGameplayPaused(true)
        XCTAssertNil(scene.simulation.queuedActionKind)
        scene.setGameplayPaused(false)
        scene.simulation.ball.position = scene.simulation.player.position + .up
        scene.simulation.ball.velocity = .zero
        var frameTime = 600.0
        advance(scene, frames: 15, time: &frameTime)
        XCTAssertTrue(scene.simulation.hasControl)
        XCTAssertEqual(scene.simulation.kickCount, 0)
        XCTAssertEqual(scene.simulation.slideCount, 0)
    }

    func testJoystickMovesPassReceiverBeforeArrivalThroughSceneInput() {
        let scene = GameScene()
        scene.setMode(.passing)
        scene.simulation.tuning.aiSpeedScale = 0
        let positions = [Vector2.zero, Vector2(x: 0, y: 24), Vector2(x: -25, y: -25),
                         Vector2(x: 25, y: 35), Vector2(x: -25, y: 35), Vector2(x: 25, y: -25)]
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state.position = positions[id]
            scene.simulation.roster[id].state.velocity = .zero
        }
        scene.simulation.ball.position = .up * 1.25
        scene.setMovement(.up)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.05)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 1)
        XCTAssertTrue(scene.simulation.isControllingPassReceiver)
        XCTAssertFalse(scene.simulation.hasControl)

        scene.setMovement(Vector2(x: 1, y: 0))
        var frameTime = 700.0
        advance(scene, frames: 12, time: &frameTime)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 1)
        XCTAssertGreaterThan(scene.simulation.player.position.x, 0.5)
        XCTAssertEqual(scene.simulation.roster[0].state.position.x, 0, accuracy: 0.000001)
        XCTAssertGreaterThan((scene.simulation.ball.position - scene.simulation.player.position).length, 10)
        XCTAssertFalse(scene.simulation.hasControl, "Receiver movement must work well before the first touch.")
        XCTAssertEqual(scene.simulation.chipCount, 0)
    }

    func testJoystickWinsBallFromFrontWithoutActionButton() {
        let scene = defendingScene()
        scene.simulation.player.position = Vector2(x: 0, y: -3.6)
        scene.setMovement(.up)
        var frameTime = 800.0
        for _ in 0..<40 where !scene.simulation.hasControl {
            advance(scene, frames: 1, time: &frameTime)
        }
        XCTAssertTrue(scene.simulation.hasControl)
        XCTAssertEqual(scene.simulation.possessionTeam, .blue)
        XCTAssertEqual(scene.simulation.phase, .playing)
        XCTAssertEqual(scene.simulation.standingTackleCount, 0)
        XCTAssertEqual(scene.simulation.slideCount, 0)
        XCTAssertEqual(scene.simulation.kickCount, 0)
    }

    func testShortActionTapWhileAlreadyNearestDoesNotLaunchStandingTackle() {
        let scene = defendingScene()
        scene.simulation.player.position = Vector2(x: 0, y: -2.2)
        scene.simulation.player.facing = .up
        scene.setMovement(.zero)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.05)
        XCTAssertFalse(scene.simulation.hasControl)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 0)
        XCTAssertEqual(scene.simulation.standingTackleCount, 0)
        XCTAssertEqual(scene.simulation.slideCount, 0)
        XCTAssertFalse(scene.simulation.isTackling)
        XCTAssertNil(scene.simulation.queuedActionKind)
        XCTAssertEqual(scene.simulation.phase, .playing)
    }

    func testJoystickSelectsMatchingRunnerImmediatelyAndCanReverseTheChoice() {
        let scene = looseSelectionScene()
        scene.update(900)
        scene.setMovement(Vector2(x: -1, y: 0))
        scene.update(900.02)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 1,
                       "Left means the nearby player to the right of the ball, even though player 0 is closer.")
        XCTAssertLessThan(scene.simulation.roster[1].state.position.x, 8)
        XCTAssertEqual(scene.simulation.roster[0].state.position.x, -4, accuracy: 0.000001)
        XCTAssertEqual(scene.simulation.kickCount, 0)

        scene.setMovement(Vector2(x: 1, y: 0))
        scene.update(900.04)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 0,
                       "A clear reverse direction must not wait for the old switch cooldown.")
        XCTAssertGreaterThan(scene.simulation.roster[0].state.position.x, -4)
    }

    func testActionBeforeNextFrameUsesTheRunnerIndicatedByTheJoystick() {
        for duration in [0.05, 0.3] {
            let scene = looseSelectionScene()
            scene.setMovement(Vector2(x: -1, y: 0))
            scene.pressAction()
            XCTAssertEqual(scene.simulation.selectedPlayerID, 1,
                           "The current directional choice must be applied before capturing the action's player.")
            scene.releaseAction(heldFor: duration)
            XCTAssertEqual(scene.simulation.selectedPlayerID, 1)
            XCTAssertEqual(scene.simulation.kickCount, 0)
            if duration < scene.simulation.tuning.slideHoldThreshold {
                XCTAssertEqual(scene.simulation.queuedPassPlayerID, 1)
                XCTAssertFalse(scene.simulation.isSliding)
            } else {
                XCTAssertTrue(scene.simulation.roster[1].isSliding)
                XCTAssertFalse(scene.simulation.roster[0].isSliding)
            }
        }
    }

    private func looseSelectionScene() -> GameScene {
        let scene = GameScene()
        scene.setMode(.passing)
        scene.simulation.tuning.aiSpeedScale = 0
        let positions = [Vector2(x: -4, y: 0), Vector2(x: 8, y: 0), Vector2(x: 0, y: 20),
                         Vector2(x: -25, y: 35), Vector2(x: 25, y: 35), Vector2(x: 25, y: -35)]
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state.position = positions[id]
            scene.simulation.roster[id].state.velocity = .zero
        }
        scene.simulation.ball.position = .zero
        scene.simulation.ball.velocity = .zero
        scene.simulation.step(dt: tick)
        XCTAssertNil(scene.simulation.possessionTeam)
        XCTAssertEqual(scene.simulation.selectedPlayerID, 0)
        return scene
    }

    private func defendingScene() -> GameScene {
        let scene = GameScene()
        scene.setMode(.passing)
        scene.simulation.tuning.aiSpeedScale = 0
        let positions = [Vector2(x: 0, y: -20), Vector2(x: -25, y: -25), Vector2(x: 25, y: -25),
                         Vector2.zero, Vector2(x: -25, y: 35), Vector2(x: 25, y: 35)]
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state.position = positions[id]
            scene.simulation.roster[id].state.velocity = .zero
        }
        scene.simulation.ball.position = -.up * 1.15
        scene.simulation.ball.velocity = .zero
        scene.simulation.step(dt: tick)
        XCTAssertEqual(scene.simulation.possessionTeam, .red)
        return scene
    }

    private func incomingScene() -> GameScene {
        let scene = soloScene(ballDistance: 12)
        scene.simulation.player.position = .zero
        scene.simulation.player.velocity = .zero
        scene.simulation.ball.position = Vector2(x: 8, y: 0)
        scene.simulation.ball.velocity = Vector2(x: -12, y: 0)
        scene.simulation.ball.mode = .pass
        return scene
    }

    private func soloScene(ballDistance: Double) -> GameScene {
        let scene = GameScene()
        scene.setMode(.solo)
        scene.resetSandbox(clearScore: true)
        scene.simulation.ball.position = scene.simulation.player.position + .up * ballDistance
        scene.simulation.ball.velocity = .zero
        scene.simulation.step(dt: tick)
        XCTAssertFalse(scene.simulation.hasControl)
        XCTAssertFalse(scene.simulation.canKick)
        return scene
    }

    private func advance(_ scene: GameScene, frames: Int, time: inout TimeInterval) {
        for _ in 0..<frames {
            time += tick
            scene.update(time)
        }
    }
}
