import XCTest
@testable import TopScoresSoccer

final class GroundPassPlannerTests: XCTestCase {
    private let tick = 1.0 / 60

    private func integratedMotion(_ state: PlayerState, requested: Vector2, time: Double,
                                  acceleration: Double = 42, deceleration: Double = 30) -> PlayerState {
        var result = state
        var elapsed = 0.0
        while elapsed < time {
            let dt = min(tick, time - elapsed)
            let rate = requested.length > 0.0001 ? acceleration : deceleration
            result.velocity += (requested - result.velocity).clampedLength(rate * dt)
            result.position += result.velocity * dt
            elapsed += dt
        }
        return result
    }

    func testPredictionAccountsForAccelerationAndNeutralBraking() {
        let receiver = PlayerState(position: .zero, velocity: Vector2(x: 6, y: 0))
        for requested in [Vector2.zero, .up * 11.76, Vector2(x: -2.352, y: 0)] {
            for time in [0.1, 0.5, 1.5] {
                let planned = GroundPassPlanner.motion(after: time, receiver: receiver,
                    requestedVelocity: requested, acceleration: 42, deceleration: 30)
                let integrated = integratedMotion(receiver, requested: requested, time: time)
                XCTAssertLessThan((planned.position - integrated.position).length, 0.12)
                XCTAssertLessThan((planned.velocity - integrated.velocity).length, 0.001)
            }
        }
    }

    func testRollingFlightAndSustainedReceiverRunMeetAtSamePointAcrossDistances() {
        let origin = Vector2(x: 0, y: -38.75)
        for distance in [10.0, 20, 30, 40] {
            for initial in [Vector2.zero, Vector2(x: 6, y: 0), Vector2.up * 6] {
                for requested in [Vector2.zero, .up * 11.76, Vector2(x: 2.352, y: 0)] {
                    let receiver = PlayerState(position: origin + .up * distance, velocity: initial)
                    let plan = GroundPassPlanner.plan(origin: origin, receiver: receiver,
                        requestedVelocity: requested, acceleration: 42, deceleration: 30,
                        minimumSpeed: 21, arrivalSpeed: 12, friction: 5)
                    XCTAssertTrue(plan.isReachable)
                    XCTAssertLessThanOrEqual(plan.launchSpeed, 44)
                    let direction = (plan.destination - origin).normalized
                    let travel = plan.launchSpeed * plan.flightTime - 2.5 * plan.flightTime * plan.flightTime
                    let ballAtContact = origin + direction * travel
                    let actual = integratedMotion(receiver, requested: requested, time: plan.flightTime)
                    XCTAssertLessThan((ballAtContact - actual.position).length, 0.13)
                    let closingSpeed = plan.launchSpeed - 5 * plan.flightTime - actual.velocity.dot(direction)
                    XCTAssertGreaterThanOrEqual(closingSpeed, 11.99)
                }
            }
        }
    }

    func testNewMovementReplacesOldAILateralLead() {
        let origin = Vector2(x: 0, y: -38.75)
        let receiver = PlayerState(position: origin + .up * 20, velocity: Vector2(x: 6, y: 0))
        let manual = GroundPassPlanner.plan(origin: origin, receiver: receiver,
            requestedVelocity: .up * 2.352, acceleration: 42, deceleration: 30,
            minimumSpeed: 21, arrivalSpeed: 12, friction: 5)
        let autonomous = GroundPassPlanner.plan(origin: origin, receiver: receiver,
            requestedVelocity: nil, acceleration: 42, deceleration: 30,
            minimumSpeed: 21, arrivalSpeed: 12, friction: 5)
        XCTAssertLessThan(manual.destination.x, 0.6)
        XCTAssertGreaterThan(autonomous.destination.x, 4)
        XCTAssertGreaterThan(manual.destination.y, receiver.position.y)
    }

