import CoreGraphics
import Foundation

/// Follows the action in projected pitch coordinates, accounting for the playable
/// area between the native HUD and thumb controls rather than the whole display.
@MainActor
final class CameraController {
    struct ReceiverEdgeMarker {
        /// Camera-local screen points, with (0, 0) at the display centre.
        let position: CGPoint
        let angle: CGFloat
    }

    private(set) var resolvedScale: CGFloat = 1
    private(set) var receiverEdgeMarker: ReceiverEdgeMarker?
    private var position = CGPoint.zero
    private var isInitialized = false
    private var zoomFactor: CGFloat = 1
    private let projection = 0.86

    /// Insets are screen points measured from the full scene edges, including safe
    /// areas. The portrait view shows at least 44 m across and 56 m of pitch length.
    static func recommendedScale(
        viewport: CGSize,
        topInset: CGFloat = 130,
        bottomInset: CGFloat = 190
    ) -> CGFloat {
        let playHeight = max(180, viewport.height - topInset - bottomInset)
        return max(56 * 0.86 / playHeight, 44 / max(1, viewport.width))
    }

    /// `point` is already projected: world x, world y × 0.86.
    func reset(to point: CGPoint) {
        position = point
        isInitialized = false
        zoomFactor = 1
        receiverEdgeMarker = nil
    }

