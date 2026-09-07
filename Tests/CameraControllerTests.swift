import XCTest
@testable import TopScoresSoccer

@MainActor
final class CameraControllerTests: XCTestCase {
    private let viewports = [CGSize(width: 440, height: 956), CGSize(width: 834, height: 1194)]
    private let topInset: CGFloat = 170
    private let bottomInset: CGFloat = 300

    func testBallRemainsInPlayableAreaAtEveryPitchBoundaryOnPhoneAndPad() {
        let xPositions = [-Pitch.width / 2 - Pitch.ballRadius, 0, Pitch.width / 2 + Pitch.ballRadius]
        let yPositions = [-Pitch.length / 2 - Pitch.ballRadius, 0, Pitch.length / 2 + Pitch.ballRadius]
        for viewport in viewports {
            let scale = CameraController.recommendedScale(viewport: viewport, topInset: topInset, bottomInset: bottomInset)
            let camera = CameraController()
            for x in xPositions {
                for y in yPositions {
                    let ball = BallState(position: Vector2(x: x, y: y))
                    let position = camera.update(ball: ball, player: PlayerState(), viewport: viewport,
                                                 scale: scale, tuning: .defaults, deltaTime: 1 / 60,
                                                 topInset: topInset, bottomInset: bottomInset)
                    assertVisible(ball: ball, camera: position, viewport: viewport, scale: scale)
                }
            }
        }
    }

    func testMaximumPowerShotsStayVisibleThroughLongFramesAndCameraReversals() {
        let directions: [Vector2] = [.up, -.up, Vector2(x: 1, y: 0), Vector2(x: -1, y: 0),
                                     Vector2(x: 1, y: 1).normalized, Vector2(x: -1, y: -1).normalized]
        for viewport in viewports {
            let scale = CameraController.recommendedScale(viewport: viewport, topInset: topInset, bottomInset: bottomInset)
            for direction in directions {
                let camera = CameraController()
                camera.reset(to: .zero)
                var ball = BallState(position: .zero, velocity: direction * GameplayTuning.defaults.shotMaxSpeed, mode: .shot)
                // A very low response exposes any reliance on smoothing to keep the
                // ball visible. The visibility envelope must protect the action.
                var tuning = GameplayTuning.defaults
                tuning.cameraSmoothing = 0.25
                for frame in 0..<90 {
                    let dt = frame.isMultiple(of: 11) ? 0.1 : 1.0 / 60
                    ball.position += ball.velocity * dt
                    if abs(ball.position.x) > Pitch.width / 2 || abs(ball.position.y) > Pitch.length / 2 {
                        ball.position.x = min(Pitch.width / 2, max(-Pitch.width / 2, ball.position.x))
                        ball.position.y = min(Pitch.length / 2, max(-Pitch.length / 2, ball.position.y))
                        ball.velocity *= -1
                    }
                    let position = camera.update(ball: ball, player: PlayerState(), viewport: viewport,
                                                 scale: scale, tuning: tuning, deltaTime: dt,
                                                 topInset: topInset, bottomInset: bottomInset)
                    assertVisible(ball: ball, camera: position, viewport: viewport, scale: scale)
                }
            }
        }
    }

    func testChangingSelectedPlayerDoesNotPullCameraAwayFromStationaryBall() {
        for viewport in viewports {
            let camera = CameraController()
            let scale = CameraController.recommendedScale(viewport: viewport, topInset: topInset, bottomInset: bottomInset)
            let ball = BallState(position: .zero)
            var player = PlayerState(position: Vector2(x: -30, y: -48))
            let first = camera.update(ball: ball, player: player, viewport: viewport, scale: scale,
                                      tuning: .defaults, deltaTime: 1 / 60, topInset: topInset, bottomInset: bottomInset)
            player.position = Vector2(x: 30, y: 48)
            var last = first
            for _ in 0..<120 {
                last = camera.update(ball: ball, player: player, viewport: viewport, scale: scale,
                                     tuning: .defaults, deltaTime: 1 / 60, topInset: topInset, bottomInset: bottomInset)
                assertVisible(ball: ball, camera: last, viewport: viewport, scale: scale)
            }
            XCTAssertLessThan(hypot(last.x - first.x, last.y - first.y), 1.21,
                              "A remote player switch should only gently bias the ball camera.")
        }
    }

