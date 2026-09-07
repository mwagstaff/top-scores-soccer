import SwiftUI
import SpriteKit

struct GameSurface: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> SandboxSurfaceView {
        SandboxSurfaceView(scene: scene)
    }
    func updateUIView(_ uiView: SandboxSurfaceView, context: Context) {}
    static func dismantleUIView(_ uiView: SandboxSurfaceView, coordinator: ()) {
        uiView.tearDown()
    }
}

@MainActor
final class SandboxSurfaceView: UIView {
    private let spriteView = SKView()
    private let controls = InputController(frame: .zero)
    private let gameScene: GameScene
    init(scene: GameScene) {
        gameScene = scene
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(spriteView)
        addSubview(controls)
        spriteView.isUserInteractionEnabled = false
        controls.scene = scene
        scene.onResetInput = { [weak controls] in controls?.clearTouches() }
        scene.onControlFeedback = { [weak controls] status, hasBall, curving in
            controls?.feedback(status: status, hasBall: hasBall, curving: curving)
        }
        spriteView.presentScene(scene)
    }
    required init?(coder: NSCoder) { fatalError("Use init(scene:)") }
    override func layoutSubviews() {
        super.layoutSubviews()
        spriteView.frame = bounds
        controls.frame = bounds
    }
    func tearDown() {
        gameScene.cancelTouches()
        gameScene.onResetInput = nil
        gameScene.onControlFeedback = nil
        spriteView.presentScene(nil)
    }
}
