import XCTest
import UIKit
@testable import TopScoresSoccer

@MainActor
final class KickPresentationTests: XCTestCase {
    func testShotMeterShowsSweetBandThenOverhitAndClearsOnRelease() throws {
        let scene = GameScene(mode: .solo)
        scene.simulation.player.position = Vector2(x: 0, y: 32)
        scene.simulation.ball.position = Vector2(x: 0, y: 33.25)
        let input = controls(for: scene)
        var hud = SandboxHUD()
        scene.onHUDUpdate = { hud = $0 }
        scene.setMovement(.up, timestamp: 100)
        scene.pressAction(startedAt: 100.01)
        let sweet = KickMechanics.shotSweetSpotDurations(tuning: scene.simulation.tuning)
        scene.simulation.updateActionHold(heldFor: (sweet.lowerBound + sweet.upperBound) / 2)
        refresh(input, scene: scene)
        XCTAssertEqual(hud.power?.kind, .shot)
        XCTAssertEqual(hud.status, "RELEASE NOW")
        XCTAssertTrue(try XCTUnwrap(scene.powerFeedback).isSweet)
        XCTAssertFalse(try XCTUnwrap(scene.powerFeedback).overcharging)
        XCTAssertEqual(try powerElement(in: input).accessibilityLabel, "RELEASE NOW")
        attach(input, named: "Shot meter — green release band")

        scene.simulation.updateActionHold(heldFor: 2)
        refresh(input, scene: scene)
        XCTAssertEqual(hud.status, "OVERHIT")
        XCTAssertTrue(try XCTUnwrap(scene.powerFeedback).overcharging)
        XCTAssertTrue(try powerElement(in: input).accessibilityValue?.contains("sail over") == true)
        attach(input, named: "Shot meter — overhit warning")
        scene.releaseAction(heldFor: 2)
        refresh(input, scene: scene)
        XCTAssertNil(scene.powerFeedback)
        XCTAssertNil(hud.power)
        XCTAssertFalse(elements(input).contains { $0.accessibilityIdentifier == "sandbox.power" })
    }

    func testThrowDistanceHasNoShotBandAndPauseClearsHeldMeter() throws {
        let scene = matchFixture(throwIn: true)
        XCTAssertEqual(scene.simulation.matchRestart?.kind, .throwIn)
        XCTAssertEqual(scene.simulation.matchRestart?.team, .blue)
        let input = controls(for: scene)
        scene.setMovement(Vector2(x: -1, y: 0), timestamp: 200)
        scene.pressAction(startedAt: 200.01)
        scene.simulation.updateActionHold(heldFor: 0.8)
        refresh(input, scene: scene)
        let power = try XCTUnwrap(scene.powerFeedback)
        XCTAssertEqual(power.kind, .throwIn)
        XCTAssertNil(power.sweetSpot)
        XCTAssertFalse(power.overcharging)
        XCTAssertGreaterThan(power.fraction, 0.5)
        XCTAssertEqual(try powerElement(in: input).accessibilityLabel, "THROW DISTANCE")
        attach(input, named: "Throw-in meter — distance without shot bands")
        let kicks = scene.simulation.kickCount
        scene.setGameplayPaused(true)
        refresh(input, scene: scene)
        XCTAssertNil(scene.powerFeedback)
        XCTAssertFalse(elements(input).contains { $0.accessibilityIdentifier == "sandbox.power" })
        scene.setGameplayPaused(false)
        scene.releaseAction(heldFor: 1)
        XCTAssertEqual(scene.simulation.kickCount, kicks)
    }

    func testBlueKeeperHandsRemainEnabledAndOfferLongThrowDistance() throws {
        let scene = matchFixture(throwIn: false)
        XCTAssertTrue(scene.simulation.isHoldingGoalkeeper)
        XCTAssertTrue(scene.simulation.isControllingGoalkeeper)
        let input = controls(for: scene)
        refresh(input, scene: scene)
        let action = try XCTUnwrap(elements(input).first { $0.accessibilityIdentifier == "sandbox.action" })
        XCTAssertFalse(action.accessibilityTraits.contains(.notEnabled))
        scene.pressAction(startedAt: 300)
        scene.simulation.updateActionHold(heldFor: 0.8)
        refresh(input, scene: scene)
        XCTAssertEqual(scene.powerFeedback?.kind, .keeperDistribution)
        XCTAssertEqual(scene.powerFeedback?.title, "LONG THROW")
        XCTAssertEqual(input.actionTitle, "THROW")
        XCTAssertTrue(scene.powerFeedback?.guidance.contains("Release to throw") == true)
        XCTAssertNil(scene.powerFeedback?.sweetSpot)
        XCTAssertFalse(action.accessibilityTraits.contains(.notEnabled))
        XCTAssertFalse(action.accessibilityHint?.localizedCaseInsensitiveContains("punt") == true)
        attach(input, named: "Keeper meter — high long throw")
        scene.cancelTouches()
        refresh(input, scene: scene)
        XCTAssertTrue(scene.simulation.isHoldingGoalkeeper)
        XCTAssertNil(scene.powerFeedback)
    }

