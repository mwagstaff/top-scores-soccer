import AVFAudio
import XCTest
@testable import TopScoresSoccer

@MainActor
final class GameSceneFoulTests: XCTestCase {
    func testWhistleWaitsForFallAndPauseDoesNotSkipTheAftermath() {
        let scene = GameScene()
        scene.setMode(.passing)
        scene.simulation.tuning.aiSpeedScale = 0
        scene.simulation.roster[1].state.position = Vector2(x: -25, y: -25)
        scene.simulation.roster[2].state.position = Vector2(x: 25, y: -25)
        scene.simulation.roster[3].state.position = Vector2(x: -7, y: 18)
        scene.simulation.roster[3].state.facing = -.up
        scene.simulation.roster[4].state.position = Vector2(x: 25, y: 35)
        scene.simulation.roster[5].state.position = Vector2(x: -25, y: 35)
        scene.simulation.player.position = Vector2(x: -7, y: 20.6)
        scene.simulation.player.velocity = -.up * 16
        scene.simulation.player.facing = -.up
        scene.simulation.ball.position = Vector2(x: 25, y: 0)
        var whistles = 0
        scene.onWhistle = { whistles += 1 }
        scene.pressAction(startedAt: ProcessInfo.processInfo.systemUptime - 0.3)
        var time = 10.0
        for _ in 0..<15 {
            time += 1.0 / 60
            scene.update(time)
            if case .foulContact = scene.simulation.phase { break }
        }
        XCTAssertEqual(scene.simulation.phase, .foulContact(team: .red))
        XCTAssertEqual(whistles, 0)
        XCTAssertNil(scene.simulation.lastFoul)
        for _ in 0..<10 { time += 1.0 / 60; scene.update(time) }
        let progress = scene.simulation.roster[3].fallProgress
        XCTAssertGreaterThan(progress, 0)
        XCTAssertLessThan(progress, 1)
        scene.setGameplayPaused(true)
        time += 10
        scene.update(time)
        XCTAssertEqual(scene.simulation.roster[3].fallProgress, progress)
        XCTAssertEqual(whistles, 0)
        scene.setGameplayPaused(false)
        for _ in 0..<Int(ceil(scene.simulation.tuning.foulContactDuration * 60)) + 2 {
            time += 1.0 / 60
            scene.update(time)
            if case .freeKick = scene.simulation.phase { break }
        }
        XCTAssertEqual(scene.simulation.phase, .freeKick(team: .red))
        XCTAssertEqual(scene.simulation.roster[3].fallProgress, 1)
        XCTAssertEqual(whistles, 1)
        for _ in 0..<10 { time += 1.0 / 60; scene.update(time) }
        XCTAssertEqual(whistles, 1, "The same stoppage must never replay its whistle each frame.")
        scene.resetSandbox()
        time += 1.0 / 60
        scene.update(time)
        XCTAssertEqual(whistles, 1)
        XCTAssertTrue(scene.simulation.footballers.allSatisfy { $0.fallProgress == 0 })
    }

    func testOriginalWhistleIsBundledAndDecodesAsAShortCue() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "referee-whistle", withExtension: "wav"))
        let sound = try AVAudioPlayer(contentsOf: url)
        XCTAssertEqual(sound.numberOfChannels, 1)
        XCTAssertEqual(sound.duration, 0.32, accuracy: 0.001)
    }
}
