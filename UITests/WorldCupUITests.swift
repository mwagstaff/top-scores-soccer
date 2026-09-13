import XCTest

@MainActor
final class WorldCupUITests: XCTestCase {
    func testCreateWorldCupAndPersistSelectedTeam() {
        let app = launchWorldCup()
        let start = element("worldcup.start", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(element("worldcup.play", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("worldcup.team-name", in: app).label.contains("Mexico"))
        XCTAssertTrue(element("worldcup.selected-group", in: app).exists)
        XCTAssertTrue(element("worldcup.save-status", in: app).exists)

        app.terminate(); app.launch()
        XCTAssertTrue(element("worldcup.play", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("worldcup.team-name", in: app).label.contains("Mexico"))
    }

    func testTiedFinalOffersExtraTimeThenPenaltyShootout() {
        let app = launchWorldCup(extra: ["--world-cup-final-ui", "--short-match"])
        element("worldcup.start", in: app).tap()
        XCTAssertTrue(element("worldcup.play", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("worldcup.progress", in: app).label.contains("Final"))
        element("worldcup.play", in: app).tap()
        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        app.buttons["sandbox.pass"].tap()
        let secondHalf = element("match.second-half", in: app)
        XCTAssertTrue(secondHalf.waitForExistence(timeout: 10))
        secondHalf.tap()
        let extraTime = element("worldcup.extra-time", in: app)
        XCTAssertTrue(extraTime.waitForExistence(timeout: 12))
        extraTime.tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        app.buttons["sandbox.pass"].tap()
        XCTAssertTrue(secondHalf.waitForExistence(timeout: 10))
        secondHalf.tap()
        XCTAssertTrue(element("worldcup.penalty-shootout", in: app).waitForExistence(timeout: 10))
    }

    func testDebugCelebrationCanBeOpenedDirectly() {
        let app = XCUIApplication()
        app.launchArguments = ["--world-cup-celebration"]
        app.launch()
        XCTAssertTrue(element("worldcup.celebration.team", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("worldcup.celebration.continue", in: app).exists)
    }

    func testDebugCelebrationCanBePreviewedFromWorldCupScreen() {
        let app = launchWorldCup()
        let preview = element("worldcup.preview-celebration", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(element("worldcup.celebration.team", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("worldcup.celebration.continue", in: app).exists)
    }

    func testCompletedMatchdayShowsExpandableResultHistory() {
        let app = launchWorldCup()
        element("worldcup.start", in: app).tap()
        XCTAssertTrue(element("worldcup.play", in: app).waitForExistence(timeout: 10))
        element("worldcup.play", in: app).tap()
        XCTAssertTrue(element("worldcup.debug-match", in: app).waitForExistence(timeout: 10))
        element("worldcup.debug-match", in: app).tap()
        element("worldcup.debug-win", in: app).tap()
        XCTAssertTrue(element("worldcup.result-saved", in: app).waitForExistence(timeout: 10))
        element("worldcup.continue", in: app).tap()

        let lozenge = element("worldcup.results-lozenge", in: app)
        XCTAssertTrue(lozenge.waitForExistence(timeout: 10))
        let toggle = element("worldcup.results-toggle", in: app)
        XCTAssertTrue(toggle.exists)
        toggle.tap()
        XCTAssertTrue(element("worldcup.results-history", in: app).waitForExistence(timeout: 5))
        let tables = element("worldcup.results-tables", in: app)
        XCTAssertTrue(tables.exists)
        tables.tap()
        XCTAssertTrue(element("worldcup.group-tables", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("worldcup.group-table.A", in: app).exists)
        element("worldcup.group-picker.B", in: app).tap()
        XCTAssertTrue(element("worldcup.group-table.B", in: app).waitForExistence(timeout: 5))
        let picker = element("worldcup.group-picker", in: app)
        XCTAssertTrue(picker.exists)
        for _ in 0..<5 {
            if element("worldcup.group-picker.L", in: app).exists { break }
            picker.swipeLeft()
        }
        XCTAssertTrue(element("worldcup.group-picker.L", in: app).exists)
    }

    func testDebugControlsCanJumpStraightToPenaltyShootout() {
        let app = launchWorldCup(extra: ["--world-cup-final-ui"])
        element("worldcup.start", in: app).tap()
        XCTAssertTrue(element("worldcup.play", in: app).waitForExistence(timeout: 10))
        element("worldcup.play", in: app).tap()
        XCTAssertTrue(element("worldcup.debug-match", in: app).waitForExistence(timeout: 10))
        element("worldcup.debug-match", in: app).tap()
        XCTAssertTrue(element("worldcup.debug-win", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("worldcup.debug-draw", in: app).exists)
        XCTAssertTrue(element("worldcup.debug-defeat", in: app).exists)
        XCTAssertTrue(element("worldcup.debug-extraTime", in: app).exists)
        let penalties = element("worldcup.debug-penaltyShootout", in: app)
        XCTAssertTrue(penalties.exists)
        penalties.tap()
        XCTAssertTrue(element("worldcup.penalty-shootout", in: app).waitForExistence(timeout: 10))
    }

    func testDebugWinsCanCompleteTheWholeTournamentAndReachCelebration() {
        let app = launchWorldCup()
        element("worldcup.start", in: app).tap()
        for match in 1...8 {
            let play = element("worldcup.play", in: app)
            XCTAssertTrue(play.waitForExistence(timeout: 10), "Missing match \(match)")
            play.tap()
            let debug = element("worldcup.debug-match", in: app)
            XCTAssertTrue(debug.waitForExistence(timeout: 10), "Missing debug controls for match \(match)")
            debug.tap()
            let win = element("worldcup.debug-win", in: app)
            XCTAssertTrue(win.waitForExistence(timeout: 5))
            win.tap()
            XCTAssertTrue(element("worldcup.result-saved", in: app).waitForExistence(timeout: 10))
            element("worldcup.continue", in: app).tap()
        }
        XCTAssertTrue(element("worldcup.celebration.team", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("worldcup.celebration.continue", in: app).exists)
    }

    private func launchWorldCup(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--world-cup", "--world-cup-ui-testing", "--reset-world-cup-ui"] + extra
        app.launchEnvironment["WORLD_CUP_TEST_STORE_ID"] = UUID().uuidString
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