    func testGoalKickUsesKickGuidanceAndHeightMeterWithoutShotBand() throws {
        let scene = matchFixture(throwIn: false, goalKick: true)
        XCTAssertEqual(scene.simulation.matchRestart?.kind, .goalKick)
        XCTAssertTrue(scene.simulation.isTakingRestart)
        let input = controls(for: scene)
        var hud = SandboxHUD()
        scene.onHUDUpdate = { hud = $0 }
        scene.setMovement(.up, timestamp: 350)
        refresh(input, scene: scene)
        XCTAssertEqual(input.actionTitle, "KICK")
        XCTAssertTrue(hud.detail.contains("Tap to pass"))
        let action = try XCTUnwrap(elements(input).first { $0.accessibilityIdentifier == "sandbox.action" })
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            XCTAssertTrue(action.accessibilityValue?.contains("goal kick") == true)
        }
        scene.pressAction(startedAt: 350.01)
        scene.simulation.updateActionHold(heldFor: 0.85)
        refresh(input, scene: scene)
        XCTAssertEqual(scene.powerFeedback?.kind, .longKick)
        XCTAssertNil(scene.powerFeedback?.sweetSpot)
        XCTAssertEqual(hud.status, "HOLD FOR HEIGHT")
        XCTAssertEqual(input.actionTitle, "KICK")
        attach(input, named: "Goal-kick meter — hold high and long")
        scene.releaseAction(heldFor: 0.85)
        XCTAssertEqual(scene.simulation.lastKickKind, "long goal kick")
        XCTAssertNil(scene.powerFeedback)
    }

    func testKeeperOutletsStayVisibleBeforeReleaseAndHandoverOnPhoneAndPad() throws {
        for viewport in [CGSize(width: 393, height: 852), CGSize(width: 440, height: 956),
                         CGSize(width: 834, height: 1194)] {
            for goalKick in [false, true] {
                let scene = matchFixture(throwIn: false, goalKick: goalKick)
                scene.size = viewport
                scene.simulation.roster[0].state = PlayerState(position: Vector2(x: -24, y: -20))
                scene.simulation.roster[1].state = PlayerState(position: Vector2(x: 30, y: -20))
                scene.simulation.roster[2].state = PlayerState(position: Vector2(x: -26, y: 39))
                scene.simulation.roster[3].state = PlayerState(position: Vector2(x: 26, y: 39))
                let keeperID = scene.simulation.selectedPlayerID
                var time = 500.0
                for targetID in [0, 1] {
                    let offset = scene.simulation.roster[targetID].state.position - scene.simulation.ball.position
                    scene.setMovement(Vector2(x: offset.x, y: offset.y * 0.86).normalized)
                    XCTAssertEqual(scene.simulation.passTargetID, targetID)
                    scene.update(time)
                    time += 1 / 60
                    XCTAssertEqual(scene.simulation.selectedPlayerID, keeperID,
                                   "Preview framing must leave the goalkeeper under manual control.")
                    try assertVisible(scene.simulation.ball.position, in: scene)
                    try assertVisible(scene.simulation.roster[targetID].state.position, in: scene)
                    XCTAssertTrue(try XCTUnwrap(scene.camera?.childNode(withName: "controlled-receiver-edge")).isHidden)
                }
                scene.pressAction()
                scene.releaseAction(heldFor: 0.10)
                XCTAssertEqual(scene.simulation.selectedPlayerID, 1)
                XCTAssertTrue(scene.simulation.isControllingPassReceiver)
                scene.update(time)
                try assertVisible(scene.simulation.ball.position, in: scene)
                try assertVisible(scene.simulation.player.position, in: scene)
            }
        }
    }

    private func assertVisible(_ position: Vector2, in scene: GameScene,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let camera = try XCTUnwrap(scene.camera, file: file, line: line)
        let x = (position.x - camera.position.x) / camera.xScale + scene.size.width / 2
        let y = (position.y * 0.86 - camera.position.y) / camera.yScale + scene.size.height / 2
        let clearance = 1.8 / camera.xScale
        XCTAssertGreaterThanOrEqual(x - clearance, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(x + clearance, scene.size.width, file: file, line: line)
        XCTAssertGreaterThanOrEqual(y - clearance, 300, file: file, line: line)
        XCTAssertLessThanOrEqual(y + clearance, scene.size.height - 170, file: file, line: line)
    }

    func testSceneForwardsFreshMovementTimestampsForBackheel() {
        let scene = GameScene(mode: .solo)
        scene.setMovement(.up, timestamp: 400)
        scene.pressAction(startedAt: 400.01)
        scene.setMovement(-.up, timestamp: 400.10)
        scene.releaseAction(heldFor: 0.16)
        XCTAssertEqual(scene.simulation.kickCount, 1)
        XCTAssertEqual(scene.simulation.lastKickKind, "backheel")
        XCTAssertLessThan(scene.simulation.ball.velocity.y, 0)
    }

    private func controls(for scene: GameScene) -> InputController {
        let input = InputController(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        input.scene = scene
        scene.onControlFeedback = { [weak input] status, hasBall, curving in
            input?.feedback(status: status, hasBall: hasBall, curving: curving)
        }
        scene.onResetInput = { [weak input] in input?.clearTouches() }
        input.layoutIfNeeded()
        return input
    }

    private func refresh(_ input: InputController, scene: GameScene) {
        scene.refreshHUD()
        input.feedback(status: scene.simulation.actionStatus, hasBall: scene.simulation.hasControl,
                       curving: scene.simulation.aftertouchRemaining > 0)
    }

    private func elements(_ input: InputController) -> [UIAccessibilityElement] {
        input.accessibilityElements as? [UIAccessibilityElement] ?? []
    }

    private func powerElement(in input: InputController) throws -> UIAccessibilityElement {
        try XCTUnwrap(elements(input).first { $0.accessibilityIdentifier == "sandbox.power" })
    }

    private func attach(_ input: InputController, named name: String) {
        let size = CGSize(width: input.bounds.width, height: 306)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.08, green: 0.29, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: -650)
            input.draw(input.bounds)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Reach real simulation contexts through opponent possession and a boundary
    /// crossing/save; no private ownership fields or synthetic UIKit touches.
    private func matchFixture(throwIn: Bool, goalKick: Bool = false) -> GameScene {
        let scene = GameScene(mode: .match)
        scene.simulation.tuning.aiSpeedScale = 0
        scene.simulation.pressAction()
        scene.simulation.releaseAction(heldFor: 0.12)
        for id in scene.simulation.roster.indices where !scene.simulation.roster[id].isGoalkeeper {
            scene.simulation.roster[id].state.position = Vector2(x: id.isMultiple(of: 2) ? -22 : 22,
                                                                 y: id < 5 ? -20 : 20)
            scene.simulation.roster[id].state.velocity = .zero
        }
        scene.simulation.ball = BallState(position: scene.simulation.roster[5].state.position + .up,
                                          velocity: .zero, mode: .free)
        scene.simulation.step(dt: 1.0 / 60)
        if throwIn || goalKick {
            scene.simulation.ball = BallState(position: goalKick ? Vector2(x: 20, y: -52.4) : Vector2(x: 34.2, y: 0),
                                              velocity: goalKick ? -.up * 35 : Vector2(x: 35, y: 0), mode: .free)
            scene.simulation.step(dt: 1.0 / 60)
            for _ in 0..<90 where scene.simulation.phase != .playing { scene.simulation.step(dt: 1.0 / 60) }
        } else {
            scene.simulation.roster[4].state.position = Vector2(x: 0, y: -47)
            scene.simulation.roster[4].state.velocity = .zero
            scene.simulation.ball = BallState(position: Vector2(x: 0, y: -45.9), velocity: -.up * 4, mode: .pass)
            for _ in 0..<8 { scene.simulation.step(dt: 1.0 / 60) }
        }
        scene.simulation.cancelInput()
        return scene
    }
}
