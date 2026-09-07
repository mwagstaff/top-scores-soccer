import XCTest
@testable import TopScoresSoccer

@MainActor
final class ReceiverCameraTests: XCTestCase {
    private let viewports = [CGSize(width: 393, height: 852), CGSize(width: 440, height: 956),
                             CGSize(width: 834, height: 1194)]
    private let top: CGFloat = 170
    private let bottom: CGFloat = 300

    func testTenToFortyMetreHandoverImmediatelyShowsBallAndReceiverInEveryDirection() {
        let directions = [Vector2.up, -.up, Vector2(x: 1, y: 0), Vector2(x: -1, y: 0),
                          Vector2(x: 1, y: 1).normalized, Vector2(x: -1, y: -1).normalized]
        for viewport in viewports {
            for matchMultiplier in [1.0, 1.08] {
                for distance in [10.0, 25, 40] {
                    for direction in directions {
                        let camera = CameraController()
                        let base = scale(for: viewport) * matchMultiplier
                        let ball = BallState(position: direction * (-distance / 2), velocity: .zero)
                        _ = camera.update(ball: ball, player: PlayerState(position: ball.position),
                                          viewport: viewport, scale: base, tuning: .defaults,
                                          deltaTime: 1 / 60, topInset: top, bottomInset: bottom)
                        let receiver = PlayerState(position: direction * (distance / 2))
                        let position = camera.update(ball: ball, player: receiver, viewport: viewport,
                                                     scale: base, tuning: .defaults, deltaTime: 1 / 60,
                                                     topInset: top, bottomInset: bottom, framingReceiver: true)
                        assertVisible(ball.position, camera: position, scale: camera.resolvedScale, viewport: viewport)
                        assertVisible(receiver.position, camera: position, scale: camera.resolvedScale, viewport: viewport)
                        XCTAssertNil(camera.receiverEdgeMarker)
                        XCTAssertLessThanOrEqual(camera.resolvedScale, base * 1.20 + 0.000001)
                    }
                }
            }
        }
    }

    func testMovingReceiverAndTravellingPassStayVisibleBeforeContact() {
        for viewport in viewports {
            let camera = CameraController()
            let base = scale(for: viewport)
            var ball = BallState(position: Vector2(x: -20, y: -8), velocity: Vector2(x: 21, y: 0), mode: .pass)
            var receiver = PlayerState(position: Vector2(x: 20, y: -8), velocity: Vector2(x: 2, y: 5))
            for _ in 0..<90 {
                let position = camera.update(ball: ball, player: receiver, viewport: viewport, scale: base,
                                             tuning: .defaults, deltaTime: 1 / 60,
                                             topInset: top, bottomInset: bottom, framingReceiver: true)
                assertVisible(ball.position, camera: position, scale: camera.resolvedScale, viewport: viewport)
                assertVisible(receiver.position, camera: position, scale: camera.resolvedScale, viewport: viewport)
                XCTAssertNil(camera.receiverEdgeMarker)
                // Independent physical trajectories exercise framing; no camera
                // decision is allowed to change the ball or receiver's movement.
                ball.position += ball.velocity / 60
                receiver.position += receiver.velocity / 60
            }
        }
    }

    func testTouchlineAndGoalLinePassesPreserveAirBallAndReceiverClearance() {
        let pairs: [(Vector2, Vector2)] = [
            (.init(x: -33, y: -20), .init(x: 7, y: -20)),
            (.init(x: 33, y: 20), .init(x: -7, y: 20)),
            (.init(x: 10, y: 51), .init(x: 10, y: 11)),
            (.init(x: -10, y: -51), .init(x: -10, y: -11))
        ]
        for viewport in viewports {
            let camera = CameraController()
            for (ballPosition, receiverPosition) in pairs {
                let ball = BallState(position: ballPosition, mode: .pass, height: 4)
                let position = camera.update(ball: ball, player: PlayerState(position: receiverPosition),
                                             viewport: viewport, scale: scale(for: viewport), tuning: .defaults,
                                             deltaTime: 1 / 60, topInset: top, bottomInset: bottom, framingReceiver: true)
                assertVisible(ballPosition, camera: position, scale: camera.resolvedScale, viewport: viewport, height: 4)
                assertVisible(receiverPosition, camera: position, scale: camera.resolvedScale, viewport: viewport)
                XCTAssertNil(camera.receiverEdgeMarker)
            }
        }
    }

