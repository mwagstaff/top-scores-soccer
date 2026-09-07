import SpriteKit
import UIKit
import XCTest
@testable import TopScoresSoccer

@MainActor
final class HeaderPresentationTests: XCTestCase {
    func testHeaderAvailabilityAndQueueStayDistinctFromSlideAndPower() throws {
        let scene = headerScene(distance: 3, height: 2.5, speed: -8)
        let input = controls(for: scene)
        var hud = SandboxHUD()
        var impacts: [GameplayHaptic] = []
        scene.onHUDUpdate = { hud = $0 }
        scene.onHaptic = { impacts.append($0) }
        refresh(input, scene: scene)
        XCTAssertEqual(scene.simulation.headingPlayerID, 0)
        XCTAssertEqual(input.actionTitle, "HEAD")
        XCTAssertEqual(hud.status, "HEAD IT")
        XCTAssertEqual(try actionElement(in: input).accessibilityLabel, "Head ball")
        attach(input, named: "Header available — aim and tap")

        scene.pressAction()
        scene.simulation.updateActionHold(heldFor: 0.5)
        refresh(input, scene: scene)
        XCTAssertTrue(scene.simulation.isPreparingHeader)
        XCTAssertEqual(hud.status, "PREPARE HEADER")
        XCTAssertNil(scene.powerFeedback)
        XCTAssertEqual(scene.simulation.chargeFraction, 0, "Headers must not draw the foot-level power track either.")
        XCTAssertEqual(scene.simulation.slideCount, 0)
        scene.releaseAction(heldFor: 0.5)
        refresh(input, scene: scene)
        XCTAssertEqual(hud.status, "HEADER QUEUED")
        XCTAssertEqual(input.actionTitle, "HEADER")
        XCTAssertEqual(scene.simulation.headerCount, 0)
        XCTAssertTrue(impacts.isEmpty, "A prepared header has not contacted the ball yet.")
        attach(input, named: "Header queued — saved aim, no shot meter")

        scene.setGameplayPaused(true)
        refresh(input, scene: scene)
        XCTAssertNil(scene.simulation.queuedActionKind)
        XCTAssertFalse(scene.simulation.isPreparingHeader)
        XCTAssertEqual(hud.status, "PAUSED")
        scene.setGameplayPaused(false)
        for tick in 0..<40 { scene.update(10 + Double(tick) / 60) }
        XCTAssertEqual(scene.simulation.headerCount, 0)
        XCTAssertEqual(scene.simulation.slideCount, 0)
        XCTAssertTrue(impacts.isEmpty, "Resuming cannot replay a cancelled header.")
    }

    func testActualHeaderProducesOneLightImpactAndResetsItsPose() {
        let scene = headerScene(distance: 1, height: 1.6, speed: 0)
        var impacts: [GameplayHaptic] = []
        scene.onHaptic = { impacts.append($0) }
        scene.setMovement(Vector2(x: 1, y: 0))
        scene.pressAction()
        scene.releaseAction(heldFor: 0.08)
        for tick in 0..<4 { scene.update(20 + Double(tick) / 60) }
        XCTAssertEqual(scene.simulation.headerCount, 1)
        XCTAssertEqual(scene.simulation.lastHeaderPlayerID, 0)
        XCTAssertEqual(scene.simulation.lastKickKind, "header")
        XCTAssertEqual(impacts, [.pass])
        XCTAssertGreaterThan(scene.simulation.footballers[0].headingProgress, 0)
        XCTAssertGreaterThan(scene.simulation.ball.velocity.x, 0)
        scene.releaseAction(heldFor: 0.08)
        for tick in 4..<30 { scene.update(20 + Double(tick) / 60) }
        XCTAssertEqual(scene.simulation.headerCount, 1)
        XCTAssertEqual(impacts, [.pass], "Duplicate release and rendering cannot repeat header contact.")
        scene.resetSandbox()
        XCTAssertEqual(scene.simulation.footballers[0].headingProgress, 0)
        XCTAssertEqual(impacts, [.pass], "Reset is silent.")
    }

    func testDefensiveUpfieldHoldShowsHeightWithoutShotOverhitBand() throws {
        let scene = GameScene(mode: .solo)
        scene.simulation.player.position = Vector2(x: 0, y: -28)
        scene.simulation.ball.position = Vector2(x: 0, y: -26.75)
        let input = controls(for: scene)
        scene.setMovement(.up)
        scene.pressAction()
        scene.simulation.updateActionHold(heldFor: 0.8)
        refresh(input, scene: scene)
        let power = try XCTUnwrap(scene.powerFeedback)
        XCTAssertEqual(power.kind, .longKick)
        XCTAssertNil(power.sweetSpot)
        XCTAssertNil(power.overhitStart)
        XCTAssertFalse(power.overcharging)
        XCTAssertEqual(power.title, "HOLD FOR HEIGHT")
        attach(input, named: "Defensive clearance — hold for height and distance")
        scene.cancelTouches()
        XCTAssertNil(scene.powerFeedback)
    }

