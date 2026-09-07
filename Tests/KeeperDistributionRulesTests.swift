import XCTest
@testable import TopScoresSoccer

final class KeeperDistributionRulesTests: XCTestCase {
    private let tick = 1.0 / 60

    private func prepared(hands: Bool, rating: Double? = nil) -> FootballSimulation {
        var tuning = GameplayTuning.defaults
        tuning.aiSpeedScale = 0
        var simulation = FootballSimulation(tuning: tuning, mode: .match)
        simulation.pressAction()
        simulation.releaseAction(heldFor: 0.12)
        simulation.cancelInput()
        for id in simulation.roster.indices where !simulation.roster[id].isGoalkeeper {
            simulation.roster[id].state = PlayerState(position: Vector2(
                x: id.isMultiple(of: 2) ? -29 : 29, y: id < 5 ? -43 : 4))
        }
        simulation.ball = BallState(position: simulation.roster[5].state.position + .up, mode: .free)
        simulation.step(dt: tick)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        simulation.roster[4].state = PlayerState(position: Vector2(x: 0, y: -47))
        if let rating {
            simulation.roster[4].clubPlayer = ClubPlayer(id: "distribution-\(rating)", name: "Keeper",
                position: "G", jerseyNumber: 1, rating: rating, appearance: .generated(for: "keeper"))
        }
        if hands {
            simulation.ball = BallState(position: Vector2(x: 0, y: -45.9), velocity: -.up * 4, mode: .free)
            for _ in 0..<30 { simulation.step(dt: tick) }
            XCTAssertTrue(simulation.isHoldingGoalkeeper)
        } else {
            simulation.ball = BallState(position: Vector2(x: 17, y: -52), velocity: -.up * 90, mode: .free)
            simulation.step(dt: tick)
            XCTAssertEqual(simulation.matchRestart?.kind, .goalKick)
            for _ in 0..<120 where simulation.phase != .playing { simulation.step(dt: tick) }
            XCTAssertTrue(simulation.isTakingRestart)
            XCTAssertFalse(simulation.isHoldingGoalkeeper)
        }
        // Reposition after restart placement, so the tests have the same sparse layout.
        for id in 0..<4 {
            simulation.roster[id].state = PlayerState(position: Vector2(x: -29, y: -49 + Double(id)))
        }
        for id in 5..<9 {
            simulation.roster[id].state = PlayerState(position: Vector2(x: id.isMultiple(of: 2) ? -29 : 29, y: 4))
        }
        simulation.roster[9].state = PlayerState(position: Vector2(x: -12, y: 49))
        simulation.movement = .up
        XCTAssertEqual(simulation.selectedPlayerID, 4)
        return simulation
    }

    private func release(_ simulation: inout FootballSimulation, duration: Double) {
        simulation.pressAction()
        simulation.updateActionHold(heldFor: duration)
        simulation.movement = .zero
        simulation.releaseAction(heldFor: duration)
    }

