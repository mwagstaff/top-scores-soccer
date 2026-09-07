import XCTest
@testable import TopScoresSoccer

final class BallFlightTests: XCTestCase {
    func testChipRisesToBallisticApexWithoutAddingHorizontalPower() {
        var ball = BallState()
        ball.velocity = Vector2(x: 20, y: 0)
        BallFlight.chip(&ball, liftSpeed: 8)
        XCTAssertEqual(BallFlight.height(after: 0.25, ball: ball), 1.4375, accuracy: 0.000001)
        BallFlight.advance(&ball, dt: 8.0 / 18)
        XCTAssertEqual(ball.height, 64.0 / 36, accuracy: 0.000001)
        XCTAssertEqual(ball.verticalVelocity, 0, accuracy: 0.000001)
        XCTAssertEqual(ball.velocity, Vector2(x: 20, y: 0))
    }

    func testLandingBouncesLosesEnergyAndEventuallySettles() {
        var ball = BallState()
        ball.velocity = .up * 20
        BallFlight.chip(&ball)
        BallFlight.advance(&ball, dt: 16.0 / 18)
        XCTAssertEqual(ball.height, 0, accuracy: 0.000001)
        XCTAssertEqual(ball.verticalVelocity, 2.56, accuracy: 0.000001)
        XCTAssertEqual(ball.velocity.length, 17.2, accuracy: 0.000001)
        BallFlight.advance(&ball, dt: 3)
        XCTAssertEqual(ball.height, 0)
        XCTAssertEqual(ball.verticalVelocity, 0)
        XCTAssertLessThan(ball.velocity.length, 17.2)
    }

    func testAirborneBallCannotBeRechippedAndStepGroupingMatches() {
        var single = BallState()
        single.velocity = .up * 24
        BallFlight.chip(&single)
        var stepped = single
        BallFlight.advance(&stepped, dt: 0.1)
        let lift = stepped.verticalVelocity
        BallFlight.chip(&stepped, liftSpeed: 100)
        XCTAssertEqual(stepped.verticalVelocity, lift)
        for _ in 0..<114 { BallFlight.advance(&stepped, dt: 1.0 / 60) }
        BallFlight.advance(&single, dt: 2)
        XCTAssertEqual(stepped.height, single.height, accuracy: 0.000001)
        XCTAssertEqual(stepped.verticalVelocity, single.verticalVelocity, accuracy: 0.000001)
        XCTAssertEqual(stepped.velocity.length, single.velocity.length, accuracy: 0.000001)
    }
}
