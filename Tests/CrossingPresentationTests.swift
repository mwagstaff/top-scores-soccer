import UIKit
import XCTest
@testable import TopScoresSoccer

@MainActor
final class CrossingPresentationTests: XCTestCase {
    func testWingCrossShowsTimingAndOverhitFeedbackOnPhoneAndPad() throws {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 834, height: 1194)] {
            let scene = crossingScene()
            let input = controls(for: scene, size: size)
            var hud = SandboxHUD()
            scene.onHUDUpdate = { hud = $0 }
            refresh(input, scene: scene)
            XCTAssertTrue(scene.simulation.canCross)
            XCTAssertEqual(input.actionTitle, "CROSS")
            XCTAssertEqual(input.actionIconName, "arrow.up.right")
            XCTAssertEqual(input.passTitle, "SHORT PASS")
            XCTAssertEqual(input.passIconName, "arrow.right")
            XCTAssertEqual(hud.status, "CROSS AVAILABLE")
            let action = try element("sandbox.action", in: input)
            XCTAssertEqual(action.accessibilityLabel, "Cross ball")
            XCTAssertTrue(action.accessibilityHint?.contains("automatically") == true)
            XCTAssertTrue(action.accessibilityHint?.contains("Press PASS") == true)

            scene.pressAction(button: .shoot, startedAt: 100)
            scene.simulation.updateActionHold(heldFor: 0.04)
            refresh(input, scene: scene)
            XCTAssertEqual(scene.powerFeedback?.kind, .cross)
            XCTAssertTrue(try element("sandbox.power", in: input).accessibilityValue?.contains("falls short") == true)

            scene.simulation.updateActionHold(heldFor: 0.49)
            refresh(input, scene: scene)
            let sweet = try XCTUnwrap(scene.powerFeedback)
            XCTAssertTrue(sweet.isSweet)
            XCTAssertEqual(hud.status, "CROSS NOW")
            XCTAssertEqual(input.actionTitle, "CROSS")
            XCTAssertTrue(try element("sandbox.power", in: input).accessibilityValue?.contains("Release in green") == true)
            assertTint(sweet.tint, greenExceedsRed: true)
            XCTAssertTrue(input.bounds.contains(try element("sandbox.power", in: input).accessibilityFrameInContainerSpace))
            attach(input, named: "Cross sweet band — \(Int(size.width))pt")

            scene.simulation.updateActionHold(heldFor: 2)
            refresh(input, scene: scene)
            let overhit = try XCTUnwrap(scene.powerFeedback)
            XCTAssertTrue(overhit.overcharging)
            XCTAssertFalse(overhit.isSweet)
            XCTAssertNotNil(overhit.overhitStart)
            XCTAssertEqual(hud.status, "CROSS OVERHIT")
            XCTAssertTrue(try element("sandbox.power", in: input).accessibilityValue?.contains("sail past") == true)
            assertTint(overhit.tint, greenExceedsRed: false)
            attach(input, named: "Cross overhit warning — \(Int(size.width))pt")

            scene.releaseAction(heldFor: 2)
            refresh(input, scene: scene)
            XCTAssertEqual(scene.simulation.lastKickKind, "cross")
            XCTAssertEqual(hud.crosses, 1)
            XCTAssertNil(scene.powerFeedback)
            XCTAssertFalse(elements(input).contains { $0.accessibilityIdentifier == "sandbox.power" })
        }
    }

    func testIncomingCrossExplainsGoalwardTapAndContactHasOneImpact() throws {
        let scene = crossingScene()
        let input = controls(for: scene, size: CGSize(width: 440, height: 956))
        var hud = SandboxHUD()
        var impacts: [GameplayHaptic] = []
        scene.onHUDUpdate = { hud = $0 }
        scene.pressAction(button: .shoot)
        scene.releaseAction(heldFor: 0.49)
        XCTAssertTrue(scene.simulation.isCrossInFlight)
        XCTAssertNotEqual(scene.simulation.selectedPlayerID, 0)
        refresh(input, scene: scene)
        XCTAssertEqual(hud.status, "MEET THE CROSS")
        XCTAssertTrue(try element("sandbox.action", in: input).accessibilityHint?.contains("Tap as the cross") == true)

        // Keep the real cross's ownership and handover, then place its arrival at
        // reachable heading height to exercise feedback at the contact boundary.
        scene.simulation.player = PlayerState(position: Vector2(x: 0, y: 42))
        scene.simulation.ball = BallState(position: Vector2(x: 0.25, y: 42.1),
            velocity: Vector2(x: -8, y: 0), mode: .pass, height: 1.65, verticalVelocity: -1)
        refresh(input, scene: scene)
        XCTAssertEqual(input.actionTitle, "HEAD")
        XCTAssertEqual(hud.status, "HEAD IT")
        XCTAssertTrue(hud.detail.contains("towards goal"))
        XCTAssertFalse(hud.detail.contains("Aim the stick"))
        scene.onHaptic = { impacts.append($0) }
        scene.pressAction(button: .shoot)
        XCTAssertEqual(scene.simulation.headerCount, 1)
        XCTAssertEqual(impacts, [.pass], "A header connecting on button-down gives immediate feedback.")
        scene.releaseAction(heldFor: 0.08)
        XCTAssertEqual(scene.simulation.headerCount, 1)
        XCTAssertEqual(impacts, [.pass], "Releasing the same jump cannot repeat its impact.")
        XCTAssertNil(scene.powerFeedback)
    }

    func testCrossCueClearsWhenPlayerLeavesWingAndPauseCancelsPower() throws {
        let scene = crossingScene()
        let input = controls(for: scene, size: CGSize(width: 440, height: 956))
        refresh(input, scene: scene)
        XCTAssertEqual(input.actionTitle, "CROSS")
        scene.simulation.player.position = Vector2(x: 0, y: 32)
        scene.simulation.ball.position = scene.simulation.player.position + .up * 1.25
        refresh(input, scene: scene)
        XCTAssertFalse(scene.simulation.canCross)
        XCTAssertEqual(try element("sandbox.action", in: input).accessibilityLabel, "Shoot")
        XCTAssertNotEqual(input.actionTitle, "CROSS")

        scene.simulation.player.position = Vector2(x: 26, y: 24)
        scene.simulation.ball.position = scene.simulation.player.position + .up * 1.25
        scene.pressAction(button: .shoot)
        scene.simulation.updateActionHold(heldFor: 0.49)
        XCTAssertEqual(scene.powerFeedback?.kind, .cross)
        scene.setGameplayPaused(true)
        refresh(input, scene: scene)
        XCTAssertNil(scene.powerFeedback)
        scene.setGameplayPaused(false)
        scene.releaseAction(heldFor: 0.49)
        XCTAssertEqual(scene.simulation.crossCount, 0)
    }

    private func crossingScene() -> GameScene {
        let scene = GameScene(mode: .passing)
        scene.simulation.tuning.aiSpeedScale = 0
        scene.simulation.player = PlayerState(position: Vector2(x: 26, y: 24), velocity: .up * 4, facing: .up)
        scene.simulation.ball.position = scene.simulation.player.position + .up * 1.25
        scene.simulation.roster[1].state = PlayerState(position: Vector2(x: 0, y: 42))
        scene.simulation.roster[2].state = PlayerState(position: Vector2(x: -10, y: 40))
        for id in scene.simulation.roster.indices where scene.simulation.roster[id].team == .red {
            scene.simulation.roster[id].state = PlayerState(position: Vector2(x: Double(id) * 3, y: -25))
        }
        scene.setMovement(.up, timestamp: 99)
        return scene
    }

    private func controls(for scene: GameScene, size: CGSize) -> InputController {
        let input = InputController(frame: CGRect(origin: .zero, size: size))
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

    private func element(_ identifier: String, in input: InputController) throws -> UIAccessibilityElement {
        try XCTUnwrap(elements(input).first { $0.accessibilityIdentifier == identifier })
    }

    private func assertTint(_ color: UIColor, greenExceedsRed: Bool,
                            file: StaticString = #filePath, line: UInt = #line) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        XCTAssertEqual(alpha, 1, file: file, line: line)
        if greenExceedsRed { XCTAssertGreaterThan(green, red, file: file, line: line) }
        else { XCTAssertGreaterThan(red, green, file: file, line: line) }
    }

    private func attach(_ input: InputController, named name: String) {
        let size = CGSize(width: input.bounds.width, height: 306)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.08, green: 0.29, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: 306 - input.bounds.height)
            input.draw(input.bounds)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