    /// `scale` is projected pitch metres per scene point (the SKCameraNode scale).
    /// `topInset` and `bottomInset` reserve the actual HUD/control areas in points.
    func update(
        ball: BallState,
        player: PlayerState,
        viewport: CGSize,
        scale: CGFloat,
        tuning: GameplayTuning,
        deltaTime: Double,
        topInset: CGFloat = 130,
        bottomInset: CGFloat = 190,
        framingReceiver: Bool = false
    ) -> CGPoint {
        guard viewport.width > 0, viewport.height > 0, scale > 0 else { return position }
        let groundBall = Vector2(x: ball.position.x, y: ball.position.y * projection)
        let projectedPlayer = Vector2(x: player.position.x, y: player.position.y * projection)
        let height = ball.height.isFinite ? max(0, ball.height) : 0
        let drawnBallRadius = (Pitch.ballRadius + 0.17) * (1 + min(height, 5) * 0.035)
        let extraHeadroom = max(0, height + drawnBallRadius + 0.25 - 2.5)
        let insetBudget = max(0, viewport.height - 100)
        let requestedInsets = max(0, topInset) + max(0, bottomInset)
        let insetRatio = requestedInsets > insetBudget ? insetBudget / max(1, requestedInsets) : 1
        let playHeight = max(1, viewport.height - requestedInsets * insetRatio)
        var requiredZoom: CGFloat = 1
        if framingReceiver {
            let span = projectedPlayer - groundBall
            let fitScale = max((abs(span.x) + 5.2) / viewport.width,
                               (abs(span.y) + 5.2 + extraHeadroom) / playHeight)
            requiredZoom = min(1.20, max(1, fitScale / scale))
        }
        // Widen immediately only when visibility requires it. Once the pass is
        // collected, return gently rather than changing player size in one frame.
        let zoomAlpha = 1 - exp(-3.2 * min(max(0, deltaTime), 0.1))
        zoomFactor = max(requiredZoom, zoomFactor + (requiredZoom - zoomFactor) * zoomAlpha)
        resolvedScale = scale * zoomFactor
        let scale = resolvedScale
        let halfWidth = Double(viewport.width * scale / 2)
        let halfHeight = Double(viewport.height * scale / 2)
        // Keep a further 2.5 m clear inside the usable area. This leaves room for
        // the ball and upright figures at speed, even adjacent to pitch boundaries.
        let left = -max(2, halfWidth - 2.5)
        let right = max(2, halfWidth - 2.5)
        // Ordinary chips fit inside the existing 2.5 m upper margin. Reserve only
        // the extra space a taller ball needs, including its outline and clearance.
        // The lower envelope continues to follow the ground shadow; zoom is stable.
        let bottom = -halfHeight + Double(max(0, bottomInset) * insetRatio * scale) + 2.5
        let top = halfHeight - Double(max(0, topInset) * insetRatio * scale) - 2.5 - extraHeadroom
        let visibleBottom = min(bottom, top - 2)
        let visibleTop = max(top, visibleBottom + 2)
        let playCenterOffset = (visibleBottom + visibleTop) / 2
        let projectedVelocity = Vector2(x: ball.velocity.x, y: ball.velocity.y * projection)
        let pitchEdge = Pitch.width / 2 + 4
        let pitchEnd = (Pitch.length / 2 + Pitch.goalDepth + 4) * projection
        // Clamp the unobscured play area to the pitch and run-off, allowing the
        // outer full viewport to continue behind the HUD and control strip.
        let rawMinimumX = -pitchEdge - left
        let rawMaximumX = pitchEdge - right
        let minimumX = min(0, rawMinimumX)
        let maximumX = max(0, rawMaximumX)
        let rawMinimumY = -pitchEnd - visibleBottom
        let rawMaximumY = pitchEnd - visibleTop
        let minimumY = min(-playCenterOffset, rawMinimumY)
        let maximumY = max(-playCenterOffset, rawMaximumY)
        let lookAhead = projectedVelocity * tuning.cameraLookAhead
        // Keep remote selected-player changes from dragging the camera away from
        // a pass. A nearby receiver gently biases it without overruling the ball.
        let playerBias = framingReceiver ? (projectedPlayer - groundBall) * 0.5
            : (projectedPlayer - groundBall).clampedLength(6) * 0.10
        let actionCenter = groundBall + playerBias
        let lookAheadWeight = framingReceiver ? 0.20 : 1.0
        let target = Vector2(
            x: clamp(actionCenter.x + lookAhead.x * 0.60 * lookAheadWeight, minimumX, maximumX),
            y: clamp(actionCenter.y + lookAhead.y * lookAheadWeight - playCenterOffset, minimumY, maximumY)
        )
        if !isInitialized {
            position = CGPoint(x: target.x, y: target.y)
            isInitialized = true
        }
        let alpha = 1 - exp(-max(0, tuning.cameraSmoothing) * min(max(0, deltaTime), 0.1))
        var next = Vector2(
            x: position.x + (target.x - position.x) * alpha,
            y: position.y + (target.y - position.y) * alpha
        )
        next.x = clamp(next.x, minimumX, maximumX)
        next.y = clamp(next.y, minimumY, maximumY)
        // Ball visibility wins over smoothing, including a frame that crosses a
        // scoring boundary. The restart will reset any resulting slight overscroll.
        next.x = clamp(next.x, groundBall.x - right, groundBall.x - left)
        next.y = clamp(next.y, groundBall.y - visibleTop, groundBall.y - visibleBottom)
        receiverEdgeMarker = nil
        if framingReceiver {
            // Intersect the two visibility envelopes. Only the minimum pan needed
            // to reveal the recipient can override smoothing at the handover.
            let pairLeft = max(groundBall.x, projectedPlayer.x) - right
            let pairRight = min(groundBall.x, projectedPlayer.x) - left
            let pairBottom = max(groundBall.y, projectedPlayer.y) - visibleTop
            let pairTop = min(groundBall.y, projectedPlayer.y) - visibleBottom
            if pairLeft <= pairRight { next.x = clamp(next.x, pairLeft, pairRight) }
            if pairBottom <= pairTop { next.y = clamp(next.y, pairBottom, pairTop) }
            let offset = projectedPlayer - next
            if offset.x < left || offset.x > right || offset.y < visibleBottom || offset.y > visibleTop {
                // Exceptional spans retain ball visibility and point to the actual
                // controlled player instead of zooming the whole pitch to tiny dots.
                let extraMarkerMargin = max(0, 28 * scale - 2.5)
                let marker = Vector2(x: clamp(offset.x, left + extraMarkerMargin, right - extraMarkerMargin),
                                     y: clamp(offset.y, visibleBottom + extraMarkerMargin, visibleTop - extraMarkerMargin))
                receiverEdgeMarker = ReceiverEdgeMarker(
                    position: CGPoint(x: marker.x / scale, y: marker.y / scale),
                    angle: CGFloat(atan2(offset.y - marker.y, offset.x - marker.x)))
            }
        }
        position = CGPoint(x: next.x, y: next.y)
        return position
    }

    private func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}
