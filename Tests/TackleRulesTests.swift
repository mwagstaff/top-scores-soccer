import XCTest
@testable import TopScoresSoccer

final class TackleRulesTests: XCTestCase {
    private func decision(
        _ kind: TackleKind = .slide,
        ball: Double? = nil,
        body: Double? = nil,
        behind: Bool = false,
        speed: Double = 8,
        draw: Double = 0.99,
        configuration: TackleRules.Configuration = .defaults
    ) -> TackleDecision {
        TackleRules.assess(
            kind: kind,
            ballContactFraction: ball,
            opponentContactFraction: body,
            approachFromBehind: behind,
            relativeSpeed: speed,
            randomUnit: draw,
            configuration: configuration
        )
    }

    func testWhiffAndBallOnlyContactNeverFoulOrAwardCards() {
        for kind in [TackleKind.standing, .slide] {
            XCTAssertEqual(decision(kind, behind: true, speed: 30, draw: 0), .clean)
            XCTAssertEqual(decision(kind, ball: 0.4, behind: true, speed: 30, draw: 0), .clean)
        }
    }

    func testBallFirstAndSimultaneousContactAreCleanEvenForFastRearSlide() {
        for fraction in [0.0, 0.49, 0.5] {
            XCTAssertEqual(decision(ball: fraction, body: 0.5, behind: true, speed: 30, draw: 0), .clean)
        }
    }

    func testBodyFirstIsFoulEvenWhenBallIsReachedLaterInSameStep() {
        XCTAssertEqual(decision(ball: 0.7, body: 0.3), TackleDecision(foul: true, card: .none))
        XCTAssertTrue(decision(.standing, ball: 0.7, body: 0.3).foul)
        XCTAssertTrue(decision(body: 0.3).foul)
    }

    func testStandingFoulHasLowerYellowRiskThanSlideFoul() {
        XCTAssertEqual(decision(.standing, body: 0.3, draw: 0.10).card, .none)
        XCTAssertEqual(decision(.slide, body: 0.3, draw: 0.10).card, .yellow)
        XCTAssertEqual(decision(.standing, body: 0.3, draw: 0.039).card, .yellow)
        XCTAssertEqual(decision(.standing, body: 0.3, draw: 0.04).card, .none)
    }

    func testRearAndHighSpeedContactIncreaseYellowRisk() {
        XCTAssertEqual(decision(body: 0.3, draw: 0.30).card, .none)
        XCTAssertEqual(decision(body: 0.3, behind: true, draw: 0.30).card, .yellow)
        XCTAssertEqual(decision(body: 0.3, speed: 12, draw: 0.30).card, .yellow)
    }

    func testDirectRedRequiresFastSlideFromBehind() {
        XCTAssertEqual(decision(.standing, body: 0.3, behind: true, speed: 30, draw: 0).card, .yellow)
        XCTAssertEqual(decision(.slide, body: 0.3, behind: false, speed: 30, draw: 0).card, .yellow)
        XCTAssertEqual(decision(.slide, body: 0.3, behind: true, speed: 11.99, draw: 0).card, .yellow)
        XCTAssertEqual(decision(.slide, body: 0.3, behind: true, speed: 12, draw: 0).card, .red)
    }

    func testRecklessSlideUsesRareDisjointRedAndYellowRollRanges() {
        XCTAssertEqual(decision(body: 0.3, behind: true, speed: 12, draw: 0.039999).card, .red)
        XCTAssertEqual(decision(body: 0.3, behind: true, speed: 12, draw: 0.04).card, .yellow)
        XCTAssertEqual(decision(body: 0.3, behind: true, speed: 12, draw: 0.559).card, .yellow)
        XCTAssertEqual(decision(body: 0.3, behind: true, speed: 12, draw: 0.561).card, .none)

        let decisions = (0..<10_000).map {
            decision(body: 0.3, behind: true, speed: 12, draw: (Double($0) + 0.5) / 10_000)
        }
        XCTAssertEqual(decisions.filter { $0.card == .red }.count, 400)
        XCTAssertEqual(decisions.filter { $0.card == .yellow }.count, 5_200)
        XCTAssertTrue(decisions.allSatisfy(\.foul))
    }

    func testConfigurationCanTuneDisciplineWithoutChangingContactLegality() {
        var configuration = TackleRules.Configuration.defaults
        configuration.standingYellowChance = 0
        configuration.slideYellowChance = 0
        configuration.behindYellowBonus = 0
        configuration.highSpeedYellowBonus = 0
        configuration.recklessSlideRedChance = 0
        XCTAssertEqual(decision(body: 0.3, behind: true, speed: 30, draw: 0, configuration: configuration),
                       TackleDecision(foul: true, card: .none))
        XCTAssertEqual(decision(ball: 0.2, body: 0.3, configuration: configuration), .clean)
    }

    func testInvalidContactCannotBecomeAnInventedCollision() {
        for invalid in [-0.1, 1.1, Double.nan, Double.infinity] {
            XCTAssertEqual(decision(body: invalid, behind: true, speed: 30, draw: 0), .clean)
            XCTAssertTrue(decision(ball: invalid, body: 0.3).foul)
        }
    }

    func testInvalidRandomValueDoesNotInventACard() {
        XCTAssertEqual(decision(body: 0.3, behind: true, speed: 30, draw: .nan).card, .none)
        XCTAssertEqual(decision(body: 0.3, behind: true, speed: 30, draw: .infinity).card, .none)
    }
}
