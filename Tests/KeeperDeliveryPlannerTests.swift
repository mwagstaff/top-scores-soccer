import XCTest
@testable import TopScoresSoccer

final class KeeperDeliveryPlannerTests: XCTestCase {
    private let origin = Vector2(x: 0, y: -48)
    private let tuning = GameplayTuning.defaults

    private func delivery(distance: Double, movement: Vector2 = .zero, hands: Bool = true,
                          hold: Double = 0.12, ability: Double = 1,
                          blockers: [Vector2] = []) -> KeeperDeliveryPlanner.Plan {
        KeeperDeliveryPlanner.plan(origin: origin,
            receiver: PlayerState(position: origin + .up * distance), requestedVelocity: movement * 11.76,
            acceleration: 42, deceleration: 30, hands: hands, heldFor: hold,
            ability: ability, blockers: blockers, tuning: tuning)
    }

    func testBallisticMeetingMatchesActualReceiverMotionAcrossDistancesAndSpeeds() {
        for distance in [6.0, 18, 30, 40] {
            for movement in [Vector2.zero, .up * 0.35, .up, Vector2(x: 0.35, y: 0)] {
                let plan = delivery(distance: distance, movement: movement)
                XCTAssertTrue(plan.isReachable, "distance=\(distance), movement=\(movement)")
                let state = GroundPassPlanner.motion(after: plan.flightTime,
                    receiver: PlayerState(position: origin + .up * distance), requestedVelocity: movement * 11.76,
                    acceleration: 42, deceleration: 30)
                XCTAssertLessThan((plan.destination - state.position).length, 0.000001)
                XCTAssertLessThan((origin + plan.direction * plan.speed * plan.flightTime - state.position).length, 0.000001)
                XCTAssertEqual(plan.height + plan.verticalVelocity * plan.flightTime
                    - 0.5 * tuning.ballGravity * plan.flightTime * plan.flightTime, 0.2, accuracy: 0.000001)
                XCTAssertLessThanOrEqual(plan.speed, 34)
            }
        }
    }

    func testFullSpeedCloseReceiverUpgradesToAReachableOverarmThrow() {
        let stationary = delivery(distance: 6)
        let runner = delivery(distance: 6, movement: .up)
        XCTAssertEqual(stationary.kind, .underarmThrow)
        XCTAssertEqual(runner.kind, .overarmThrow)
        XCTAssertTrue(runner.isReachable)
        XCTAssertGreaterThan(runner.height, stationary.height)
    }

    func testCentralBlockerRaisesArcButMarkerAtDestinationDoesNotPromiseBypass() {
        let clear = delivery(distance: 24)
        let blocked = delivery(distance: 24, blockers: [origin + .up * 12])
        let marked = delivery(distance: 24, blockers: [origin + .up * 23])
        XCTAssertEqual(clear.kind, .overarmThrow)
        XCTAssertEqual(blocked.kind, .highThrow)
        XCTAssertEqual(marked.kind, .overarmThrow)
        XCTAssertTrue(blocked.isReachable)
        let time = 12 / blocked.speed
        XCTAssertGreaterThan(blocked.height + blocked.verticalVelocity * time - 9 * time * time,
                             HeadingMechanics.maximumHeight)
        // The marked recipient's foot-height arrival remains physically available to either team.
        XCTAssertEqual(marked.verticalVelocity, clear.verticalVelocity, accuracy: 0.000001)
    }

    func testNewLedLaneBlockerRebuildsTheHighLaunchProfile() {
        let receiver = PlayerState(position: origin + .up * 9)
        // Initially outside the lane, inside the rightward receiver's predicted line.
        let blocker = origin + Vector2(x: 3.8, y: 4)
        XCTAssertFalse(KeeperDeliveryPlanner.isBlocked(origin: origin, destination: receiver.position, opponents: [blocker]))
        let plan = KeeperDeliveryPlanner.plan(origin: origin, receiver: receiver,
            requestedVelocity: Vector2(x: 11.76, y: 0), acceleration: 42, deceleration: 30,
            hands: true, heldFor: 0.12, ability: 1, blockers: [blocker], tuning: tuning)
        XCTAssertEqual(plan.kind, .highThrow)
        XCTAssertEqual(plan.height, 1.8)
        XCTAssertTrue(plan.isReachable)
        XCTAssertGreaterThan(plan.verticalVelocity, 7)
    }

    func testGoalKickClearLaneUsesGroundPlanAndBlockedLaneUsesBallisticPlan() {
        let ground = delivery(distance: 22, movement: .up * 0.35, hands: false)
        let loft = delivery(distance: 22, movement: .up * 0.35, hands: false,
                            blockers: [origin + .up * 10])
        XCTAssertEqual(ground.kind, .groundGoalKick)
        XCTAssertEqual(ground.height, 0)
        XCTAssertEqual(ground.verticalVelocity, 0)
        XCTAssertEqual(loft.kind, .loftedGoalKick)
        XCTAssertTrue(loft.isReachable)
        XCTAssertGreaterThan(loft.verticalVelocity, 8)
    }

    func testLongHandsDeliveryIsAlwaysAHighThrowAndChargeAddsPhysicalRange() {
        let light = KeeperDeliveryPlanner.space(origin: origin, aim: .up, hands: true,
            heldFor: 0.4, ability: 1, tuning: tuning)
        let full = KeeperDeliveryPlanner.space(origin: origin, aim: .up, hands: true,
            heldFor: 1, ability: 1, tuning: tuning)
        XCTAssertEqual(light.kind, .longThrow)
        XCTAssertEqual(full.kind, .longThrow)
        XCTAssertEqual(light.height, 1.8)
        XCTAssertGreaterThan(light.verticalVelocity, 12)
        XCTAssertGreaterThan(full.verticalVelocity, light.verticalVelocity)
        XCTAssertGreaterThan((full.destination - origin).length, (light.destination - origin).length + 10)
    }

    func testAbilityChangesLongRangeOnceWhileRoutineDeliveryStillMeetsRecipient() {
        let weak = KeeperDeliveryPlanner.space(origin: origin, aim: .up, hands: true,
            heldFor: 1, ability: 0.9, tuning: tuning)
        let strong = KeeperDeliveryPlanner.space(origin: origin, aim: .up, hands: true,
            heldFor: 1, ability: 1.1, tuning: tuning)
        XCTAssertGreaterThan(strong.speed, weak.speed)
        XCTAssertGreaterThan((strong.destination - origin).length, (weak.destination - origin).length)
        XCTAssertEqual(weak.speed, 34 * 0.9, accuracy: 0.000001)
        for quality in [0.9, 1, 1.1] {
            let routine = delivery(distance: 18, ability: quality)
            XCTAssertTrue(routine.isReachable)
            XCTAssertEqual(routine.speed * routine.flightTime, 18, accuracy: 0.000001)
        }
    }
}