    func testChipAndGroundShadowStayVisibleAtCornersAndNorthGoal() {
        let boundaryPositions = [
            Vector2(x: -Pitch.width / 2, y: Pitch.length / 2),
            Vector2(x: Pitch.width / 2, y: Pitch.length / 2),
            Vector2(x: -Pitch.width / 2, y: -Pitch.length / 2),
            Vector2(x: Pitch.width / 2, y: -Pitch.length / 2),
            Vector2(x: 0, y: Pitch.length / 2 + Pitch.ballRadius)
        ]
        for viewport in viewports {
            let scale = CameraController.recommendedScale(viewport: viewport, topInset: topInset, bottomInset: bottomInset)
            let camera = CameraController()
            for point in boundaryPositions {
                for height in [0.0, 8.0 * 8 / (2 * 18), 4.0] {
                    var ball = BallState(position: point, mode: .pass)
                    ball.height = height
                    let position = camera.update(ball: ball, player: PlayerState(), viewport: viewport,
                                                 scale: scale, tuning: .defaults, deltaTime: 1 / 60,
                                                 topInset: topInset, bottomInset: bottomInset)
                    assertVisible(ball: ball, camera: position, viewport: viewport, scale: scale)
                }
            }
        }
    }

    func testLoftedShotTracksAscentAndDescentWithoutHidingGroundShadow() {
        for viewport in viewports {
            let scale = CameraController.recommendedScale(viewport: viewport, topInset: topInset, bottomInset: bottomInset)
            for lift in [8.0, 12.0] {
                let camera = CameraController()
                var ball = BallState(position: Vector2(x: -20, y: -40),
                                     velocity: Vector2(x: 0.3, y: 1).normalized * 47, mode: .shot)
                var elapsed = 0.0
                for frame in 0..<100 {
                    let dt = frame.isMultiple(of: 9) ? 0.1 : 1.0 / 60
                    elapsed += dt
                    ball.height = max(0, lift * elapsed - 0.5 * 18 * elapsed * elapsed)
                    ball.verticalVelocity = ball.height > 0 ? lift - 18 * elapsed : 0
                    ball.position += ball.velocity * dt
                    if abs(ball.position.y) > Pitch.length / 2 {
                        ball.position.y = min(Pitch.length / 2, max(-Pitch.length / 2, ball.position.y))
                        ball.velocity *= -1
                    }
                    let position = camera.update(ball: ball, player: PlayerState(), viewport: viewport,
                                                 scale: scale, tuning: .defaults, deltaTime: dt,
                                                 topInset: topInset, bottomInset: bottomInset)
                    assertVisible(ball: ball, camera: position, viewport: viewport, scale: scale)
                }
            }
        }
    }

    private func assertVisible(ball: BallState, camera: CGPoint, viewport: CGSize, scale: CGFloat,
                               file: StaticString = #filePath, line: UInt = #line) {
        let screenX = (ball.position.x - camera.x) / scale + viewport.width / 2
        let groundScreenY = (ball.position.y * 0.86 - camera.y) / scale + viewport.height / 2
        let height = max(0, ball.height)
        let screenY = groundScreenY + height / scale
        let ballRadius = CGFloat(Pitch.ballRadius + 0.17) * (1 + min(height, 5) * 0.035) / scale
        XCTAssertGreaterThanOrEqual(screenX - ballRadius, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(screenX + ballRadius, viewport.width, file: file, line: line)
        XCTAssertGreaterThanOrEqual(screenY - ballRadius, bottomInset, file: file, line: line)
        XCTAssertLessThanOrEqual(screenY + ballRadius, viewport.height - topInset, file: file, line: line)
        let shadowBottom = groundScreenY - (0.13 + 0.31 * (1 + min(height, 5) * 0.07)) * 0.86 / scale
        XCTAssertGreaterThanOrEqual(shadowBottom, bottomInset, "Ground shadow must remain above the controls.", file: file, line: line)
    }
}
