import XCTest

@MainActor
final class TeamManagementUITests: XCTestCase {
    func testPreMatchTacticsAndLiveSubstitutionScreen() {
        continueAfterFailure = false
        let app = launch()
        app.buttons["friendly.kickoff"].tap()
        XCTAssertTrue(app.buttons["team.kickoff"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["sandbox.pass"].exists)
        app.segmentedControls["team.style"].buttons["Defensive"].tap()
        capture(app, "Pre-match defensive starting XI")
        app.buttons["team.kickoff"].tap()
        XCTAssertTrue(app.buttons["sandbox.pause"].waitForExistence(timeout: 10))
        app.buttons["sandbox.pause"].tap()
        app.buttons["match.team-management"].tap()
        XCTAssertTrue(app.segmentedControls["team.style"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["team.style"].buttons["Defensive"].isSelected)
        app.segmentedControls["team.style"].buttons["Attacking"].tap()
        let midfielder = app.buttons["friendly.lineup.slot.5"]
        reveal(midfielder, in: app)
        midfielder.tap()
        let replacement = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "friendly.replacement.")).firstMatch
        XCTAssertTrue(replacement.waitForExistence(timeout: 5))
        replacement.tap()
        XCTAssertTrue(app.buttons["friendly.lineup.done"].waitForExistence(timeout: 5))
        capture(app, "Live team management substitution draft")
        app.buttons["friendly.lineup.done"].tap()
        XCTAssertTrue(app.buttons["sandbox.resume"].waitForExistence(timeout: 5))
        app.buttons["sandbox.resume"].tap()
        XCTAssertTrue(app.staticTexts["match.substitution-notice"].waitForExistence(timeout: 5))
        capture(app, "Substitution applied at kickoff stoppage")
        app.buttons["sandbox.reset"].tap()
        XCTAssertTrue(app.buttons["team.kickoff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["team.style"].buttons["Defensive"].isSelected,
                      "A new match restores the pre-match style, not the temporary attacking change")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["friendly.kickoff"].waitForExistence(timeout: 10))
        app.buttons["friendly.kickoff"].tap()
        XCTAssertTrue(app.buttons["team.kickoff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["team.style"].buttons["Defensive"].isSelected)
    }

    func testLargeTextPreMatchAndCancelStayReachable() {
        continueAfterFailure = false
        let app = launch(largeText: true)
        app.buttons["friendly.kickoff"].tap()
        let kickoff = app.buttons["team.kickoff"]
        XCTAssertTrue(kickoff.waitForExistence(timeout: 10))
        XCTAssertTrue(kickoff.isHittable)
        capture(app, "Team management at largest accessibility text size")
        let player = app.buttons["friendly.lineup.slot.1"]
        reveal(player, in: app)
        player.tap()
        XCTAssertTrue(app.navigationBars["Choose a player"].waitForExistence(timeout: 5))
        capture(app, "Player choice at largest accessibility text size")
        app.buttons["team.replacement.cancel"].tap()
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: kickoff)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed)
        app.buttons["team.cancel"].tap()
        XCTAssertTrue(app.buttons["friendly.kickoff"].waitForExistence(timeout: 5))
    }

    private func launch(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--premier-league"]
            + (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launchEnvironment["FRIENDLY_TEST_STORE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["friendly.kickoff"].waitForExistence(timeout: 10))
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            var bottom = app.frame.maxY - 30
            for id in ["team.kickoff", "friendly.lineup.done"] {
                let pinned = app.buttons[id]
                if pinned.exists && pinned.isHittable { bottom = min(bottom, pinned.frame.minY - 20) }
            }
            let top = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable)
                .map { $0.frame.maxY + 12 }.max() ?? app.frame.minY
            if element.isHittable && element.frame.midY > top && element.frame.maxY < bottom { return }
            if let scroll = app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                scroll.swipeUp()
            } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
