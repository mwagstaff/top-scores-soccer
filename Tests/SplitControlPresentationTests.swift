import XCTest
import UIKit
@testable import TopScoresSoccer

@MainActor
final class SplitControlPresentationTests: XCTestCase {
    func testButtonsHaveSeparateHitAreasAndAccessibleActionsAcrossViewports() throws {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 393, height: 852), CGSize(width: 744, height: 1133)] {
            let scene = GameScene(mode: .solo)
            let input = InputController(frame: CGRect(origin: .zero, size: size))
            input.scene = scene
            input.layoutIfNeeded()
            input.feedback(status: .idle, hasBall: true, curving: false)
            let elements = try XCTUnwrap(input.accessibilityElements as? [UIAccessibilityElement])
            let pass = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "sandbox.pass" })
            let shoot = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "sandbox.action" })
            XCTAssertNotNil(UIImage(systemName: input.passIconName))
            XCTAssertNotNil(UIImage(systemName: input.actionIconName))
            for element in [pass, shoot] {
                XCTAssertTrue(input.bounds.contains(element.accessibilityFrameInContainerSpace))
                XCTAssertGreaterThanOrEqual(element.accessibilityFrameInContainerSpace.width, 44)
            }
            XCTAssertFalse(pass.accessibilityFrameInContainerSpace.intersects(shoot.accessibilityFrameInContainerSpace))
            XCTAssertEqual(input.touchRole(at: CGPoint(x: pass.accessibilityFrameInContainerSpace.midX,
                y: pass.accessibilityFrameInContainerSpace.midY)), .pass)
            XCTAssertEqual(input.touchRole(at: CGPoint(x: shoot.accessibilityFrameInContainerSpace.midX,
                y: shoot.accessibilityFrameInContainerSpace.midY)), .action)
            XCTAssertEqual(shoot.accessibilityCustomActions?.count, 3)
            XCTAssertTrue(pass.accessibilityActivate())
            XCTAssertEqual(scene.simulation.kickCount, 1)
            XCTAssertEqual(scene.simulation.lastKick, .pass)
            scene.setGameplayPaused(true)
            XCTAssertFalse(shoot.accessibilityActivate())
            XCTAssertEqual(scene.simulation.kickCount, 1)
        }
    }
}