    func testZoomReturnsGraduallyAfterReceptionAndResetRemovesIt() {
        for viewport in viewports {
            let camera = CameraController()
            let base = scale(for: viewport)
            // Exceed even the iPad's wider baseline so this exercises an actual
            // zoom and its return rather than an already-visible pair.
            let ball = BallState(position: Vector2(x: -30, y: 0))
            let receiver = PlayerState(position: Vector2(x: 30, y: 0))
            _ = camera.update(ball: ball, player: receiver, viewport: viewport, scale: base, tuning: .defaults,
                              deltaTime: 1 / 60, topInset: top, bottomInset: bottom, framingReceiver: true)
            let widened = camera.resolvedScale
            XCTAssertGreaterThan(widened, base)
            var previousScale = widened
            for _ in 0..<180 {
                let position = camera.update(ball: ball, player: receiver, viewport: viewport, scale: base,
                                             tuning: .defaults, deltaTime: 1 / 60,
                                             topInset: top, bottomInset: bottom)
                XCTAssertLessThanOrEqual(camera.resolvedScale, previousScale)
                XCTAssertGreaterThan(camera.resolvedScale, base)
                assertVisible(ball.position, camera: position, scale: camera.resolvedScale, viewport: viewport)
                previousScale = camera.resolvedScale
            }
            XCTAssertEqual(camera.resolvedScale, base, accuracy: 0.00001)
            camera.reset(to: .zero)
            XCTAssertNil(camera.receiverEdgeMarker)
            _ = camera.update(ball: ball, player: receiver, viewport: viewport, scale: base, tuning: .defaults,
                              deltaTime: 0, topInset: top, bottomInset: bottom)
            XCTAssertEqual(camera.resolvedScale, base)
        }
    }

    func testExceptionalSpanUsesReadableEdgeMarkerWithoutLosingBallOrUnlimitedZoom() throws {
        for viewport in viewports {
            let camera = CameraController()
            let base = scale(for: viewport)
            let ball = BallState(position: Vector2(x: -32, y: -45))
            let receiver = PlayerState(position: Vector2(x: 32, y: 45))
            let position = camera.update(ball: ball, player: receiver, viewport: viewport, scale: base,
                                         tuning: .defaults, deltaTime: 1 / 60,
                                         topInset: top, bottomInset: bottom, framingReceiver: true)
            assertVisible(ball.position, camera: position, scale: camera.resolvedScale, viewport: viewport)
            XCTAssertLessThanOrEqual(camera.resolvedScale, base * 1.20 + 0.000001)
            let marker = try XCTUnwrap(camera.receiverEdgeMarker)
            XCTAssertGreaterThanOrEqual(marker.position.x + viewport.width / 2, 24)
            XCTAssertLessThanOrEqual(marker.position.x + viewport.width / 2, viewport.width - 24)
            XCTAssertGreaterThanOrEqual(marker.position.y + viewport.height / 2, bottom + 24)
            XCTAssertLessThanOrEqual(marker.position.y + viewport.height / 2, viewport.height - top - 24)
            _ = camera.update(ball: ball, player: receiver, viewport: viewport, scale: base,
                              tuning: .defaults, deltaTime: 1 / 60, topInset: top, bottomInset: bottom)
            XCTAssertNil(camera.receiverEdgeMarker)
        }
    }

    private func scale(for viewport: CGSize) -> CGFloat {
        CameraController.recommendedScale(viewport: viewport, topInset: top, bottomInset: bottom)
    }

    private func assertVisible(_ point: Vector2, camera: CGPoint, scale: CGFloat, viewport: CGSize,
                               height: Double = 0, file: StaticString = #filePath, line: UInt = #line) {
        let x = (point.x - camera.x) / scale + viewport.width / 2
        let y = (point.y * 0.86 - camera.y) / scale + viewport.height / 2
        let margin = 1.8 / scale
        XCTAssertGreaterThanOrEqual(x - margin, -0.00001, file: file, line: line)
        XCTAssertLessThanOrEqual(x + margin, viewport.width + 0.00001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(y - margin, bottom - 0.00001, file: file, line: line)
        let topExtent = height > 0 ? (height + 0.6) / scale : margin
        XCTAssertLessThanOrEqual(y + topExtent, viewport.height - top + 0.00001, file: file, line: line)
    }
}