    func testContactHopPreservesGroundOriginAndRestoresCachedArtwork() throws {
        let canvas = SKScene(size: CGSize(width: 1100, height: 650))
        canvas.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let view = SKView(frame: CGRect(origin: .zero, size: canvas.size))
        let renderer = PitchRenderer()
        renderer.root.xScale = 40
        renderer.root.yScale = 40 * 0.86
        canvas.addChild(renderer.root)
        let stages = [0.0, 0.18, 0.35, 0.68, 1.0]
        var players = (0..<10).map { id in
            Footballer(id: id, team: id < 5 ? .blue : .red,
                       state: PlayerState(position: Vector2(x: Double(id % 5) * 5 - 10, y: id < 5 ? 3 : -3),
                                          facing: id < 5 ? .up : Vector2(x: 1, y: 0)))
        }
        func draw() {
            renderer.render(footballers: players, selectedPlayerID: 2, passTargetID: nil,
                            ball: BallState(position: Vector2(x: 0, y: 4), height: 1.6), hasControl: false,
                            chargeFraction: 0, aftertouchRemaining: 0, aftertouchVector: .zero,
                            debug: false, deltaTime: 0)
        }
        draw()
        let upright = poses(renderer.root)
        let player = try node("player-2", in: renderer.root)
        let figure = try node("figure", in: player)
        let marker = try node("selection", in: player)
        let shadow = try node("player-shadow-2", in: renderer.root)
        let rootPosition = player.position
        let markerPosition = marker.position
        let shadowPosition = shadow.position
        let standingHeight = figure.position.y
        for id in players.indices { players[id].headingProgress = stages[id % 5] }
        draw()
        XCTAssertGreaterThan(figure.position.y, standingHeight + 20)
        XCTAssertEqual(player.position, rootPosition)
        XCTAssertEqual(marker.position, markerPosition)
        XCTAssertEqual(shadow.position, shadowPosition)
        XCTAssertFalse(marker.isHidden)
        let contact = poses(renderer.root)
        for _ in 0..<20 { draw() }
        XCTAssertEqual(poses(renderer.root), contact, "Only simulation progress advances the contact pose.")
        for (column, title) in ["READY", "RISE", "HEADER", "LAND", "READY"].enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = title
            label.fontSize = 19
            label.position = CGPoint(x: Double(column) * 200 - 400, y: 275)
            label.zPosition = 100
            canvas.addChild(label)
        }
        let crop = CGRect(x: -550, y: -325, width: 1100, height: 650)
        let texture = try XCTUnwrap(view.texture(from: canvas, crop: crop))
        let attachment = XCTAttachment(image: UIImage(cgImage: texture.cgImage()))
        attachment.name = "Header contact — north and right, fixed ground markers"
        attachment.lifetime = .keepAlways
        add(attachment)
        for id in players.indices { players[id].headingProgress = 0 }
        draw()
        XCTAssertEqual(poses(renderer.root), upright, "Cached boots, limbs, figure and shadow must reset after contact.")
    }

    private func headerScene(distance: Double, height: Double, speed: Double) -> GameScene {
        let scene = GameScene(mode: .solo)
        scene.simulation.ball = BallState(position: Vector2(x: 20, y: 0), mode: .free)
        scene.simulation.step(dt: 1 / 60)
        scene.simulation.player = PlayerState(position: .zero)
        scene.simulation.ball = BallState(position: Vector2(x: 0, y: distance), velocity: Vector2(x: 0, y: speed),
                                         mode: .free, height: height, verticalVelocity: -1)
        return scene
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

    private func actionElement(in input: InputController) throws -> UIAccessibilityElement {
        try XCTUnwrap((input.accessibilityElements as? [UIAccessibilityElement])?
            .first { $0.accessibilityIdentifier == "sandbox.action" })
    }

    private func attach(_ input: InputController, named name: String) {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 440, height: 306)).image { context in
            UIColor(red: 0.08, green: 0.29, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 440, height: 306))
            context.cgContext.translateBy(x: 0, y: -650)
            input.draw(input.bounds)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func node(_ name: String, in root: SKNode) throws -> SKNode {
        try XCTUnwrap(nodes(root).first { $0.name == name })
    }

    private func nodes(_ root: SKNode) -> [SKNode] { [root] + root.children.flatMap(nodes) }

    private struct Pose: Equatable {
        let position: CGPoint
        let xScale: CGFloat
        let yScale: CGFloat
        let rotation: CGFloat
        let depth: CGFloat
        let hidden: Bool
    }

    private func poses(_ root: SKNode) -> [Pose] {
        nodes(root).map { Pose(position: $0.position, xScale: $0.xScale, yScale: $0.yScale,
                              rotation: $0.zRotation, depth: $0.zPosition, hidden: $0.isHidden) }
    }
}