    func testBoundaryPredictionUsesEffectiveMovementAndStaysOnPitch() {
        let receiver = PlayerState(position: Vector2(x: 33, y: 50), velocity: Vector2(x: 6, y: 8))
        let state = GroundPassPlanner.motion(after: 1, receiver: receiver,
            requestedVelocity: Vector2(x: 6, y: 8), acceleration: 42, deceleration: 30)
        XCTAssertEqual(state.position.x, Pitch.width / 2 - Pitch.playerRadius)
        XCTAssertEqual(state.position.y, Pitch.length / 2 - Pitch.playerRadius)
        XCTAssertEqual(state.velocity, .zero)
        let plan = GroundPassPlanner.plan(origin: Vector2(x: 20, y: 20), receiver: receiver,
            requestedVelocity: Vector2(x: 6, y: 8), acceleration: 42, deceleration: 30,
            minimumSpeed: 21, arrivalSpeed: 12, friction: 5)
        XCTAssertTrue(plan.isReachable)
        XCTAssertLessThanOrEqual(plan.destination.x, Pitch.width / 2 - Pitch.playerRadius)
        XCTAssertLessThanOrEqual(plan.destination.y, Pitch.length / 2 - Pitch.playerRadius)
    }

    func testUnreachableRollingPassIsExplicitRatherThanPromised() {
        let plan = GroundPassPlanner.plan(origin: Vector2(x: 0, y: -30),
            receiver: PlayerState(position: Vector2(x: 0, y: 30)), requestedVelocity: .zero,
            acceleration: 42, deceleration: 30, minimumSpeed: 8, arrivalSpeed: 4,
            friction: 9, maximumSpeed: 10)
        XCTAssertFalse(plan.isReachable)
        XCTAssertLessThanOrEqual(plan.launchSpeed, 10)
        XCTAssertTrue(plan.destination.x.isFinite && plan.destination.y.isFinite && plan.flightTime.isFinite)
    }

    private func exercise() -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .passing)
        simulation.player.position = Vector2(x: 0, y: -40)
        simulation.ball.position = simulation.player.position + .up * 1.25
        simulation.roster[1].state.position = simulation.ball.position + .up * 20
        simulation.roster[2].state.position = Vector2(x: -28, y: 44)
        for id in 3..<6 { simulation.roster[id].state.position = Vector2(x: id % 2 == 0 ? 28 : -28, y: 40) }
        return simulation
    }

    func testClearDirectionWinsOverAnOpenWideAlternative() {
        var simulation = exercise()
        simulation.roster[2].state.position = simulation.roster[1].state.position + Vector2(x: 17, y: 0)
        simulation.roster[3].state.position = simulation.ball.position + .up * 9
        simulation.movement = .up
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 1)
        XCTAssertEqual(simulation.lastKickKind, "pass")
    }

    func testSimilarDirectionsCanStillPreferAnOpenLane() {
        var simulation = exercise()
        simulation.roster[2].state.position = simulation.roster[1].state.position + Vector2(x: 4, y: 0)
        simulation.roster[3].state.position = simulation.ball.position + .up * 10
        simulation.movement = .zero
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        XCTAssertEqual(simulation.passTargetID, 2)
    }

    func testActualRatedKicksReachContinuouslyAdvancingReceiverAtFortyMetres() {
        for rating in [70.0, 78, 90] {
            var simulation = exercise()
            simulation.roster[1].state.position = simulation.ball.position + .up * 40
            let profile = ClubPlayer(id: "test-\(rating)", name: "Planner test", position: "D",
                                     rating: rating, appearance: .generated(for: "planner"))
            simulation.roster[0].clubPlayer = profile
            simulation.roster[1].clubPlayer = profile
            simulation.movement = .up
            simulation.pressAction()
            simulation.releaseAction(heldFor: 0.12)
            XCTAssertEqual(simulation.passTargetID, 1)
            XCTAssertLessThanOrEqual(simulation.ball.velocity.length, 44)
            for _ in 0..<180 where !simulation.hasControl { simulation.step(dt: tick) }
            XCTAssertTrue(simulation.hasControl, "The launch must account for the actual rated power applied by kick execution.")
            XCTAssertEqual(simulation.selectedPlayerID, 1)
            XCTAssertEqual(simulation.chipCount, 0)
        }
    }
}
