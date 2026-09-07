import SpriteKit
import XCTest
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import TopScoresSoccer

@MainActor
final class PitchRendererTests: XCTestCase {
    func testPassPreviewAndControlHandoverHaveDistinctShapesAndRenderAttachments() throws {
        let canvas = SKScene(size: CGSize(width: 760, height: 480))
        canvas.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let view = SKView(frame: CGRect(origin: .zero, size: canvas.size))
        let renderer = PitchRenderer()
        renderer.root.xScale = 35
        renderer.root.yScale = 35 * 0.86
        canvas.addChild(renderer.root)
        let players = [Footballer(id: 0, team: .blue, state: PlayerState(position: Vector2(x: -6, y: -1))),
                       Footballer(id: 1, team: .blue, state: PlayerState(position: Vector2(x: 6, y: 1)))]
        func draw(selected: Int, ball: Vector2, dt: Double = 0) {
            renderer.render(footballers: players, selectedPlayerID: selected, passTargetID: 1,
                            ball: BallState(position: ball), hasControl: selected == 0,
                            chargeFraction: 0, aftertouchRemaining: 0, aftertouchVector: .zero,
                            debug: false, deltaTime: dt)
        }
        draw(selected: 0, ball: Vector2(x: -4.75, y: -1))
        let passer = try named("player-0", in: renderer.root)
        let receiver = try named("player-1", in: renderer.root)
        let selectedRing = try XCTUnwrap(named("selection", in: passer) as? SKShapeNode)
        let target = try XCTUnwrap(named("pass-target", in: receiver) as? SKShapeNode)
        XCTAssertFalse(selectedRing.isHidden)
        XCTAssertFalse(target.isHidden)
        XCTAssertTrue(try named("selection", in: receiver).isHidden)
        XCTAssertNotEqual(target.path?.boundingBox, selectedRing.path?.boundingBox)
        XCTAssertTrue(try named("control-handover", in: passer).isHidden,
                      "An initial scene is not a control handover.")
        try attach(canvas, using: view, named: "Pass preview — yellow control ring and cyan target brackets")

        draw(selected: 1, ball: Vector2(x: -2, y: 0))
        XCTAssertTrue(selectedRing.isHidden)
        XCTAssertTrue(target.isHidden)
        XCTAssertFalse(try named("selection", in: receiver).isHidden)
        let pulse = try named("control-handover", in: receiver)
        XCTAssertFalse(pulse.isHidden)
        for _ in 0..<4 { draw(selected: 1, ball: Vector2(x: -2, y: 0), dt: 0.05) }
        XCTAssertGreaterThan(pulse.xScale, 1)
        XCTAssertGreaterThan(pulse.alpha, 0)
        try attach(canvas, using: view, named: "Pass handover — receiver now controlled, expanding yellow pulse")
        for _ in 0..<15 { draw(selected: 1, ball: Vector2(x: -2, y: 0), dt: 0.05) }
        XCTAssertTrue(pulse.isHidden)
        XCTAssertFalse(try named("selection", in: receiver).isHidden)
        try attach(canvas, using: view, named: "Receiver control — stable yellow ring after pulse")

        renderer.resetControlFeedback()
        draw(selected: 0, ball: Vector2(x: -4.75, y: -1))
        XCTAssertTrue(try named("control-handover", in: passer).isHidden)
        XCTAssertTrue(pulse.isHidden)
        XCTAssertFalse(target.isHidden)
    }