    func testLongGoalKickCanSelectAndPhysicallyReachPlayerBeyondDefensiveLine() {
        var simulation = prepared(hands: false)
        simulation.roster[0].state = PlayerState(position: Vector2(x: simulation.ball.position.x, y: 12))
        XCTAssertTrue(OffsideRules.snapshot(actor: 4, ball: simulation.ball.position,
            roster: simulation.roster)!.candidates.contains(0), "This is an offside position during ordinary open play")
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 1)
        XCTAssertEqual(simulation.passTargetID, 0)
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.lastDistributionKind, .longGoalKick)
        XCTAssertEqual(simulation.roster[4].goalkeeperReleaseKind, .goalKick)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        for _ in 0..<300 where !simulation.hasControl && simulation.phase == .playing {
            simulation.step(dt: tick)
        }
        XCTAssertTrue(simulation.hasControl)
        XCTAssertEqual(simulation.selectedPlayerID, 0)
        XCTAssertEqual(simulation.possessionTeam, .blue)
        XCTAssertEqual(simulation.offsideCount, 0)
        XCTAssertNil(simulation.matchRestart)
    }

    func testOpenPlayLongThrowExcludesOffsideTargetAndPenalisesHisActualInvolvement() {
        var simulation = prepared(hands: true)
        simulation.roster[0].state = PlayerState(position: Vector2(x: simulation.ball.position.x, y: 22))
        XCTAssertTrue(OffsideRules.snapshot(actor: 4, ball: simulation.ball.position,
            roster: simulation.roster)!.candidates.contains(0))
        simulation.pressAction()
        simulation.updateActionHold(heldFor: 1)
        XCTAssertNil(simulation.passTargetID, "An open-play hand release has no goal-kick exemption")
        simulation.movement = .zero
        simulation.releaseAction(heldFor: 1)
        XCTAssertEqual(simulation.lastDistributionKind, .longThrow)
        XCTAssertNil(simulation.passTargetID)
        XCTAssertEqual(simulation.offsideCount, 0, "Being in position alone is not an offence")
        for _ in 0..<300 where simulation.phase == .playing {
            simulation.step(dt: tick)
        }
        XCTAssertEqual(simulation.offsideCount, 1, "The unassisted throw still has ordinary offside on physical involvement")
        XCTAssertEqual(simulation.matchRestart?.kind, .offside)
        XCTAssertEqual(simulation.matchRestart?.team, .red)
        XCTAssertEqual(simulation.foulCount, 0)
    }

    func testMarkerAtDescendingThrowLandingCanHeadItBeforeIntendedReceiver() {
        var simulation = prepared(hands: true)
        let origin = simulation.ball.position
        simulation.roster[0].state = PlayerState(position: origin + .up * 24)
        simulation.roster[5].state = PlayerState(position: origin + .up * 21.5, facing: -.up)
        XCTAssertEqual(simulation.passTargetID, 0)
        let kicks = simulation.kickCount
        release(&simulation, duration: 0.12)
        XCTAssertEqual(simulation.passTargetID, 0)
        // Zero AI speed deliberately disables autonomous headers. A small active scale keeps
        // this marking position local while allowing a real opposition heading decision.
        simulation.tuning.aiSpeedScale = 0.05
        for _ in 0..<180 where simulation.lastHeaderPlayerID == nil && simulation.phase == .playing {
            simulation.step(dt: tick)
        }
        XCTAssertEqual(simulation.lastHeaderPlayerID, 5)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        XCTAssertEqual(simulation.lastDeliberatePlayTeam, .red)
        XCTAssertLessThan(simulation.ball.velocity.y, 0)
        XCTAssertFalse(simulation.isControllingPassReceiver)
        XCTAssertEqual(simulation.kickCount, kicks + 1, "The defender's physical header is not a second human release")
    }

    func testDefenderEnteringAfterLowGoalKickReleaseCanPhysicallyIntercept() {
        var simulation = prepared(hands: false)
        let origin = simulation.ball.position
        simulation.roster[0].state = PlayerState(position: origin + .up * 18)
        release(&simulation, duration: 0.12)
        XCTAssertEqual(simulation.lastDistributionKind, .groundGoalKick)
        XCTAssertEqual(simulation.passTargetID, 0)
        // The opponent enters the real launched lane after the delivery choice is committed.
        simulation.roster[5].state = PlayerState(position: origin + .up * 8, facing: -.up)
        for _ in 0..<120 where simulation.possessionTeam != .red && simulation.phase == .playing {
            simulation.step(dt: tick)
        }
        XCTAssertEqual(simulation.possessionTeam, .red)
        XCTAssertEqual(simulation.lastTouchTeam, .red)
        XCTAssertFalse(simulation.isControllingPassReceiver)
        XCTAssertEqual(simulation.earlyPassAdjustmentCount, 0)
        XCTAssertEqual(simulation.ball.height, 0)
    }

    private func landingRange(_ simulation: FootballSimulation) -> Double {
        let flight = simulation.ball
        let gravity = simulation.tuning.ballGravity
        let time = (flight.verticalVelocity + sqrt(flight.verticalVelocity * flight.verticalVelocity
            + 2 * gravity * flight.height)) / gravity
        return flight.velocity.length * time
    }

    func testKeeperAbilityAddsLongDistributionRangeButHoldAndRatingHaveCaps() {
        for hands in [true, false] {
            var totals = [Double]()
            for rating in [55.0, 78, 95] {
                var total = 0.0
                for duration in [0.4, 0.65, 1.0] {
                    var simulation = prepared(hands: hands, rating: rating)
                    release(&simulation, duration: duration)
                    XCTAssertNil(simulation.passTargetID)
                    XCTAssertEqual(simulation.lastDistributionKind, hands ? .longThrow : .longGoalKick)
                    XCTAssertEqual(simulation.roster[4].goalkeeperReleaseKind, hands ? .overarmThrow : .goalKick)
                    XCTAssertGreaterThan(simulation.ball.verticalVelocity, 8)
                    let distance = landingRange(simulation)
                    XCTAssertTrue(distance.isFinite)
                    XCTAssertLessThan(distance, 95, "Ability must not make a whole-pitch launch unbounded")
                    total += distance
                }
                totals.append(total)
            }
            XCTAssertGreaterThan(totals[1], totals[0] + 10)
            XCTAssertGreaterThan(totals[2], totals[1] + 10)
            var full = prepared(hands: hands, rating: 95)
            release(&full, duration: 1)
            var overheld = prepared(hands: hands, rating: 200)
            release(&overheld, duration: 20)
            XCTAssertEqual(landingRange(full), landingRange(overheld), accuracy: 0.000001)
            XCTAssertEqual(full.ball.verticalVelocity, overheld.ball.verticalVelocity, accuracy: 0.000001)
        }
    }
}
