import XCTest
@testable import TopScoresSoccer

@MainActor
final class GameHapticsTests: XCTestCase {
    private let tick = 1.0 / 60.0

    func testKicksProduceOneDistinctImpactAndCancelledPressIsSilent() {
        let scene = soloScene()
        var events: [GameplayHaptic] = []
        scene.onHaptic = { events.append($0) }
        scene.pressAction()
        XCTAssertTrue(events.isEmpty)
        scene.releaseAction(heldFor: 0.05)
        XCTAssertEqual(events, [.pass])
        var time = 10.0
        advance(scene, frames: 10, time: &time)
        XCTAssertEqual(events, [.pass], "Render updates must not repeat a release-time impact.")

        scene.resetSandbox()
        scene.pressAction()
        scene.releaseAction(heldFor: 0.9)
        XCTAssertEqual(events, [.pass, .shot])
        scene.resetSandbox()
        scene.pressAction()
        scene.cancelTouches()
        scene.releaseAction(heldFor: 0.9)
        scene.resetSandbox(clearScore: true)
        advance(scene, frames: 5, time: &time)
        XCTAssertEqual(events, [.pass, .shot])
    }

    func testPreparedKickWaitsForBallContactBeforeItsHaptic() {
        let scene = looseSolo(ballDistance: 12)
        scene.simulation.player.position = .zero
        scene.simulation.ball.position = Vector2(x: 8, y: 0)
        scene.simulation.ball.velocity = Vector2(x: -12, y: 0)
        scene.simulation.ball.mode = .pass
        var events: [GameplayHaptic] = []
        scene.onHaptic = { events.append($0) }
        scene.setMovement(.up)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.05)
        XCTAssertEqual(scene.simulation.queuedActionKind, "pass")
        XCTAssertTrue(events.isEmpty, "Preparing the kick is not ball contact.")
        scene.setMovement(.zero)
        var time = 20.0
        for _ in 0..<90 where scene.simulation.kickCount == 0 {
            advance(scene, frames: 1, time: &time)
        }
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertEqual(events, [.pass])
        advance(scene, frames: 10, time: &time)
        XCTAssertEqual(events, [.pass])
    }

    func testSlideImpactRequiresContactAndAMissStaysSilent() {
        for distance in [4.0, 12.0] {
            let scene = looseSolo(ballDistance: distance)
            var events: [GameplayHaptic] = []
            scene.onHaptic = { events.append($0) }
            scene.setMovement(.up)
            scene.pressAction(startedAt: ProcessInfo.processInfo.systemUptime - 0.3)
            var time = 30.0
            advance(scene, frames: 1, time: &time)
            XCTAssertEqual(scene.simulation.slideCount, 1)
            XCTAssertTrue(events.isEmpty, "Starting a slide is not an impact.")
            advance(scene, frames: 35, time: &time)
            scene.releaseAction(heldFor: 0.6)
            XCTAssertEqual(events, distance == 4 ? [.slideContact] : [])
        }
    }

    func testRunningChallengeProducesOneContactImpactWithoutAction() {
        let scene = GameScene()
        scene.simulation.tuning.aiSpeedScale = 0
        let positions = [Vector2(x: 0, y: -20), Vector2(x: -25, y: -25), Vector2(x: 25, y: -25),
                         Vector2.zero, Vector2(x: -25, y: 35), Vector2(x: 25, y: 35)]
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state.position = positions[id]
            scene.simulation.roster[id].state.velocity = .zero
            scene.simulation.roster[id].state.facing = .up
        }
        scene.simulation.ball.position = .up * 0.9
        scene.simulation.ball.velocity = .zero
        scene.simulation.step(dt: tick)
        XCTAssertEqual(scene.simulation.possessionTeam, .red)
        scene.simulation.player.position = .up * 2.8
        scene.simulation.player.velocity = -.up * 8
        scene.setMovement(-.up)
        var events: [GameplayHaptic] = []
        scene.onHaptic = { events.append($0) }
        var time = 40.0
        for _ in 0..<12 where !scene.simulation.hasControl {
            advance(scene, frames: 1, time: &time)
        }
        XCTAssertTrue(scene.simulation.hasControl)
        XCTAssertEqual(scene.simulation.runningChallengeCount, 1)
        XCTAssertEqual(events, [.challenge])
    }

    func testFoulImpactPrecedesWhistleAndDoesNotRepeatDuringFall() {
        let scene = GameScene()
        scene.simulation.tuning.aiSpeedScale = 0
        let positions = [Vector2(x: -7, y: 20.6), Vector2(x: -25, y: -25), Vector2(x: 25, y: -25),
                         Vector2(x: -7, y: 18), Vector2(x: 25, y: 35), Vector2(x: -25, y: 35)]
        for id in scene.simulation.roster.indices {
            scene.simulation.roster[id].state.position = positions[id]
            scene.simulation.roster[id].state.velocity = .zero
        }
        scene.simulation.player.velocity = -.up * 16
        scene.simulation.player.facing = -.up
        scene.simulation.roster[3].state.facing = -.up
        scene.simulation.ball.position = Vector2(x: 25, y: 0)
        var events: [GameplayHaptic] = []
        var whistles = 0
        scene.onHaptic = { events.append($0) }
        scene.onWhistle = { whistles += 1 }
        scene.pressAction(startedAt: ProcessInfo.processInfo.systemUptime - 0.3)
        var time = 50.0
        for _ in 0..<15 where scene.simulation.phase == .playing {
            advance(scene, frames: 1, time: &time)
        }
        XCTAssertEqual(scene.simulation.phase, .foulContact(team: .red))
        XCTAssertEqual(events, [.foul])
        XCTAssertEqual(whistles, 0)
        advance(scene, frames: 90, time: &time)
        XCTAssertEqual(events, [.foul])
        XCTAssertEqual(whistles, 1)
    }

    func testHapticsSettingAndPauseSuppressFeedbackWithoutReplayingIt() {
        let session = GameSession()
        session.mode = .solo
        let scene = session.scene
        var events: [GameplayHaptic] = []
        scene.onHaptic = { events.append($0) }
        session.hapticsEnabled = false
        scene.pressAction()
        scene.releaseAction(heldFor: 0.05)
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertTrue(events.isEmpty)
        session.hapticsEnabled = true
        var time = 60.0
        advance(scene, frames: 5, time: &time)
        XCTAssertTrue(events.isEmpty, "Enabling feedback must not replay contacts that happened while muted.")
        scene.resetSandbox()
        scene.setGameplayPaused(true)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.05)
        advance(scene, frames: 5, time: &time)
        XCTAssertTrue(events.isEmpty)
        scene.setGameplayPaused(false)
        scene.pressAction()
        scene.releaseAction(heldFor: 0.05)
        XCTAssertEqual(events, [.pass])
    }

    private func soloScene() -> GameScene {
        let scene = GameScene()
        scene.setMode(.solo)
        scene.resetSandbox(clearScore: true)
        return scene
    }

    private func looseSolo(ballDistance: Double) -> GameScene {
        let scene = soloScene()
        scene.simulation.ball.position = scene.simulation.player.position + .up * ballDistance
        scene.simulation.ball.velocity = .zero
        scene.simulation.step(dt: tick)
        XCTAssertFalse(scene.simulation.hasControl)
        return scene
    }

    private func advance(_ scene: GameScene, frames: Int, time: inout Double) {
        for _ in 0..<frames { time += tick; scene.update(time) }
    }
}