    func testFallProgressionAndResetRenderAttachments() throws {
        let size = CGSize(width: 1100, height: 720)
        let scene = SKScene(size: size)
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let renderer = PitchRenderer()
        renderer.root.xScale = 40
        renderer.root.yScale = 40 * 0.86
        scene.addChild(renderer.root)

        let directions = [Vector2.up, Vector2(x: 1, y: 0), Vector2(x: -1, y: -0.4).normalized]
        let stages = [0.0, 0.18, 0.35, 0.62, 1.0]
        var footballers: [Footballer] = []
        for row in directions.indices {
            for column in stages.indices {
                let id = row * stages.count + column
                var state = PlayerState()
                state.position = Vector2(x: Double(column) * 5 - 10, y: 6 - Double(row) * 6)
                state.facing = directions[row]
                var footballer = Footballer(id: id, team: row == 1 ? .blue : .red, state: state)
                footballer.fallDirection = directions[row]
                footballers.append(footballer)
            }
        }
        render(footballers, with: renderer)
        let upright = snapshot(renderer.root)
        for id in footballers.indices { footballers[id].fallProgress = stages[id % stages.count] }
        render(footballers, with: renderer)
        XCTAssertNotEqual(snapshot(renderer.root), upright)

        var labels: [SKLabelNode] = []
        for (column, title) in ["UPRIGHT", "STUMBLE", "IMPACT", "RECOIL", "DOWN"].enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = title
            label.fontSize = 19
            label.fontColor = .white
            label.position = CGPoint(x: Double(column) * 200 - 400, y: 310)
            label.zPosition = 100
            scene.addChild(label)
            labels.append(label)
        }
        try attach(scene, using: view, named: "Fall progression — north, right and diagonal")

        // A whistle or a paused frame may leave the victim prone for some time.
        // Rendering that state repeatedly must not fade it away or stand it up.
        let fallen = snapshot(renderer.root)
        for _ in 0..<30 { render(footballers, with: renderer) }
        XCTAssertEqual(snapshot(renderer.root), fallen)
        for node in allNodes(renderer.root) where node.name?.hasPrefix("player-") == true {
            XCTAssertFalse(node.isHidden)
            XCTAssertEqual(node.alpha, 1)
        }

        let recoveries = [0.0, 0.22, 0.5, 0.78, 1.0]
        for id in footballers.indices {
            let offender = id / stages.count == 2
            footballers[id].fallProgress = offender ? 0 : 1
            footballers[id].isSliding = offender
            footballers[id].recoveryProgress = recoveries[id % stages.count]
        }
        for (label, title) in zip(labels, ["DOWN", "PLANT HANDS", "KNEEL", "PUSH UP", "STAND"]) {
            label.text = title
        }
        render(footballers, with: renderer)
        try attach(scene, using: view, named: "Foul recovery — victims above, sliding offender below")
        let recovering = snapshot(renderer.root)
        for _ in 0..<30 { render(footballers, with: renderer) }
        XCTAssertEqual(snapshot(renderer.root), recovering,
                       "Core progress owns the get-up clock; repeated rendering cannot skip its stages.")

        for id in footballers.indices { footballers[id].recoveryProgress = 1 }
        render(footballers, with: renderer)
        assertMatchingPoses(snapshot(renderer.root), upright,
                            "Both victim and slider should already be standing before free-kick placement.")

