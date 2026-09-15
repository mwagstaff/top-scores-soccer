import SpriteKit

/// Original vector artwork. All positions and dimensions use the simulation's metres.
/// The scene projects the ground plane; the figure compensates to remain upright.
@MainActor
final class PitchRenderer {
    let root = SKNode()
    var matchKits: MatchKits? {
        didSet {
            guard matchKits != oldValue else { return }
            for sprite in players.values {
                sprite.root.removeFromParent()
                sprite.shadow.removeFromParent()
            }
            players.removeAll()
        }
    }
    private let artwork = SKNode()
    private let drawingScale: CGFloat = 20

    @MainActor
    private final class PlayerArtwork {
        let root = SKNode()
        let figure = SKNode()
        let leftBoot = SKShapeNode(rectOf: CGSize(width: 0.43, height: 0.48), cornerRadius: 0.12)
        let rightBoot = SKShapeNode(rectOf: CGSize(width: 0.43, height: 0.48), cornerRadius: 0.12)
        let selection = SKShapeNode(circleOfRadius: 1.2)
        let passTarget = SKShapeNode()
        let handover = SKShapeNode(circleOfRadius: 1.32)
        let aim = SKShapeNode()
        let powerTrack = SKShapeNode(rectOf: CGSize(width: 2.8, height: 0.4), cornerRadius: 0.2)
        let powerFill = SKShapeNode()
        let powerBand = SKShapeNode()
        let powerDanger = SKShapeNode()
        let powerMarker = SKShapeNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 1.85, height: 0.88))
        let tackle = SKShapeNode()
        let kickLeg = SKShapeNode()
        let booking = SKShapeNode(rectOf: CGSize(width: 0.36, height: 0.55), cornerRadius: 0.05)
        let keeperGloves = SKNode()
        let keeperBadge = SKNode()
        let arms = SKShapeNode(rectOf: CGSize(width: 1.62, height: 0.4), cornerRadius: 0.16)
        let hair = SKShapeNode(ellipseOf: CGSize(width: 0.72, height: 0.34))
        let poseArms = SKShapeNode()
        let poseArmsOutline = SKShapeNode()
        let poseLegs = SKShapeNode()
        let poseLegsOutline = SKShapeNode()
        let impact = SKShapeNode()
        let team: Team
        let isGoalkeeper: Bool
        var profile: ClubPlayer?
        var gait = 0.0
        init(team: Team, isGoalkeeper: Bool) {
            self.team = team
            self.isGoalkeeper = isGoalkeeper
        }
    }

    private var players: [Int: PlayerArtwork] = [:]
    private let ballNode = SKNode()
    private let ballPanels = SKShapeNode()
    private let ballShadow = SKShapeNode(ellipseOf: CGSize(width: 1.1, height: 0.62))
    private let heightConnector = SKShapeNode()
    private let trajectory = SKShapeNode()
    private let playerVector = SKShapeNode()
    private let curveVector = SKShapeNode()
    private let passVector = SKShapeNode()
    private let trailNode = SKNode()
    private var trailDots: [SKShapeNode] = []
    private var trail: [CGPoint] = []
    private var lastBallPosition: Vector2?
    private var lastBallVisualPosition: Vector2?
    private var roll = 0.0
    private var lastSelectedPlayerID: Int?
    private var handoverRemaining = 0.0

    private let chalk = SKColor(red: 0.91, green: 0.96, blue: 0.88, alpha: 0.88)
    private let cyan = SKColor(red: 0.49, green: 0.88, blue: 1, alpha: 1)
    private let yellow = SKColor(red: 1, green: 0.87, blue: 0.37, alpha: 1)

    init() {
        buildPitch()
        buildBall()
        buildDebug()
        upscaleArtwork(artwork)
        artwork.setScale(1 / drawingScale)
        root.addChild(artwork)
    }

    private static let iconCache = NSCache<NSString, UIImage>()
    private static let iconRenderer = PitchRenderer()
    private static let iconView = SKView(frame: CGRect(x: 0, y: 0, width: 100, height: 120))

    /// Snapshot the same figure builder used on the pitch, without match indicators.
    static func playerIcon(_ player: ClubPlayer, kit: ClubKit) -> UIImage? {
        let key = "\(player.id)|\(player.appearance)|\(player.jerseyNumber ?? 0)|\(player.role)|\(kit)" as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        iconCache.countLimit = 160
        let sprite = iconRenderer.buildPlayer(team: .blue, number: player.jerseyNumber ?? 0,
            isGoalkeeper: player.role == "G", kit: kit, appearance: player.appearance,
            shirtNumber: player.jerseyNumber.map(String.init) ?? "–")
        sprite.root.removeFromParent(); sprite.shadow.removeFromParent()
        sprite.figure.removeFromParent()
        sprite.figure.position = .zero
        sprite.figure.setScale(1)
        sprite.leftBoot.position.x = -5.6; sprite.rightBoot.position.x = 5.6
        let bounds = sprite.figure.calculateAccumulatedFrame().insetBy(dx: -4, dy: -4)
        guard let texture = iconView.texture(from: sprite.figure, crop: bounds) else { return nil }
        let image = UIImage(cgImage: texture.cgImage())
        iconCache.setObject(image, forKey: key)
        return image
    }

    func resetControlFeedback() {
        lastSelectedPlayerID = nil
        handoverRemaining = 0
    }

    /// The solo overload preserves the sandbox presentation contract.
    func render(
        player: PlayerState,
        ball: BallState,
        hasControl: Bool,
        chargeFraction: Double,
        aftertouchRemaining: Double,
        aftertouchVector: Vector2,
        debug: Bool,
        deltaTime: Double
    ) {
        render(footballers: [Footballer(id: 0, team: .blue, state: player, isTackling: false)],
               selectedPlayerID: 0, passTargetID: nil, ball: ball, hasControl: hasControl,
               chargeFraction: chargeFraction, aftertouchRemaining: aftertouchRemaining,
               aftertouchVector: aftertouchVector, debug: debug, deltaTime: deltaTime)
    }

    func render(
        footballers: [Footballer],
        selectedPlayerID: Int,
        passTargetID: Int?,
        ball: BallState,
        hasControl: Bool,
        chargeFraction: Double,
        aftertouchRemaining: Double,
        aftertouchVector: Vector2,
        debug: Bool,
        deltaTime: Double,
        controlledGoalkeeper: Bool = false,
        holdingGoalkeeperID: Int? = nil,
        powerFeedback: KickPowerFeedback? = nil
    ) {
        let dt = min(max(deltaTime, 0), 0.05)
        if let lastSelectedPlayerID, lastSelectedPlayerID != selectedPlayerID, selectedPlayerID >= 0 {
            handoverRemaining = 0.55
        } else {
            handoverRemaining = max(0, handoverRemaining - dt)
        }
        lastSelectedPlayerID = selectedPlayerID
        let liveIDs = Set(footballers.map(\.id))
        var heldBallDrawingPosition: CGPoint?
        for id in Array(players.keys) where !liveIDs.contains(id) {
            players[id]?.root.removeFromParent()
            players[id]?.shadow.removeFromParent()
            players.removeValue(forKey: id)
        }
        for footballer in footballers {
            if let existing = players[footballer.id],
               existing.team != footballer.team || existing.isGoalkeeper != footballer.isGoalkeeper
                || existing.profile != footballer.clubPlayer {
                existing.root.removeFromParent()
                existing.shadow.removeFromParent()
                players.removeValue(forKey: footballer.id)
            }
            let sprite: PlayerArtwork
            if let existing = players[footballer.id] {
                sprite = existing
            } else {
                // Numbering is stable across selection changes; blue and red retain
                // different shorts and trim patterns as well as different colours.
                sprite = buildPlayer(team: footballer.team,
                                     number: footballer.clubPlayer?.jerseyNumber ?? footballer.id + 1,
                                     isGoalkeeper: footballer.isGoalkeeper, runtimeID: footballer.id,
                                     kit: footballer.team == .blue ? matchKits?.home : matchKits?.away,
                                     appearance: footballer.clubPlayer?.appearance,
                                     shirtNumber: footballer.clubPlayer.map { $0.jerseyNumber.map(String.init) ?? "–" })
                sprite.profile = footballer.clubPlayer
                players[footballer.id] = sprite
            }
            // Dismissal takes effect in play immediately, but a committed slide
            // remains visible until its foul aftermath and get-up have finished.
            let dismissed = footballer.isUnavailable && !footballer.isSliding
            sprite.root.isHidden = dismissed
            sprite.shadow.isHidden = dismissed
            if dismissed { continue }
            sprite.booking.isHidden = footballer.yellowCards == 0
            sprite.keeperGloves.isHidden = !footballer.isGoalkeeper
            sprite.keeperBadge.isHidden = !footballer.isGoalkeeper
            let player = footballer.state
            let selected = footballer.id == selectedPlayerID && (!footballer.isGoalkeeper || controlledGoalkeeper)
            let target = footballer.id == passTargetID && !selected
            sprite.root.position = point(player.position)
            sprite.shadow.position = point(player.position + Vector2(x: 0.22, y: -0.05))
            sprite.shadow.zRotation = 0
            sprite.shadow.setScale(1)
            sprite.root.zPosition = 20 - CGFloat(player.position.y) * 0.01
            // A cached player can return from a fall or slide on any restart.
            // Reset the extra pose transforms before applying this frame's state.
            sprite.leftBoot.zRotation = 0
            sprite.rightBoot.zRotation = 0
            for (glove, x) in zip(sprite.keeperGloves.children, [-0.85, 0.85]) {
                glove.position = point(Vector2(x: x, y: 0.86))
            }
            sprite.arms.zRotation = 0
            sprite.arms.setScale(1)
            sprite.arms.isHidden = false
            sprite.poseArms.isHidden = true
            sprite.poseArmsOutline.isHidden = true
            sprite.poseLegs.isHidden = true
            sprite.poseLegsOutline.isHidden = true
            sprite.impact.isHidden = true
            sprite.hair.position = point(Vector2(x: 0, y: 1.84))
            sprite.hair.setScale(1)
            sprite.gait += player.velocity.length * dt * 2.4
            let stride = min(player.velocity.length / 7, 1) * 0.2
            let facing = player.facing.length > 0.001 ? player.facing.normalized : .up
            let direction = player.velocity.length > 0.2 ? player.velocity.normalized : facing
            let fall = footballer.fallProgress.isFinite ? min(1, max(0, footballer.fallProgress)) : 0
            let recovery = footballer.recoveryProgress.isFinite ? min(1, max(0, footballer.recoveryProgress)) : 0
            let dive = footballer.isGoalkeeper && footballer.goalkeeperDiveProgress.isFinite
                ? min(1, max(0, footballer.goalkeeperDiveProgress)) : 0
            if fall > 0 {
                let supplied = footballer.fallDirection
                let fallDirection = supplied.x.isFinite && supplied.y.isFinite && supplied.length > 0.001
                    ? supplied.normalized : facing
                applyFall(to: sprite, progress: fall, direction: fallDirection)
                if recovery > 0 { applyRecovery(to: sprite, progress: recovery) }
            } else if dive > 0 {
                applyKeeperDive(to: sprite, extent: dive, facing: facing)
            } else if footballer.isSliding {
                // Feet lead along the ground travel direction; the body trails
                // behind the unchanged physical/contact origin during the slide.
                let pace = min(1, player.velocity.length / 16)
                sprite.figure.position = point(direction * (0.12 + (1 - pace) * 0.14))
                let slideAngle = atan2(direction.y, direction.x) + .pi / 2
                sprite.figure.zRotation = CGFloat(atan2(sin(slideAngle), cos(slideAngle)))
                sprite.figure.xScale = 0.94
                sprite.figure.yScale = CGFloat(0.95 + pace * 0.17)
                let leftFoot = Vector2(x: -0.4, y: -0.2 * pace)
                let rightFoot = Vector2(x: 0.31, y: -0.28 - pace * 0.32)
                sprite.leftBoot.position = point(leftFoot)
                sprite.rightBoot.position = point(rightFoot)
                sprite.kickLeg.isHidden = true
                drawGroundLimbs(to: sprite, leftFoot: leftFoot, rightFoot: rightFoot,
                                leftHand: Vector2(x: -0.92, y: 0.52),
                                rightHand: Vector2(x: 0.92, y: 0.62), kneeBend: (1 - pace) * 0.25)
                groundShadow(sprite, direction: direction, amount: 1)
                if recovery > 0 { applyRecovery(to: sprite, progress: recovery, fromSlide: true) }
            } else {
                sprite.figure.position = point(Vector2(x: 0, y: -1.15 + abs(sin(sprite.gait)) * stride * 0.2))
                sprite.figure.zRotation = footballer.isTackling ? CGFloat(-facing.x * 0.15) : 0
                sprite.figure.xScale = 1
                sprite.figure.yScale = 1 / 0.86
                sprite.leftBoot.position = point(Vector2(x: -0.31, y: sin(sprite.gait) * stride))
                var rightFoot = Vector2(x: 0.31, y: -sin(sprite.gait) * stride)
                if footballer.isTackling {
                    rightFoot += Vector2(x: facing.x * 0.7, y: facing.y * 0.7 * 0.86)
                    sprite.kickLeg.path = line(from: Vector2(x: 0.31, y: 0.3), to: rightFoot)
                }
                sprite.rightBoot.position = point(rightFoot)
                sprite.kickLeg.isHidden = !footballer.isTackling
                if footballer.isGoalkeeper, let release = footballer.goalkeeperReleaseKind,
                   footballer.goalkeeperReleaseProgress.isFinite, footballer.goalkeeperReleaseProgress > 0 {
                    let supplied = footballer.goalkeeperReleaseDirection
                    let releaseDirection = supplied.x.isFinite && supplied.y.isFinite && supplied.length > 0.001
                        ? supplied.normalized : facing
                    applyKeeperRelease(to: sprite, kind: release,
                                       progress: footballer.goalkeeperReleaseProgress, direction: releaseDirection)
                } else if footballer.headingProgress.isFinite, footballer.headingProgress > 0 {
                    applyHeader(to: sprite, progress: footballer.headingProgress, facing: facing)
                }
            }
            if footballer.isGoalkeeper, footballer.id == holdingGoalkeeperID, fall == 0 {
                // Keep the held ball between the gloves throughout a diving
                // catch and recovery. This is presentation only, never a pickup.
                let extent = smooth(dive)
                let handY = 1.03 + extent * 1.26
                let handX = 0.50 - extent * 0.20
                drawGroundLimbs(to: sprite,
                                leftFoot: Vector2(x: sprite.leftBoot.position.x / drawingScale,
                                                  y: sprite.leftBoot.position.y / drawingScale),
                                rightFoot: Vector2(x: sprite.rightBoot.position.x / drawingScale,
                                                   y: sprite.rightBoot.position.y / drawingScale),
                                leftHand: Vector2(x: -handX, y: handY),
                                rightHand: Vector2(x: handX, y: handY), kneeBend: extent * 0.3)
                heldBallDrawingPosition = sprite.figure.convert(point(Vector2(x: 0, y: handY)), to: artwork)
            }
            sprite.selection.isHidden = !selected
            sprite.passTarget.isHidden = !target
            sprite.handover.isHidden = !selected || handoverRemaining <= 0
            let pulse = CGFloat(handoverRemaining / 0.55)
            sprite.handover.alpha = pulse * 0.85
            sprite.handover.setScale(handoverRemaining > 0 ? 1 + (1 - pulse) * 0.72 : 1)
            sprite.aim.isHidden = !selected || fall > 0
            sprite.aim.zRotation = CGFloat(atan2(player.facing.y, player.facing.x) - .pi / 2)
            sprite.aim.alpha = hasControl ? 0.88 : 0.5
            sprite.tackle.isHidden = !footballer.isTackling || footballer.isSliding || fall > 0
            sprite.tackle.zRotation = CGFloat(atan2(player.facing.y, player.facing.x) - .pi / 2)
            let charge = selected && fall == 0 ? CGFloat(min(max(chargeFraction, 0), 1)) : 0
            let showPower = selected && fall == 0 && (powerFeedback != nil || charge > 0)
            sprite.powerTrack.isHidden = !showPower
            sprite.powerFill.isHidden = !showPower
            sprite.powerMarker.isHidden = !showPower
            sprite.powerBand.isHidden = !showPower || powerFeedback?.sweetSpot == nil
            sprite.powerDanger.isHidden = !showPower || powerFeedback?.overhitStart == nil
            if showPower {
                sprite.powerFill.path = drawingPath(CGPath(roundedRect: CGRect(x: -1.25, y: -1.92, width: max(0.03, 2.5 * charge), height: 0.2), cornerWidth: 0.1, cornerHeight: 0.1, transform: nil))
                sprite.powerFill.fillColor = powerFeedback?.tint ?? yellow
                sprite.powerMarker.path = drawingPath(CGPath(rect: CGRect(x: -1.25 + 2.5 * charge - 0.035,
                    y: -2.1, width: 0.07, height: 0.56), transform: nil))
                if let band = powerFeedback?.sweetSpot {
                    sprite.powerBand.path = drawingPath(CGPath(rect: CGRect(x: -1.25 + 2.5 * band.lowerBound,
                        y: -2.02, width: 2.5 * (band.upperBound - band.lowerBound), height: 0.4), transform: nil))
                }
                if let danger = powerFeedback?.overhitStart {
                    sprite.powerDanger.path = drawingPath(CGPath(rect: CGRect(x: -1.25 + 2.5 * danger,
                        y: -1.98, width: 2.5 * (1 - danger), height: 0.32), transform: nil))
                }
            }
        }
        let height = ball.height.isFinite ? max(0, ball.height) : 0
        // Ground positions remain in simulation metres. Dividing by projection
        // makes one metre of ball height rise one projected metre on the display.
        let visualBall = heldBallDrawingPosition.map { Vector2(x: $0.x / drawingScale, y: $0.y / drawingScale) }
            ?? ball.position + Vector2(x: 0, y: height / 0.86)
        ballNode.position = point(visualBall)
        ballNode.setScale(heldBallDrawingPosition != nil ? 0.9 : CGFloat(1 + min(height, 5) * 0.035))
        ballShadow.isHidden = heldBallDrawingPosition != nil
        ballShadow.position = point(ball.position + Vector2(x: 0.14, y: -0.13))
        ballShadow.setScale(CGFloat(1 + min(height, 5) * 0.07))
        ballShadow.alpha = CGFloat(1 - min(height, 5) * 0.08)
        // Airborne balls clear players and posts visually; the simulation owns
        // whether an actual contact or an over-the-bar miss occurs.
        ballNode.zPosition = height > 0.12 || heldBallDrawingPosition != nil ? 26 : 23
        heightConnector.isHidden = height < 0.55 || heldBallDrawingPosition != nil
        if height >= 0.55 {
            heightConnector.path = dottedHeightLine(from: ball.position, to: visualBall)
        }

        let distance = lastBallPosition.map { (ball.position - $0).length } ?? 0
        let visualDistance = lastBallVisualPosition.map { (visualBall - $0).length } ?? 0
        if heldBallDrawingPosition != nil || distance > 5 || (ball.velocity.length < 0.1 && height < 0.1 && aftertouchRemaining <= 0) {
            trail.removeAll(keepingCapacity: true)
        } else if visualDistance > 0.02 {
            if let previous = lastBallVisualPosition { trail.insert(point(previous), at: 0) }
            if trail.count > trailDots.count { trail.removeLast(trail.count - trailDots.count) }
        }
        lastBallPosition = ball.position
        lastBallVisualPosition = visualBall
        roll += min(visualDistance, 5) * 1.2
        ballPanels.zRotation = CGFloat(roll)
        let trailVisible = heldBallDrawingPosition == nil &&
            (ball.velocity.length > 15 || (height > 0.3 && abs(ball.verticalVelocity) > 1))
        trailNode.zPosition = height > 0.12 ? 25 : 7
        for (index, dot) in trailDots.enumerated() {
            dot.isHidden = !trailVisible || index >= trail.count
            if index < trail.count {
                dot.position = trail[index]
                dot.fillColor = aftertouchRemaining > 0 ? cyan : .white
                dot.alpha = CGFloat(1 - Double(index) / Double(trailDots.count)) * (aftertouchRemaining > 0 ? 0.25 : 0.14)
                dot.setScale(CGFloat(1 - Double(index) * 0.065))
            }
        }

        trajectory.isHidden = !debug
        playerVector.isHidden = !debug
        curveVector.isHidden = !debug || aftertouchRemaining <= 0
        passVector.isHidden = !debug || passTargetID == nil
        if debug {
            trajectory.path = line(from: ball.position, to: ball.position + ball.velocity * 0.45)
            if let player = footballers.first(where: { $0.id == selectedPlayerID && !$0.isUnavailable })?.state {
                playerVector.path = line(from: player.position, to: player.position + player.velocity * 0.6)
                if let target = footballers.first(where: { $0.id == passTargetID && !$0.isUnavailable })?.state {
                    passVector.path = line(from: player.position, to: target.position)
                } else {
                    passVector.path = nil
                }
            } else {
                playerVector.path = nil
                passVector.path = nil
            }
            curveVector.path = line(from: ball.position, to: ball.position + aftertouchVector * 6)
        }
    }

    /// Contact owns the animation clock. Preparing or missing a header leaves
    /// the player on the grass, and the physical marker never follows the hop.
    private func applyHeader(to sprite: PlayerArtwork, progress: Double, facing: Vector2) {
        let progress = min(1, max(0, progress))
        guard progress > 0, progress < 1 else { return }
        let lift = progress < 0.35 ? smooth(progress / 0.35) : 1 - smooth((progress - 0.35) / 0.65)
        sprite.figure.position = point(Vector2(x: facing.x * 0.22 * lift, y: -1.15 + lift * 1.25))
        sprite.figure.zRotation = CGFloat(-facing.x * 0.16 * lift)
        sprite.figure.xScale = CGFloat(1 + lift * 0.04)
        sprite.figure.yScale = CGFloat((1 - lift * 0.04) / 0.86)
        let leftFoot = Vector2(x: -0.31 - 0.08 * lift, y: 0.32 * lift)
        let rightFoot = Vector2(x: 0.31 + 0.05 * lift, y: 0.48 * lift)
        sprite.leftBoot.position = point(leftFoot)
        sprite.rightBoot.position = point(rightFoot)
        sprite.leftBoot.zRotation = CGFloat(-0.2 * lift)
        sprite.rightBoot.zRotation = CGFloat(0.18 * lift)
        sprite.kickLeg.isHidden = true
        drawGroundLimbs(to: sprite, leftFoot: leftFoot, rightFoot: rightFoot,
                        leftHand: Vector2(x: -0.94, y: 0.74 + 0.34 * lift),
                        rightHand: Vector2(x: 0.94, y: 0.82 + 0.40 * lift), kneeBend: 0.2 * lift)
        sprite.shadow.setScale(CGFloat(1 - lift * 0.16))
        sprite.root.zPosition += CGFloat(lift * 2)
    }

    /// The ball and receiver are already free to move. This short follow-through
    /// belongs to the original keeper and never holds selection or the ball.
    private func applyKeeperRelease(to sprite: PlayerArtwork, kind: GoalkeeperReleaseKind,
                                    progress: Double, direction: Vector2) {
        let progress = min(1, max(0, progress))
        guard progress > 0, progress < 1 else { return }
        let amount = 1 - smooth(progress)
        let sweep = smooth(progress / 0.55)
        let side = direction.x < -0.25 ? -1.0 : 1.0
        sprite.figure.position = point(Vector2(x: direction.x * 0.20 * amount,
                                               y: -1.15 + direction.y * 0.08 * amount))
        sprite.figure.zRotation = CGFloat((-direction.x * 0.18 - side * 0.06) * amount)
        var leftFoot = Vector2(x: -0.31, y: -direction.y * 0.10 * amount)
        var rightFoot = Vector2(x: 0.31, y: direction.y * 0.16 * amount)
        var leftHand = Vector2(x: -0.85, y: 0.86)
        var rightHand = Vector2(x: 0.85, y: 0.86)
        switch kind {
        case .underarmThrow:
            let hand = Vector2(x: side * 0.70 + direction.x * 0.72,
                               y: 0.20 + direction.y * 0.28 + sweep * 0.22)
            if side < 0 { leftHand = leftHand * (1 - amount) + hand * amount }
            else { rightHand = rightHand * (1 - amount) + hand * amount }
        case .overarmThrow:
            let hand = Vector2(x: side * (0.45 + sweep * 0.24) + direction.x * 0.72,
                               y: 2.18 - sweep * 0.90 + direction.y * 0.10)
            if side < 0 { leftHand = leftHand * (1 - amount) + hand * amount }
            else { rightHand = rightHand * (1 - amount) + hand * amount }
            let balance = Vector2(x: -side * 1.05, y: 0.98)
            if side < 0 { rightHand = rightHand * (1 - amount) + balance * amount }
            else { leftHand = leftHand * (1 - amount) + balance * amount }
        case .goalKick:
            rightFoot += Vector2(x: direction.x * 0.95, y: direction.y * 0.80) * amount
            leftFoot.x -= 0.12 * amount
            sprite.rightBoot.zRotation = CGFloat(-direction.x * 0.6 * amount)
            leftHand += Vector2(x: -0.20, y: 0.24) * amount
            rightHand += Vector2(x: 0.18, y: 0.18) * amount
        }
        sprite.leftBoot.position = point(leftFoot)
        sprite.rightBoot.position = point(rightFoot)
        sprite.kickLeg.isHidden = true
        drawGroundLimbs(to: sprite, leftFoot: leftFoot, rightFoot: rightFoot,
                        leftHand: leftHand, rightHand: rightHand, kneeBend: amount * 0.12)
    }

    private func applyKeeperDive(to sprite: PlayerArtwork, extent: Double, facing: Vector2) {
        // The simulation supplies both pose extent and the committed save facing.
        // Recovery reduces the same extent to zero; rendering owns no save timer.
        let amount = smooth(extent)
        let side = facing.x < 0 ? -1.0 : 1.0
        let direction = Vector2(x: side, y: 0)
        sprite.figure.position = point(Vector2(x: -side * amount * 0.55, y: -1.15 * (1 - amount)))
        sprite.figure.zRotation = CGFloat(-side * .pi / 2 * amount)
        sprite.figure.xScale = CGFloat(1 - amount * 0.05)
        sprite.figure.yScale = CGFloat((1 - amount) / 0.86 + amount * 0.95)
        let leftFoot = Vector2(x: -0.31 - amount * 0.16, y: -amount * 0.18)
        let rightFoot = Vector2(x: 0.31 + amount * 0.1, y: amount * 0.16)
        sprite.leftBoot.position = point(leftFoot)
        sprite.rightBoot.position = point(rightFoot)
        sprite.leftBoot.zRotation = CGFloat(-amount * 0.25)
        sprite.rightBoot.zRotation = CGFloat(amount * 0.3)
        drawGroundLimbs(to: sprite, leftFoot: leftFoot, rightFoot: rightFoot,
                        leftHand: Vector2(x: -0.85, y: 0.86) * (1 - amount) + Vector2(x: -0.3, y: 2.26) * amount,
                        rightHand: Vector2(x: 0.85, y: 0.86) * (1 - amount) + Vector2(x: 0.28, y: 2.32) * amount,
                        kneeBend: amount * 0.3)
        sprite.kickLeg.isHidden = true
        setHairGrounding(sprite, amount: amount * 0.6)
        groundShadow(sprite, direction: direction, amount: amount)
    }

    private func applyFall(to sprite: PlayerArtwork, progress: Double, direction: Vector2) {
        // Get to ground early, then spend the remaining contact beat recoiling
        // and rolling to a stop. The simulation holds this final pose at 1.
        let tip = smooth((progress - 0.10) / 0.25)
        let impactTime = min(1, max(0, (progress - 0.28) / 0.20))
        let impact = sin(impactTime * .pi)
        let rollTime = min(1, max(0, (progress - 0.38) / 0.58))
        let recoil = sin(rollTime * .pi * 2) * (1 - rollTime) * 0.62
        let side = direction.x < -0.01 ? -1.0 : 1.0
        let rawAngle = atan2(direction.y, direction.x) - .pi / 2
        let angle = atan2(sin(rawAngle), cos(rawAngle))
        let uprightBase = Vector2(x: 0, y: -1.15)
        let proneBase = -direction * 0.65
        let lurch = direction * (sin(progress * .pi) * 0.22)
            + direction.perpendicular * (recoil * 0.28)
        sprite.figure.position = point(uprightBase * (1 - tip) + proneBase * tip + lurch)
        sprite.figure.zRotation = CGFloat(angle * tip + side * (sin(tip * .pi) * 0.28 + recoil))
        sprite.figure.xScale = CGFloat(1 + tip * 0.12 - impact * 0.10)
        sprite.figure.yScale = CGFloat((1 - tip) / 0.86 + tip * 0.84 - impact * 0.10 + abs(recoil) * 0.22)
        let stagger = sin(progress * .pi * 5) * (1 - tip) * 0.24
        let kneeBend = sin(rollTime * .pi) * (1 - rollTime)
        let leftFoot = Vector2(x: -0.31 - tip * 0.28, y: stagger - tip * 0.1 + recoil * 0.3)
        let rightFoot = Vector2(x: 0.31 + tip * 0.28, y: -stagger - tip * 0.3 + kneeBend * 0.5)
        sprite.leftBoot.position = point(leftFoot)
        sprite.rightBoot.position = point(rightFoot)
        sprite.leftBoot.zRotation = CGFloat(tip * 0.5 + recoil)
        sprite.rightBoot.zRotation = CGFloat(-tip * 0.5 - recoil * 0.5)
        drawGroundLimbs(to: sprite, leftFoot: leftFoot, rightFoot: rightFoot,
                        leftHand: Vector2(x: -0.78 - tip * 0.17, y: 0.86 + tip * 0.24 + impact * 0.25),
                        rightHand: Vector2(x: 0.78 + tip * 0.14, y: 0.86 + tip * 0.19 - recoil * 0.3),
                        kneeBend: kneeBend)
        setHairGrounding(sprite, amount: tip * (1 - abs(recoil) * 0.45))
        sprite.kickLeg.isHidden = true
        groundShadow(sprite, direction: direction, amount: tip)
        sprite.impact.isHidden = progress < 0.29 || progress > 0.70
        if !sprite.impact.isHidden {
            let center = direction * 0.8
            let sideVector = direction.perpendicular
            let path = CGMutablePath()
            for sign in [-1.0, 1.0] {
                for distance in [0.8, 1.15] {
                    let start = center + sideVector * (sign * distance)
                    path.move(to: point(start))
                    path.addLine(to: point(start + sideVector * (sign * 0.22) - direction * 0.1))
                }
            }
            sprite.impact.path = path
        }
    }

    private func applyRecovery(to sprite: PlayerArtwork, progress: Double, fromSlide: Bool = false) {
        // Hands plant before the torso rises. One knee folds underneath, then
        // the other foot takes weight as the player returns to standing.
        let rise = smooth((progress - 0.14) / 0.86)
        let turn = smooth((progress - 0.20) / 0.68)
        let plant = progress >= 1 ? 0 : sin(smooth(progress) * .pi)
        let kneeBend = progress >= 1 ? 0 : sin(smooth((progress - 0.12) / 0.88) * .pi)
        let base = sprite.figure.position
        let upright = point(Vector2(x: 0, y: -1.15))
        sprite.figure.position = CGPoint(x: base.x * (1 - rise) + upright.x * rise,
                                         y: base.y * (1 - rise) + upright.y * rise)
        sprite.figure.zRotation *= CGFloat(1 - turn)
        sprite.figure.xScale = sprite.figure.xScale * CGFloat(1 - rise) + CGFloat(rise)
        sprite.figure.yScale = (sprite.figure.yScale * CGFloat(1 - rise) + CGFloat(rise / 0.86))
            * CGFloat(1 - kneeBend * 0.22)
        let leftStart = Vector2(x: sprite.leftBoot.position.x / drawingScale,
                                y: sprite.leftBoot.position.y / drawingScale)
        let rightStart = Vector2(x: sprite.rightBoot.position.x / drawingScale,
                                 y: sprite.rightBoot.position.y / drawingScale)
        let leftFoot = leftStart * (1 - rise) + Vector2(x: -0.31, y: 0) * rise
            + Vector2(x: kneeBend * 0.16, y: kneeBend * 0.60)
        let rightFoot = rightStart * (1 - rise) + Vector2(x: 0.31, y: 0) * rise
            + Vector2(x: kneeBend * 0.12, y: -kneeBend * 0.12)
        sprite.leftBoot.position = point(leftFoot)
        sprite.rightBoot.position = point(rightFoot)
        sprite.leftBoot.zRotation = sprite.leftBoot.zRotation * CGFloat(1 - rise) - CGFloat(kneeBend * 0.9)
        sprite.rightBoot.zRotation = sprite.rightBoot.zRotation * CGFloat(1 - rise) + CGFloat(kneeBend * 0.25)
        let leftHandStart = fromSlide ? Vector2(x: -0.92, y: 0.52) : Vector2(x: -0.95, y: 1.10)
        let rightHandStart = fromSlide ? Vector2(x: 0.92, y: 0.62) : Vector2(x: 0.92, y: 1.05)
        drawGroundLimbs(to: sprite, leftFoot: leftFoot, rightFoot: rightFoot,
                        leftHand: leftHandStart * (1 - rise) + Vector2(x: -0.78, y: 0.86) * rise
                            + Vector2(x: 0, y: -plant * (fromSlide ? 0.55 : 1.02)),
                        rightHand: rightHandStart * (1 - rise) + Vector2(x: 0.78, y: 0.86) * rise
                            + Vector2(x: -plant * 0.12, y: -plant * (fromSlide ? 0.40 : 0.70)),
                        kneeBend: kneeBend)
        setHairGrounding(sprite, amount: fromSlide ? 0 : 1 - rise)
        let standingShadow = CGPoint(x: sprite.root.position.x + 0.22 * drawingScale,
                                     y: sprite.root.position.y - 0.05 * drawingScale)
        sprite.shadow.position = CGPoint(x: sprite.shadow.position.x * (1 - rise) + standingShadow.x * rise,
                                         y: sprite.shadow.position.y * (1 - rise) + standingShadow.y * rise)
        sprite.shadow.zRotation *= CGFloat(1 - rise)
        sprite.shadow.xScale = sprite.shadow.xScale * CGFloat(1 - rise) + CGFloat(rise)
        sprite.shadow.yScale = sprite.shadow.yScale * CGFloat(1 - rise) + CGFloat(rise)
        sprite.root.zPosition += CGFloat(5 * rise)
        sprite.impact.isHidden = true
        if progress >= 1 {
            // Preserve an exact upright endpoint, including hidden helper limbs.
            sprite.arms.isHidden = false
            sprite.poseArms.isHidden = true
            sprite.poseArmsOutline.isHidden = true
            sprite.poseLegs.isHidden = true
            sprite.poseLegsOutline.isHidden = true
            sprite.leftBoot.zRotation = 0
            sprite.rightBoot.zRotation = 0
            for (glove, x) in zip(sprite.keeperGloves.children, [-0.85, 0.85]) {
                glove.position = point(Vector2(x: x, y: 0.86))
            }
        }
    }

    private func groundShadow(_ sprite: PlayerArtwork, direction: Vector2, amount: Double) {
        sprite.shadow.position.x += CGFloat(direction.x * amount * 0.16) * drawingScale
        sprite.shadow.position.y += CGFloat(direction.y * amount * 0.16) * drawingScale
        sprite.shadow.zRotation = CGFloat(atan2(direction.y, direction.x) * amount)
        sprite.shadow.xScale = CGFloat(1 + amount * 0.6)
        sprite.shadow.yScale = CGFloat(1 + amount * 0.15)
        sprite.root.zPosition -= CGFloat(amount * 5)
    }

    private func setHairGrounding(_ sprite: PlayerArtwork, amount: Double) {
        sprite.hair.position = point(Vector2(x: 0, y: 1.84 - amount * 0.19))
        sprite.hair.xScale = CGFloat(1 + amount * 0.06)
        sprite.hair.yScale = CGFloat(1 + amount * 1.1)
    }

    private func drawGroundLimbs(to sprite: PlayerArtwork, leftFoot: Vector2, rightFoot: Vector2,
                                 leftHand: Vector2, rightHand: Vector2, kneeBend: Double) {
        sprite.arms.isHidden = true
        let armPath = CGMutablePath()
        for (side, hand) in [(-1.0, leftHand), (1.0, rightHand)] {
            armPath.move(to: point(Vector2(x: side * 0.46, y: 1.02)))
            armPath.addLine(to: point(Vector2(x: side * 0.71, y: (hand.y + 1.02) * 0.5)))
            armPath.addLine(to: point(hand))
        }
        let legPath = CGMutablePath()
        for (side, foot) in [(-1.0, leftFoot), (1.0, rightFoot)] {
            legPath.move(to: point(Vector2(x: side * 0.28, y: 0.40)))
            legPath.addLine(to: point(Vector2(x: side * (0.40 + kneeBend * 0.18),
                                             y: 0.05 - (side < 0 ? kneeBend * 0.16 : 0))))
            legPath.addLine(to: point(foot))
        }
        for node in [sprite.poseArms, sprite.poseArmsOutline] { node.path = armPath; node.isHidden = false }
        for node in [sprite.poseLegs, sprite.poseLegsOutline] { node.path = legPath; node.isHidden = false }
        if sprite.isGoalkeeper {
            for (glove, hand) in zip(sprite.keeperGloves.children, [leftHand, rightHand]) {
                glove.position = point(hand)
            }
        }
    }

    private func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func buildPitch() {
        root.name = "pitch"
        let verge = SKSpriteNode(color: SKColor(red: 0.075, green: 0.20, blue: 0.15, alpha: 1), size: CGSize(width: 300, height: 300))
        verge.zPosition = -20
        artwork.addChild(verge)

        let runOff = SKShapeNode(rectOf: CGSize(width: Pitch.width + 9, height: Pitch.length + 12), cornerRadius: 1.6)
        runOff.fillColor = SKColor(red: 0.10, green: 0.31, blue: 0.21, alpha: 1)
        runOff.strokeColor = SKColor(red: 0.22, green: 0.40, blue: 0.29, alpha: 0.7)
        runOff.lineWidth = 0.18
        runOff.zPosition = -10
        artwork.addChild(runOff)

        let stripeHeight = Pitch.length / 14
        for index in 0..<14 {
            let color = index.isMultiple(of: 2)
                ? SKColor(red: 0.16, green: 0.45, blue: 0.29, alpha: 1)
                : SKColor(red: 0.18, green: 0.48, blue: 0.31, alpha: 1)
            let stripe = SKSpriteNode(color: color, size: CGSize(width: Pitch.width, height: stripeHeight + 0.01))
            stripe.position.y = -Pitch.length / 2 + stripeHeight * (Double(index) + 0.5)
            stripe.zPosition = -5
            artwork.addChild(stripe)
        }

        let markings = CGMutablePath()
        markings.addRect(CGRect(x: -Pitch.width / 2, y: -Pitch.length / 2, width: Pitch.width, height: Pitch.length))
        markings.move(to: CGPoint(x: -Pitch.width / 2, y: 0))
        markings.addLine(to: CGPoint(x: Pitch.width / 2, y: 0))
        markings.addEllipse(in: CGRect(x: -9.15, y: -9.15, width: 18.3, height: 18.3))
        for sign in [-1.0, 1.0] {
            let end = sign * Pitch.length / 2
            let boxY = sign > 0 ? end - 16.5 : end
            let smallBoxY = sign > 0 ? end - 5.5 : end
            markings.addRect(CGRect(x: -20.16, y: boxY, width: 40.32, height: 16.5))
            markings.addRect(CGRect(x: -9.16, y: smallBoxY, width: 18.32, height: 5.5))
            let penalty = CGPoint(x: 0, y: end - sign * 11)
            let theta = asin(5.5 / 9.15)
            if sign > 0 {
                markings.move(to: CGPoint(x: cos(.pi + theta) * 9.15, y: penalty.y + sin(.pi + theta) * 9.15))
                markings.addArc(center: penalty, radius: 9.15, startAngle: .pi + theta, endAngle: 2 * .pi - theta, clockwise: false)
            } else {
                markings.move(to: CGPoint(x: cos(theta) * 9.15, y: penalty.y + sin(theta) * 9.15))
                markings.addArc(center: penalty, radius: 9.15, startAngle: theta, endAngle: .pi - theta, clockwise: false)
            }
            let spot = SKShapeNode(circleOfRadius: 0.18)
            spot.position = penalty
            spot.fillColor = chalk
            spot.strokeColor = .clear
            artwork.addChild(spot)
            buildGoal(north: sign > 0)
        }
        // Independent subpaths prevent arcs being joined to the preceding box.
        let lineNode = SKShapeNode(path: markings)
        lineNode.lineWidth = 0.13
        lineNode.strokeColor = chalk
        lineNode.fillColor = .clear
        lineNode.zPosition = 0
        artwork.addChild(lineNode)

        let centerSpot = SKShapeNode(circleOfRadius: 0.2)
        centerSpot.fillColor = chalk
        centerSpot.strokeColor = .clear
        artwork.addChild(centerSpot)
        for xSign in [-1.0, 1.0] {
            for ySign in [-1.0, 1.0] {
                let arc = CGMutablePath()
                let corner = CGPoint(x: xSign * Pitch.width / 2, y: ySign * Pitch.length / 2)
                let start: Double = xSign < 0 ? (ySign < 0 ? 0 : -.pi / 2) : (ySign < 0 ? .pi / 2 : .pi)
                arc.addArc(center: corner, radius: 1, startAngle: start, endAngle: start + .pi / 2, clockwise: false)
                let node = SKShapeNode(path: arc)
                node.strokeColor = chalk
                node.lineWidth = 0.13
                artwork.addChild(node)
            }
        }
    }

    private func buildGoal(north: Bool) {
        let sign: Double = north ? 1 : -1
        let end = sign * Pitch.length / 2
        let back = end + sign * Pitch.goalDepth
        let net = CGMutablePath()
        let half = Pitch.goalWidth / 2
        for x in stride(from: -half, through: half, by: 0.75) {
            net.move(to: CGPoint(x: x, y: end))
            net.addLine(to: CGPoint(x: x, y: back))
        }
        for depth in stride(from: 0.0, through: Pitch.goalDepth, by: 0.6) {
            net.move(to: CGPoint(x: -half, y: end + sign * depth))
            net.addLine(to: CGPoint(x: half, y: end + sign * depth))
        }
        let bed = SKShapeNode(rect: CGRect(x: -half, y: min(end, back), width: Pitch.goalWidth, height: Pitch.goalDepth))
        bed.fillColor = SKColor(red: 0.04, green: 0.16, blue: 0.14, alpha: 0.85)
        bed.strokeColor = .clear
        bed.zPosition = 0.5
        artwork.addChild(bed)
        let mesh = SKShapeNode(path: net)
        mesh.strokeColor = chalk.withAlphaComponent(0.24)
        mesh.lineWidth = 0.06
        mesh.zPosition = 1
        artwork.addChild(mesh)
        let frame = CGMutablePath()
        frame.move(to: CGPoint(x: -half, y: end))
        frame.addLine(to: CGPoint(x: -half, y: back))
        frame.addLine(to: CGPoint(x: half, y: back))
        frame.addLine(to: CGPoint(x: half, y: end))
        let frameNode = SKShapeNode(path: frame)
        frameNode.strokeColor = chalk.withAlphaComponent(0.8)
        frameNode.lineWidth = 0.2
        frameNode.lineJoin = .round
        frameNode.zPosition = 3
        artwork.addChild(frameNode)
        for x in [-half, half] {
            let post = SKShapeNode(circleOfRadius: Pitch.postRadius)
            post.fillColor = .white
            post.strokeColor = SKColor(white: 0.2, alpha: 0.7)
            post.lineWidth = 0.07
            post.position = CGPoint(x: x, y: end)
            post.zPosition = 24
            artwork.addChild(post)
        }
    }

    private func buildPlayer(team: Team, number: Int, isGoalkeeper: Bool,
                             runtimeID: Int? = nil, kit: ClubKit? = nil,
                             appearance: PlayerAppearance? = nil, shirtNumber: String? = nil) -> PlayerArtwork {
        let sprite = PlayerArtwork(team: team, isGoalkeeper: isGoalkeeper)
        let playerNode = sprite.root
        let figure = sprite.figure
        let leftBoot = sprite.leftBoot
        let rightBoot = sprite.rightBoot
        let playerShadow = sprite.shadow
        let selection = sprite.selection
        let aim = sprite.aim
        let powerTrack = sprite.powerTrack
        let powerFill = sprite.powerFill
        let isBlue = team == .blue
        let keeperColor = kit.map { SKColor(clubHex: $0.goalkeeperHex) } ?? (isBlue
            ? SKColor(red: 1, green: 0.70, blue: 0.18, alpha: 1)
            : SKColor(red: 0.67, green: 0.39, blue: 0.92, alpha: 1))
        let skinColor = appearance.map { SKColor(clubHex: $0.skinHex) }
        playerNode.name = "player-\(runtimeID ?? number - 1)"
        figure.name = "figure"
        playerShadow.name = "player-shadow-\(runtimeID ?? number - 1)"
        leftBoot.name = "left-boot"
        rightBoot.name = "right-boot"
        playerShadow.fillColor = SKColor(white: 0, alpha: 0.23)
        playerShadow.strokeColor = .clear
        playerShadow.zPosition = 6
        artwork.addChild(playerShadow)
        artwork.addChild(playerNode)
        selection.fillColor = yellow.withAlphaComponent(0.08)
        selection.name = "selection"
        selection.strokeColor = yellow
        selection.lineWidth = 0.17
        selection.zPosition = -2
        playerNode.addChild(selection)

        let brackets = CGMutablePath()
        for x in [-1.55, 1.55] {
            for y in [-1.55, 1.55] {
                let inwardX = x > 0 ? -0.55 : 0.55
                let inwardY = y > 0 ? -0.55 : 0.55
                brackets.move(to: CGPoint(x: x + inwardX, y: y))
                brackets.addLine(to: CGPoint(x: x, y: y))
                brackets.addLine(to: CGPoint(x: x, y: y + inwardY))
            }
        }
        sprite.passTarget.name = "pass-target"
        sprite.passTarget.path = brackets
        sprite.passTarget.strokeColor = cyan
        sprite.passTarget.lineWidth = 0.16
        sprite.passTarget.lineCap = .round
        sprite.passTarget.lineJoin = .round
        sprite.passTarget.zPosition = -1.5
        playerNode.addChild(sprite.passTarget)
        sprite.handover.name = "control-handover"
        sprite.handover.strokeColor = yellow
        sprite.handover.fillColor = .clear
        sprite.handover.lineWidth = 0.12
        sprite.handover.zPosition = -1
        playerNode.addChild(sprite.handover)

        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: -0.33, y: 2.0))
        arrow.addLine(to: CGPoint(x: 0, y: 2.4))
        arrow.addLine(to: CGPoint(x: 0.33, y: 2.0))
        aim.path = arrow
        aim.strokeColor = yellow
        aim.lineWidth = 0.18
        aim.lineCap = .round
        aim.lineJoin = .round
        aim.zPosition = 0.2
        playerNode.addChild(aim)
        figure.yScale = 1 / 0.86
        figure.zPosition = 0.1
        figure.position.y = -1.15
        playerNode.addChild(figure)

        for boot in [leftBoot, rightBoot] {
            boot.fillColor = SKColor(red: 0.06, green: 0.12, blue: 0.20, alpha: 1)
            boot.strokeColor = SKColor(white: 0.04, alpha: 0.7)
            boot.lineWidth = 0.07
            figure.addChild(boot)
        }
        let shorts = SKShapeNode(rectOf: CGSize(width: 0.94, height: 0.4), cornerRadius: 0.1)
        shorts.name = "shorts"
        shorts.position.y = 0.4
        shorts.fillColor = isGoalkeeper ? SKColor(red: 0.13, green: 0.17, blue: 0.23, alpha: 1) : isBlue
            ? SKColor(red: 0.94, green: 0.95, blue: 0.9, alpha: 1)
            : SKColor(red: 0.19, green: 0.14, blue: 0.18, alpha: 1)
        if let kit, !isGoalkeeper { shorts.fillColor = SKColor(clubHex: kit.shortsHex) }
        shorts.strokeColor = SKColor(red: 0.13, green: 0.21, blue: 0.3, alpha: 1)
        shorts.lineWidth = 0.08
        shorts.zPosition = 0.01
        figure.addChild(shorts)
        let arms = sprite.arms
        arms.name = "arms"
        arms.position.y = 0.86
        arms.fillColor = isGoalkeeper ? keeperColor : SKColor(red: 0.82, green: 0.54, blue: 0.35, alpha: 1)
        if let skinColor, !isGoalkeeper { arms.fillColor = skinColor }
        arms.strokeColor = SKColor(red: 0.16, green: 0.22, blue: 0.24, alpha: 1)
        arms.lineWidth = 0.08
        arms.zPosition = 0.02
        figure.addChild(arms)
        for x in [-0.85, 0.85] {
            let glove = SKShapeNode(rectOf: CGSize(width: 0.48, height: 0.43), cornerRadius: 0.14)
            glove.name = x < 0 ? "left-glove" : "right-glove"
            glove.position = CGPoint(x: x, y: 0.86)
            glove.fillColor = SKColor(red: 0.96, green: 1, blue: 0.88, alpha: 1)
            glove.strokeColor = SKColor(white: 0.12, alpha: 1)
            glove.lineWidth = 0.07
            sprite.keeperGloves.addChild(glove)
        }
        sprite.keeperGloves.zPosition = 0.025
        sprite.keeperGloves.name = "keeper-gloves"
        sprite.keeperGloves.isHidden = true
        figure.addChild(sprite.keeperGloves)
        let shirt = SKShapeNode(rectOf: CGSize(width: 1.1, height: 0.94), cornerRadius: 0.18)
        shirt.name = "shirt"
        shirt.position.y = 0.96
        shirt.fillColor = isGoalkeeper ? keeperColor : isBlue
            ? SKColor(red: 0.12, green: 0.49, blue: 0.98, alpha: 1)
            : SKColor(red: 0.93, green: 0.22, blue: 0.26, alpha: 1)
        if let kit, !isGoalkeeper { shirt.fillColor = SKColor(clubHex: kit.shirtHex) }
        shirt.strokeColor = isBlue
            ? SKColor(red: 0.08, green: 0.22, blue: 0.43, alpha: 1)
            : SKColor(red: 0.37, green: 0.10, blue: 0.14, alpha: 1)
        shirt.lineWidth = 0.12
        shirt.zPosition = 0.03
        figure.addChild(shirt)
        let stripe = SKShapeNode(rectOf: isBlue ? CGSize(width: 0.14, height: 0.67) : CGSize(width: 0.88, height: 0.14), cornerRadius: 0.02)
        stripe.position = isBlue ? CGPoint(x: -0.33, y: 0.93) : CGPoint(x: 0, y: 0.64)
        stripe.name = "kit-trim"
        stripe.fillColor = isGoalkeeper
            ? (isBlue ? SKColor(red: 0.10, green: 0.37, blue: 0.85, alpha: 1)
                      : SKColor(red: 0.95, green: 0.24, blue: 0.30, alpha: 1))
            : (isBlue ? cyan : SKColor(red: 1, green: 0.84, blue: 0.75, alpha: 1))
        if let kit { stripe.fillColor = SKColor(clubHex: kit.trimHex) }
        stripe.strokeColor = .clear
        stripe.zPosition = 0.04
        figure.addChild(stripe)
        let numberLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        numberLabel.name = "shirt-number"
        numberLabel.text = shirtNumber ?? (isGoalkeeper ? "1" : String(number))
        numberLabel.fontSize = 0.57
        numberLabel.fontColor = isGoalkeeper && isBlue ? SKColor(white: 0.12, alpha: 1) : .white
        if let kit {
            numberLabel.fontColor = SKColor(clubHex: RGBHex(isGoalkeeper ? kit.goalkeeperHex : kit.shirtHex).inkHex)
        }
        numberLabel.horizontalAlignmentMode = .center
        numberLabel.verticalAlignmentMode = .center
        numberLabel.position = CGPoint(x: isBlue ? 0.09 : 0, y: 0.99)
        numberLabel.zPosition = 0.045
        figure.addChild(numberLabel)
        let head = SKShapeNode(circleOfRadius: 0.4)
        head.name = "skin"
        head.position.y = 1.65
        head.fillColor = SKColor(red: 0.9, green: 0.65, blue: 0.42, alpha: 1)
        if let skinColor { head.fillColor = skinColor }
        head.strokeColor = SKColor(red: 0.15, green: 0.17, blue: 0.2, alpha: 1)
        head.lineWidth = 0.1
        head.zPosition = 0.05
        figure.addChild(head)
        let hair = sprite.hair
        hair.name = "hair"
        hair.position.y = 1.84
        hair.fillColor = SKColor(red: 0.16, green: 0.12, blue: 0.10, alpha: 1)
        if let appearance {
            hair.fillColor = SKColor(clubHex: appearance.hairHex)
            switch appearance.hairStyle % 4 {
            case 0: hair.path = CGPath(ellipseIn: CGRect(x: -0.30, y: -0.06, width: 0.60, height: 0.12), transform: nil)
            case 1: hair.path = CGPath(ellipseIn: CGRect(x: -0.37, y: -0.18, width: 0.74, height: 0.36), transform: nil)
            case 2: hair.path = CGPath(ellipseIn: CGRect(x: -0.43, y: -0.16, width: 0.86, height: 0.46), transform: nil)
            default: hair.path = CGPath(roundedRect: CGRect(x: -0.34, y: -0.12, width: 0.68, height: 0.30), cornerWidth: 0.08, cornerHeight: 0.08, transform: nil)
            }
        }
        hair.strokeColor = .clear
        hair.zPosition = 0.06
        figure.addChild(hair)

        // The compact role badge is independent of the body pose. Its blue/red
        // border keeps team identity clear despite the contrasting keeper jersey.
        sprite.keeperBadge.name = "keeper-badge"
        sprite.keeperBadge.position.y = -2.0
        sprite.keeperBadge.yScale = 1 / 0.86
        sprite.keeperBadge.zPosition = 0.3
        sprite.keeperBadge.isHidden = !isGoalkeeper
        let badge = SKShapeNode(rectOf: CGSize(width: 1.7, height: 0.78), cornerRadius: 0.22)
        badge.fillColor = SKColor(red: 0.035, green: 0.09, blue: 0.10, alpha: 0.9)
        badge.strokeColor = isBlue ? cyan : SKColor(red: 1, green: 0.52, blue: 0.48, alpha: 1)
        badge.lineWidth = 0.1
        sprite.keeperBadge.addChild(badge)
        let role = SKLabelNode(fontNamed: "Menlo-Bold")
        role.text = "GK"
        role.fontSize = 0.62
        role.fontColor = .white
        role.horizontalAlignmentMode = .center
        role.verticalAlignmentMode = .center
        role.zPosition = 0.01
        sprite.keeperBadge.addChild(role)
        playerNode.addChild(sprite.keeperBadge)

        powerTrack.position.y = -1.82
        powerTrack.fillColor = SKColor(red: 0.035, green: 0.10, blue: 0.10, alpha: 0.9)
        powerTrack.strokeColor = .white.withAlphaComponent(0.4)
        powerTrack.lineWidth = 0.06
        powerTrack.isHidden = true
        playerNode.addChild(powerTrack)
        powerFill.strokeColor = .clear
        powerFill.fillColor = yellow
        powerFill.zPosition = 1
        powerFill.isHidden = true
        playerNode.addChild(powerFill)
        sprite.powerBand.fillColor = .clear
        sprite.powerBand.strokeColor = SKColor(red: 0.47, green: 0.96, blue: 0.44, alpha: 1)
        sprite.powerBand.lineWidth = 0.08
        sprite.powerBand.zPosition = 2
        sprite.powerDanger.fillColor = SKColor(red: 1, green: 0.36, blue: 0.30, alpha: 0.65)
        sprite.powerDanger.strokeColor = .clear
        sprite.powerDanger.zPosition = 0.5
        sprite.powerMarker.fillColor = .white
        sprite.powerMarker.strokeColor = .clear
        sprite.powerMarker.zPosition = 3
        for node in [sprite.powerBand, sprite.powerDanger, sprite.powerMarker] {
            node.isHidden = true
            playerNode.addChild(node)
        }

        let tacklePath = CGMutablePath()
        tacklePath.addArc(center: .zero, radius: 1.72, startAngle: .pi * 0.18, endAngle: .pi * 0.82, clockwise: false)
        sprite.tackle.path = tacklePath
        sprite.tackle.strokeColor = isBlue ? cyan : SKColor(red: 1, green: 0.75, blue: 0.62, alpha: 1)
        sprite.tackle.lineWidth = 0.24
        sprite.tackle.lineCap = .round
        sprite.tackle.zPosition = 0.3
        sprite.tackle.isHidden = true
        playerNode.addChild(sprite.tackle)
        sprite.kickLeg.strokeColor = isBlue ? .white : SKColor(red: 0.94, green: 0.35, blue: 0.37, alpha: 1)
        sprite.kickLeg.lineWidth = 0.27
        sprite.kickLeg.lineCap = .round
        sprite.kickLeg.zPosition = -0.005
        sprite.kickLeg.isHidden = true
        figure.addChild(sprite.kickLeg)
        let skin = isGoalkeeper ? keeperColor : (skinColor ?? SKColor(red: 0.82, green: 0.54, blue: 0.35, alpha: 1))
        let limbInk = SKColor(red: 0.13, green: 0.20, blue: 0.22, alpha: 1)
        let socks = kit.map { SKColor(clubHex: $0.socksHex) }
            ?? (isBlue ? SKColor(white: 0.93, alpha: 1) : SKColor(red: 0.89, green: 0.27, blue: 0.29, alpha: 1))
        for (node, color, width, depth, name) in [
            (sprite.poseArmsOutline, limbInk, 0.42, 0.017, "arm-outline"),
            (sprite.poseArms, skin, 0.27, 0.018, "posed-arms"),
            (sprite.poseLegsOutline, limbInk, 0.40, -0.008, "leg-outline"),
            (sprite.poseLegs, socks, 0.25, -0.007, "posed-legs")
        ] {
            node.name = name
            node.strokeColor = color
            node.fillColor = .clear
            node.lineWidth = width
            node.lineCap = .round
            node.lineJoin = .round
            node.zPosition = depth
            node.isHidden = true
            figure.addChild(node)
        }
        sprite.impact.strokeColor = SKColor(red: 0.77, green: 0.81, blue: 0.47, alpha: 0.8)
        sprite.impact.lineWidth = 0.08
        sprite.impact.lineCap = .round
        sprite.impact.zPosition = -0.2
        sprite.impact.isHidden = true
        playerNode.addChild(sprite.impact)
        sprite.booking.position = CGPoint(x: 1.05, y: 0.3)
        sprite.booking.yScale = 1 / 0.86
        sprite.booking.fillColor = yellow
        sprite.booking.strokeColor = SKColor(white: 0.08, alpha: 1)
        sprite.booking.lineWidth = 0.065
        sprite.booking.zPosition = 0.4
        sprite.booking.isHidden = true
        playerNode.addChild(sprite.booking)
        upscaleArtwork(playerNode)
        upscaleArtwork(playerShadow)
        return sprite
    }

    private func buildBall() {
        ballNode.name = "football"
        ballShadow.name = "football-shadow"
        trailNode.zPosition = 7
        artwork.addChild(trailNode)
        for _ in 0..<9 {
            let dot = SKShapeNode(circleOfRadius: 0.28)
            dot.strokeColor = .clear
            dot.isHidden = true
            trailNode.addChild(dot)
            trailDots.append(dot)
        }
        ballShadow.fillColor = SKColor(white: 0, alpha: 0.35)
        ballShadow.strokeColor = .clear
        ballShadow.zPosition = 7
        artwork.addChild(ballShadow)
        heightConnector.strokeColor = .white.withAlphaComponent(0.32)
        heightConnector.lineWidth = 0.09
        heightConnector.lineCap = .round
        heightConnector.zPosition = 22
        heightConnector.isHidden = true
        artwork.addChild(heightConnector)
        artwork.addChild(ballNode)
        let ball = SKShapeNode(circleOfRadius: Pitch.ballRadius + 0.12)
        ball.fillColor = SKColor(red: 1, green: 1, blue: 0.95, alpha: 1)
        ball.strokeColor = SKColor(red: 0.05, green: 0.16, blue: 0.12, alpha: 0.9)
        ball.lineWidth = 0.09
        ball.yScale = 1 / 0.86
        ballNode.addChild(ball)
        let panels = CGMutablePath()
        for i in 0..<5 {
            let angle = Double(i) * 2 * .pi / 5
            let p = CGPoint(x: sin(angle) * 0.16, y: cos(angle) * 0.16)
            if i == 0 { panels.move(to: p) } else { panels.addLine(to: p) }
        }
        panels.closeSubpath()
        panels.addEllipse(in: CGRect(x: -0.33, y: 0.06, width: 0.11, height: 0.13))
        panels.addEllipse(in: CGRect(x: 0.16, y: -0.27, width: 0.12, height: 0.1))
        ballPanels.path = panels
        ballPanels.fillColor = SKColor(red: 0.11, green: 0.18, blue: 0.24, alpha: 1)
        ballPanels.strokeColor = .clear
        ballPanels.zPosition = 0.01
        ball.addChild(ballPanels)
    }

    private func buildDebug() {
        for (node, color) in [(trajectory, yellow), (playerVector, cyan), (curveVector, SKColor.systemPink), (passVector, SKColor.systemMint)] {
            node.strokeColor = color.withAlphaComponent(0.85)
            node.lineWidth = 0.15
            node.lineCap = .round
            node.zPosition = 30
            node.isHidden = true
            artwork.addChild(node)
        }
        passVector.lineWidth = 0.1
        passVector.alpha = 0.6
    }

    private func point(_ vector: Vector2) -> CGPoint {
        CGPoint(x: vector.x * drawingScale, y: vector.y * drawingScale)
    }

    private func drawingPath(_ path: CGPath) -> CGPath {
        var transform = CGAffineTransform(scaleX: drawingScale, y: drawingScale)
        return path.copy(using: &transform) ?? path
    }

    /// SpriteKit rasterizes shape paths in local units. Author comfortably in pitch
    /// metres, then expand geometry once so sub-metre shapes retain crisp edges when
    /// the camera magnifies the world. The public root still uses pitch metres.
    private func upscaleArtwork(_ node: SKNode) {
        node.position = CGPoint(x: node.position.x * drawingScale, y: node.position.y * drawingScale)
        if let shape = node as? SKShapeNode {
            if let path = shape.path { shape.path = drawingPath(path) }
            shape.lineWidth *= drawingScale
            shape.glowWidth *= drawingScale
        } else if let label = node as? SKLabelNode {
            label.fontSize *= drawingScale
        } else if let sprite = node as? SKSpriteNode {
            sprite.size = CGSize(width: sprite.size.width * drawingScale, height: sprite.size.height * drawingScale)
        }
        for child in node.children { upscaleArtwork(child) }
    }

    private func dottedHeightLine(from start: Vector2, to end: Vector2) -> CGPath {
        let path = CGMutablePath()
        let offset = end - start
        let segments = max(1, min(20, Int(offset.length / 0.4)))
        for index in 0..<segments {
            let fraction = (Double(index) + 0.45) / Double(segments)
            guard fraction < 0.88 else { continue }
            let dotStart = start + offset * fraction
            path.move(to: point(dotStart))
            path.addLine(to: point(dotStart + offset.normalized * 0.035))
        }
        return path
    }

    private func line(from start: Vector2, to end: Vector2) -> CGPath {
        let path = CGMutablePath()
        path.move(to: point(start))
        path.addLine(to: point(end))
        return path
    }
}