        // Exercise cached artwork, rather than constructing a fresh renderer.
        for id in footballers.indices {
            footballers[id].fallProgress = 0
            footballers[id].recoveryProgress = 0
            footballers[id].isSliding = false
        }
        render(footballers, with: renderer)
        XCTAssertEqual(snapshot(renderer.root), upright,
                       "Restart must restore the figure, boots, arms, hair, shadow and marker transforms.")
        for label in labels { label.text = "RESET" }
        try attach(scene, using: view, named: "Fall reset — cached players standing again")
    }

    func testGettingUpBeginsContinuouslyFromProneAndStoppedSlide() {
        for sliding in [false, true] {
            let renderer = PitchRenderer()
            var footballer = Footballer(id: 0, team: .blue, state: PlayerState())
            footballer.state.facing = Vector2(x: 1, y: 0)
            footballer.fallDirection = footballer.state.facing
            footballer.fallProgress = sliding ? 0 : 1
            footballer.isSliding = sliding
            render([footballer], with: renderer)
            let down = snapshot(renderer.root)
            footballer.recoveryProgress = 0.000001
            render([footballer], with: renderer)
            assertMatchingPoses(snapshot(renderer.root), down,
                                "Starting the get-up clock must not pop the head, boots, body or shadow into a new pose.")
        }
    }

    func testDismissedSliderRemainsVisibleThroughRecoveryUntilPlacement() throws {
        let renderer = PitchRenderer()
        var footballer = Footballer(id: 0, team: .red, state: PlayerState())
        footballer.isSentOff = true
        footballer.isSliding = true
        for recovery in [0.0, 0.5, 1.0] {
            footballer.recoveryProgress = recovery
            render([footballer], with: renderer)
            for name in ["player-0", "player-shadow-0"] {
                let node = try XCTUnwrap(allNodes(renderer.root).first { $0.name == name })
                XCTAssertFalse(node.isHidden, "A red card must not interrupt the visible foul sequence.")
                XCTAssertEqual(node.alpha, 1)
            }
        }

        footballer.isSliding = false
        render([footballer], with: renderer)
        for name in ["player-0", "player-shadow-0"] {
            let node = try XCTUnwrap(allNodes(renderer.root).first { $0.name == name })
            XCTAssertTrue(node.isHidden, "The dismissed player leaves when the aftermath has finished.")
        }
    }

    func testTenPlayerLineupMakesBothAutonomousKeepersDistinct() throws {
        let size = CGSize(width: 1100, height: 520)
        let scene = SKScene(size: size)
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let renderer = PitchRenderer()
        renderer.root.xScale = 40
        renderer.root.yScale = 40 * 0.86
        scene.addChild(renderer.root)
        let roster = lineup()
        renderer.render(footballers: roster, selectedPlayerID: 0, passTargetID: 1,
                        ball: BallState(position: Vector2(x: -8.2, y: 3.4)), hasControl: true,
                        chargeFraction: 0, aftertouchRemaining: 0, aftertouchVector: .zero,
                        debug: false, deltaTime: 0)

        for footballer in roster {
            let player = try named("player-\(footballer.id)", in: renderer.root)
            XCTAssertFalse(player.isHidden)
            XCTAssertEqual(allNodes(renderer.root).filter { $0.name == player.name }.count, 1)
            let gloves = try named("keeper-gloves", in: player)
            let badge = try named("keeper-badge", in: player)
            XCTAssertEqual(gloves.isHidden, !footballer.isGoalkeeper)
            XCTAssertEqual(badge.isHidden, !footballer.isGoalkeeper)
            if footballer.isGoalkeeper {
                XCTAssertTrue(allNodes(badge).contains { ($0 as? SKLabelNode)?.text == "GK" })
                XCTAssertTrue(try named("selection", in: player).isHidden)
            }
        }
        let blueShirt = try XCTUnwrap(named("shirt", in: named("player-0", in: renderer.root)) as? SKShapeNode)
        let blueKeeper = try XCTUnwrap(named("shirt", in: named("player-4", in: renderer.root)) as? SKShapeNode)
        let redShirt = try XCTUnwrap(named("shirt", in: named("player-5", in: renderer.root)) as? SKShapeNode)
        let redKeeper = try XCTUnwrap(named("shirt", in: named("player-9", in: renderer.root)) as? SKShapeNode)
        XCTAssertNotEqual(blueKeeper.fillColor, blueShirt.fillColor)
        XCTAssertNotEqual(redKeeper.fillColor, redShirt.fillColor)
        XCTAssertNotEqual(blueKeeper.fillColor, redKeeper.fillColor)

        for (index, text) in ["BLUE: FOUR OUTFIELD + GOALKEEPER", "RED: FOUR OUTFIELD + GOALKEEPER"].enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = text
            label.fontSize = 17
            label.position = CGPoint(x: 0, y: index == 0 ? 215 : -35)
            label.zPosition = 100
            scene.addChild(label)
        }
        try attach(scene, using: view, named: "Five-a-side lineup — contrasting goalkeeper kits and role badges")
    }

    func testCachedKeeperArtworkUpdatesRoleAndRemovesDepartingMatchPlayers() throws {
        let renderer = PitchRenderer()
        var roster = lineup()
        render(roster, with: renderer)
        let goalkeeper = try named("player-4", in: renderer.root)
        roster[4].isGoalkeeper = false
        render(roster, with: renderer)
        let outfield = try named("player-4", in: renderer.root)
        XCTAssertFalse(outfield === goalkeeper, "A role change must rebuild the cached jersey as well as its gloves.")
        XCTAssertTrue(try named("keeper-gloves", in: outfield).isHidden)
        XCTAssertTrue(try named("keeper-badge", in: outfield).isHidden)

        roster[4].isGoalkeeper = true
        render(roster, with: renderer)
        XCTAssertFalse(try named("keeper-badge", in: named("player-4", in: renderer.root)).isHidden)

        // Returning to the six-player exercise must remove every old match-only
        // figure and shadow, even when existing IDs now have a different role/team.
        let exercise = (0..<6).map { id in
            Footballer(id: id, team: id < 3 ? .blue : .red, state: roster[id].state)
        }
        render(exercise, with: renderer)
        for id in 6..<10 {
            XCTAssertFalse(allNodes(renderer.root).contains { $0.name == "player-\(id)" || $0.name == "player-shadow-\(id)" })
        }
        for footballer in exercise {
            let player = try named("player-\(footballer.id)", in: renderer.root)
            XCTAssertTrue(try named("keeper-gloves", in: player).isHidden)
            XCTAssertTrue(try named("keeper-badge", in: player).isHidden)
        }
    }

    func testKeeperDiveUsesExplicitExtentAndResetsItsGlovesAndBody() throws {
        let size = CGSize(width: 1100, height: 650)
        let scene = SKScene(size: size)
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let renderer = PitchRenderer()
        renderer.root.xScale = 40
        renderer.root.yScale = 40 * 0.86
        scene.addChild(renderer.root)
        var footballers = (0..<6).map { id in
            var state = PlayerState()
            state.position = Vector2(x: Double(id % 3) * 8 - 8, y: id < 3 ? 3.5 : -4)
            state.facing = Vector2(x: id < 3 ? -1 : 1, y: 0)
            var footballer = Footballer(id: id, team: id < 3 ? .blue : .red, state: state)
            footballer.isGoalkeeper = true
            return footballer
        }
        render(footballers, with: renderer)
        let upright = snapshot(renderer.root)
        for id in footballers.indices { footballers[id].goalkeeperDiveProgress = Double(id % 3) / 2 }
        render(footballers, with: renderer)
        for id in [2, 5] {
            let keeper = try named("player-\(id)", in: renderer.root)
            let figure = try named("figure", in: keeper)
            XCTAssertEqual(figure.zRotation, id == 2 ? .pi / 2 : -.pi / 2, accuracy: 0.000001)
            XCTAssertGreaterThan(try named("left-glove", in: keeper).position.y, 40)
            XCTAssertGreaterThan(try named("right-glove", in: keeper).position.y, 40)
            XCTAssertFalse(try named("keeper-badge", in: keeper).isHidden)
        }
        let extended = snapshot(renderer.root)
        for _ in 0..<30 { render(footballers, with: renderer) }
        XCTAssertEqual(snapshot(renderer.root), extended, "Repeated render frames must not advance the simulation-owned dive.")
        for (column, title) in ["READY", "REACH", "FULL SAVE"].enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = title
            label.fontSize = 19
            label.position = CGPoint(x: Double(column) * 320 - 320, y: 275)
            label.zPosition = 100
            scene.addChild(label)
        }
        try attach(scene, using: view, named: "Goalkeeper saves — left and right, explicit pose extent")

        for id in footballers.indices { footballers[id].goalkeeperDiveProgress = 0 }
        render(footballers, with: renderer)
        assertMatchingPoses(snapshot(renderer.root), upright,
                            "Save recovery and restarts must restore cached gloves, boots, body and shadow.")
    }

    func testManualKeeperRingAndHeldBallPoseRestoreToFeet() throws {
        let size = CGSize(width: 580, height: 420)
        let scene = SKScene(size: size)
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let renderer = PitchRenderer()
        renderer.root.xScale = 80
        renderer.root.yScale = 80 * 0.86
        scene.addChild(renderer.root)
        var keeper = Footballer(id: 4, team: .blue, state: PlayerState(position: .zero))
        keeper.isGoalkeeper = true
        let ball = BallState(position: Vector2(x: 0, y: 1.25))
        func draw(controlled: Bool, holding: Bool) {
            renderer.render(footballers: [keeper], selectedPlayerID: 4, passTargetID: nil,
                            ball: ball, hasControl: controlled, chargeFraction: 0,
                            aftertouchRemaining: 0, aftertouchVector: .zero,
                            debug: false, deltaTime: 0, controlledGoalkeeper: controlled,
                            holdingGoalkeeperID: holding ? 4 : nil)
        }
        draw(controlled: false, holding: false)
        let player = try named("player-4", in: renderer.root)
        XCTAssertTrue(try named("selection", in: player).isHidden)
        draw(controlled: true, holding: false)
        XCTAssertFalse(try named("selection", in: player).isHidden)
        let feet = snapshot(player)
        let footBall = try named("football", in: renderer.root).position
        try attach(scene, using: view, named: "Manual keeper — ball at feet")
        draw(controlled: true, holding: true)
        XCTAssertFalse(try named("selection", in: player).isHidden)
        XCTAssertNotEqual(try named("football", in: renderer.root).position, footBall)
        XCTAssertTrue(try named("football-shadow", in: renderer.root).isHidden)
        XCTAssertGreaterThan(try named("left-glove", in: player).position.y, 20)
        XCTAssertLessThan(abs(try named("left-glove", in: player).position.x), 12)
        try attach(scene, using: view, named: "Manual keeper — ball held between gloves")
        keeper.goalkeeperDiveProgress = 0.8
        keeper.state.facing = Vector2(x: -1, y: 0)
        draw(controlled: true, holding: true)
        XCTAssertTrue(try named("football-shadow", in: renderer.root).isHidden)
        try attach(scene, using: view, named: "Keeper diving catch — held ball follows gloves")
        keeper.goalkeeperDiveProgress = 0
        keeper.state.facing = .up
        draw(controlled: true, holding: false)
        XCTAssertEqual(snapshot(player), feet, "Releasing a held ball restores the cached hands, limbs and ring.")
        XCTAssertEqual(try named("football", in: renderer.root).position, footBall)
        XCTAssertFalse(try named("football-shadow", in: renderer.root).isHidden)
    }

    func testKeeperReleasePosesDistinguishUnderarmOverarmAndGoalKickThenReset() throws {
        let size = CGSize(width: 960, height: 420)
        let scene = SKScene(size: size)
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let renderer = PitchRenderer()
        renderer.root.xScale = 60
        renderer.root.yScale = 60 * 0.86
        scene.addChild(renderer.root)
        let kinds: [GoalkeeperReleaseKind] = [.underarmThrow, .overarmThrow, .goalKick]
        var keepers = kinds.indices.map { index in
            var player = Footballer(id: index, team: .blue,
                state: PlayerState(position: Vector2(x: Double(index - 1) * 5, y: 0)))
            player.isGoalkeeper = true
            return player
        }
        for (index, title) in ["UNDERARM THROW", "OVERARM THROW", "GOAL KICK"].enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = title
            label.fontSize = 17
            label.fontColor = .white
            label.position = CGPoint(x: Double(index - 1) * 300, y: 160)
            label.zPosition = 100
            scene.addChild(label)
        }
        render(keepers, with: renderer)
        let baseline = snapshot(renderer.root)
        for id in keepers.indices {
            keepers[id].goalkeeperReleaseKind = kinds[id]
            keepers[id].goalkeeperReleaseProgress = 0.10
            keepers[id].goalkeeperReleaseDirection = .up
        }
        render(keepers, with: renderer)
        let underarm = try named("player-0", in: renderer.root)
        let overarm = try named("player-1", in: renderer.root)
        let goalKick = try named("player-2", in: renderer.root)
        XCTAssertGreaterThan(try named("right-glove", in: overarm).position.y,
                             try named("right-glove", in: underarm).position.y + 15)
        XCTAssertGreaterThan(try named("right-boot", in: goalKick).position.y,
                             try named("right-boot", in: underarm).position.y + 8)
        for id in keepers.indices {
            let player = try named("player-\(id)", in: renderer.root)
            XCTAssertEqual(player.position.x, keepers[id].state.position.x * 20)
            XCTAssertEqual(player.position.y, 0)
        }
        try attach(scene, using: view, named: "Keeper release — low underarm, raised overarm, kicking foot")
        for id in keepers.indices { keepers[id].goalkeeperReleaseProgress = 0.60 }
        render(keepers, with: renderer)
        try attach(scene, using: view, named: "Keeper release — arm and foot follow-through")
        keepers[1].goalkeeperReleaseProgress = 0.10
        keepers[1].goalkeeperReleaseDirection = Vector2(x: -1, y: 0)
        render(keepers, with: renderer)
        XCTAssertGreaterThan(try named("left-glove", in: overarm).position.y, 35,
                             "The committed throw direction chooses the extending arm.")
        for id in keepers.indices {
            keepers[id].goalkeeperReleaseProgress = 0
            keepers[id].goalkeeperReleaseKind = nil
            keepers[id].goalkeeperReleaseDirection = .up
        }
        render(keepers, with: renderer)
        assertMatchingPoses(snapshot(renderer.root), baseline,
                            "The next frame and any restart restore cached gloves, limbs and body.")
        try attach(scene, using: view, named: "Keeper release — recovered upright")
    }

    private func lineup() -> [Footballer] {
        (0..<10).map { id in
            var state = PlayerState()
            state.position = Vector2(x: Double(id % 5) * 5 - 10, y: id < 5 ? 3 : -3.5)
            var footballer = Footballer(id: id, team: id < 5 ? .blue : .red, state: state)
            footballer.isGoalkeeper = id == 4 || id == 9
            return footballer
        }
    }

    private func named(_ name: String, in root: SKNode) throws -> SKNode {
        try XCTUnwrap(allNodes(root).first { $0.name == name }, "Missing artwork node \(name)")
    }

    private func assertMatchingPoses(_ actual: [NodePose], _ expected: [NodePose], _ message: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, message, file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a.position.x, e.position.x, accuracy: 0.0001, message, file: file, line: line)
            XCTAssertEqual(a.position.y, e.position.y, accuracy: 0.0001, message, file: file, line: line)
            XCTAssertEqual(a.xScale, e.xScale, accuracy: 0.0001, message, file: file, line: line)
            XCTAssertEqual(a.yScale, e.yScale, accuracy: 0.0001, message, file: file, line: line)
            XCTAssertEqual(a.rotation, e.rotation, accuracy: 0.0001, message, file: file, line: line)
            XCTAssertEqual(a.zPosition, e.zPosition, accuracy: 0.0001, message, file: file, line: line)
            XCTAssertEqual(a.alpha, e.alpha, accuracy: 0.0001, message, file: file, line: line)
            XCTAssertEqual(a.hidden, e.hidden, message, file: file, line: line)
        }
    }

    private func render(_ footballers: [Footballer], with renderer: PitchRenderer) {
        renderer.render(footballers: footballers, selectedPlayerID: -1, passTargetID: nil,
                        ball: BallState(position: Vector2(x: 25, y: 25)), hasControl: false,
                        chargeFraction: 0, aftertouchRemaining: 0, aftertouchVector: .zero,
                        debug: false, deltaTime: 1 / 60)
    }

    private func attach(_ scene: SKScene, using view: SKView, named name: String) throws {
        let crop = CGRect(x: -scene.size.width / 2, y: -scene.size.height / 2,
                          width: scene.size.width, height: scene.size.height)
        let texture = try XCTUnwrap(view.texture(from: scene, crop: crop))
        let rendered = texture.cgImage()
        XCTAssertGreaterThanOrEqual(rendered.width, Int(scene.size.width))
        XCTAssertGreaterThanOrEqual(rendered.height, Int(scene.size.height))
        #if canImport(UIKit)
        let image = UIImage(cgImage: rendered)
        #else
        let image = NSImage(cgImage: rendered, size: scene.size)
        #endif
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct NodePose: Equatable {
        let position: CGPoint
        let xScale: CGFloat
        let yScale: CGFloat
        let rotation: CGFloat
        let zPosition: CGFloat
        let alpha: CGFloat
        let hidden: Bool
    }

    private func snapshot(_ root: SKNode) -> [NodePose] {
        allNodes(root).map {
            NodePose(position: $0.position, xScale: $0.xScale, yScale: $0.yScale,
                     rotation: $0.zRotation, zPosition: $0.zPosition,
                     alpha: $0.alpha, hidden: $0.isHidden)
        }
    }

    private func allNodes(_ root: SKNode) -> [SKNode] {
        [root] + root.children.flatMap { allNodes($0) }
    }
}
