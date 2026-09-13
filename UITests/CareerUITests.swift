import XCTest
import UIKit

@MainActor
final class CareerUITests: XCTestCase {
    func testFinalFixtureStartsAnotherSeasonAndKeepsThePreviousRecord() {
        let app = launchCareer(finalMatch: true)
        startCareer(clubID: "1", name: "Liverpool", in: app)
        assertValue(element("career.progress", in: app), contains: "round:38;")
        playShortFixture(in: app)
        element("career.continue", in: app).tap()
        let nextSeason = element("career.nextSeason", in: app)
        XCTAssertTrue(nextSeason.waitForExistence(timeout: 5))
        XCTAssertTrue(element("career.seasonComplete", in: app).exists)
        attach(app, name: "Career season complete")
        assertTablePlayed(38, clubID: "1", in: app)
        dismissSheet(in: app)
        nextSeason.tap()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 5))
        assertValue(element("career.progress", in: app), contains: "round:1;")
        assertTablePlayed(0, clubID: "1", in: app)
        dismissSheet(in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 10))
        assertValue(element("career.progress", in: app), contains: "round:1;")
        XCTAssertTrue(element("career.clubName", in: app).label.contains("Liverpool"))
        let history = element("career.history", in: app)
        reveal(history, in: app)
        history.tap()
        let previousSeason = element("career.history.season.1", in: app)
        XCTAssertTrue(previousSeason.waitForExistence(timeout: 5))
        let finalTable = app.buttons["Final table"].firstMatch
        XCTAssertTrue(finalTable.waitForExistence(timeout: 5))
        finalTable.tap()
        let previousRow = element("career.table.club.1", in: app)
        reveal(previousRow, in: app)
        assertValue(previousRow, contains: "played:38;")
        attach(app, name: "Career previous season table after starting season two")
    }

    func testSelectedLineupAndCompletedRoundSurviveRelaunch() {
        let app = launchCareer()
        startCareer(clubID: "1", name: "Liverpool", in: app)
        assertValue(element("career.progress", in: app), contains: "round:1;")

        element("career.lineup", in: app).tap()
        let formation = element("friendly.formation", in: app)
        XCTAssertTrue(formation.waitForExistence(timeout: 5))
        formation.tap()
        app.buttons["4–3–3"].firstMatch.tap()

        let defender = element("friendly.lineup.slot.1", in: app)
        defender.tap()
        let replacement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "friendly.replacement.")).firstMatch
        XCTAssertTrue(replacement.waitForExistence(timeout: 5))
        let replacementName = replacement.label.components(separatedBy: ",")[0]
        replacement.tap()
        XCTAssertTrue(defender.waitForExistence(timeout: 5))
        XCTAssertTrue(defender.label.contains(replacementName))
        element("friendly.lineup.done", in: app).tap()
        XCTAssertTrue(element("career.lineup", in: app).label.contains("4–3–3"))
        attach(app, name: "Career first fixture and selected lineup")

        playShortFixture(in: app)
        element("career.continue", in: app).tap()
        assertValue(element("career.progress", in: app), contains: "round:2;")
        assertTablePlayed(1, clubID: "1", in: app)
        attach(app, name: "Career table after first round")
        dismissSheet(in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("career.clubName", in: app).label.contains("Liverpool"))
        assertValue(element("career.progress", in: app), contains: "round:2;")
        XCTAssertTrue(element("career.lineup", in: app).label.contains("4–3–3"))
        element("career.lineup", in: app).tap()
        let savedDefender = element("friendly.lineup.slot.1", in: app)
        XCTAssertTrue(savedDefender.waitForExistence(timeout: 5))
        XCTAssertTrue(savedDefender.label.contains(replacementName), "The manual XI edit should survive an app restart")
        element("friendly.lineup.done", in: app).tap()
        assertTablePlayed(1, clubID: "1", in: app)
    }

    func testAwayFixtureExitConfirmationLeavesMatchUnplayed() {
        let app = launchCareer()
        startCareer(clubID: "9", name: "Tottenham", in: app)
        assertValue(element("career.progress", in: app), contains: "round:1;")
        element("career.play", in: app).tap()
        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        assertValue(action, contains: "players:22;")
        XCTAssertTrue(element("match.selected-player", in: app).label.contains("Tottenham"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] %@ AND label CONTAINS[cd] %@", "Matchweek", "Away")).firstMatch.exists)
        XCTAssertFalse(element("sandbox.reset", in: app).exists, "A career fixture cannot be reset during play")
        attach(app, name: "Career away fixture with selected club under player control")

        element("sandbox.exit", in: app).tap()
        let leave = element("career.leave-match", in: app)
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        let keepPlaying = app.buttons["Keep playing"].firstMatch
        if keepPlaying.exists {
            keepPlaying.tap()
        } else {
            // iPad presents a popover: tapping the pitch outside it cancels.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.7)).tap()
        }
        XCTAssertTrue(action.exists)
        XCTAssertFalse(leave.exists)
        XCTAssertFalse(element("career.play", in: app).isHittable, "Cancelling Leave match must keep the season dashboard covered")
        element("sandbox.exit", in: app).tap()
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        leave.tap()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 5))
        assertValue(element("career.progress", in: app), contains: "round:1;")
        assertTablePlayed(0, clubID: "9", in: app)
        dismissSheet(in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 10))
        assertValue(element("career.progress", in: app), contains: "round:1;")
        playShortFixture(in: app, controlledClubName: "Tottenham")
        element("career.continue", in: app).tap()
        assertValue(element("career.progress", in: app), contains: "round:2;")
        assertTablePlayed(1, clubID: "9", in: app)
    }

    func testFullTimeSavesBeforeContinueAndDoesNotRepeatTheRound() {
        let app = launchCareer()
        startCareer(clubID: "1", name: "Liverpool", in: app)
        playShortFixture(in: app)
        attach(app, name: "Career full time with result saved")

        // Terminate on the result screen: committing a result must not depend on
        // the user tapping Continue, and relaunching must not commit it twice.
        app.terminate()
        app.launch()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 10))
        assertValue(element("career.progress", in: app), contains: "round:2;")
        assertTablePlayed(1, clubID: "1", in: app)
        dismissSheet(in: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 10))
        assertValue(element("career.progress", in: app), contains: "round:2;")
        assertTablePlayed(1, clubID: "1", in: app)
    }

    func testLargestTextCareerActionsAndFriendlyNavigationRemainReachable() {
        let app = launchCareer(largeText: true)
        let start = element("career.start", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isHittable)
        attach(app, name: "New career at accessibility XXXL")
        startCareer(clubID: "1", name: "Liverpool", in: app)
        let play = element("career.play", in: app)
        XCTAssertTrue(play.isHittable, "The next fixture action stays reachable at the largest text size")
        attach(app, name: "Career dashboard at accessibility XXXL")
        let lineup = element("career.lineup", in: app)
        reveal(lineup, in: app)
        lineup.tap()
        let done = element("friendly.lineup.done", in: app)
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        done.tap()
        assertTablePlayed(0, clubID: "1", in: app)
        attach(app, name: "Career table at accessibility XXXL")
        dismissSheet(in: app)
        let fixtures = element("career.fixtures", in: app)
        reveal(fixtures, in: app)
        fixtures.tap()
        XCTAssertTrue(app.navigationBars["Fixtures & results"].waitForExistence(timeout: 5))
        attach(app, name: "Career fixtures at accessibility XXXL")
        dismissSheet(in: app)
        selectTab("Friendly", in: app)
        let friendlyKickoff = element("friendly.kickoff", in: app)
        XCTAssertTrue(friendlyKickoff.waitForExistence(timeout: 5))
        XCTAssertTrue(friendlyKickoff.isHittable)
        selectTab("Career", in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        assertValue(element("career.progress", in: app), contains: "round:1;")
        playShortFixture(in: app)
        let next = element("career.continue", in: app)
        reveal(next, in: app)
        attach(app, name: "Career full time at accessibility XXXL")
        next.tap()
        assertValue(element("career.progress", in: app), contains: "round:2;")
    }

    private func launchCareer(largeText: Bool = false, finalMatch: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--premier-league", "--career-ui-testing", "--short-match"]
            + (finalMatch ? ["--career-final-match-ui"] : [])
            + (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launchEnvironment["CAREER_TEST_STORE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(element("career.start", in: app).waitForExistence(timeout: 10))
        return app
    }

    private func startCareer(clubID: String, name: String, in app: XCUIApplication) {
        let choose = element("career.chooseClub", in: app)
        reveal(choose, in: app)
        choose.tap()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText(name)
        }
        let club = element("career.club.\(clubID)", in: app)
        reveal(club, in: app)
        club.tap()
        let start = element("career.start", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(element("career.play", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("career.clubName", in: app).label.contains(name))
    }

    private func playShortFixture(in app: XCUIApplication, controlledClubName: String = "Liverpool") {
        element("career.play", in: app).tap()
        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        assertValue(action, contains: "players:22;")
        XCTAssertTrue(element("match.selected-player", in: app).label.contains(controlledClubName))
        assertValue(action, contains: "restartReady:true;")
        app.buttons["sandbox.pass"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let secondHalf = element("match.second-half", in: app)
        XCTAssertTrue(secondHalf.waitForExistence(timeout: 10))
        secondHalf.tap()
        let next = element("career.continue", in: app)
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertTrue(element("career.result-saved", in: app).waitForExistence(timeout: 5))
        let ready = NSPredicate(format: "enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: next)], timeout: 5), .completed)
        XCTAssertTrue(element("match.results", in: app).exists)
        XCTAssertFalse(element("match.play-again", in: app).exists)
    }

    private func assertTablePlayed(_ played: Int, clubID: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let table = element("career.table", in: app)
        reveal(table, in: app)
        table.tap()
        let row = element("career.table.club.\(clubID)", in: app)
        reveal(row, in: app)
        assertValue(row, contains: "played:\(played);", file: file, line: line)
    }

    private func dismissSheet(in app: XCUIApplication) {
        let done = app.buttons["Done"].firstMatch
        if done.exists {
            done.tap()
        } else {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        XCTAssertTrue(element("career.clubName", in: app).waitForExistence(timeout: 5))
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.exists {
            tab.tap()
        } else {
            let button = app.buttons[title].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<18 {
            guard target.exists else {
                app.swipeUp()
                continue
            }
            let bounds = visibleBounds(for: target, in: app)
            let frame = target.frame
            // XCTest may call a partly covered SwiftUI row hittable even when
            // its tap point lands on the pinned action bar. Keep a clear area
            // around the tap point; large-text panels can be taller than the
            // viewport and need not be completely visible to activate safely.
            let clearance = min(CGFloat(20), frame.height / 2)
            let low = frame.midY - clearance
            let high = frame.midY + clearance
            if target.isHittable && low >= bounds.top && high <= bounds.bottom { return }
            let moveDown = low < bounds.top && high <= bounds.bottom
            let gap = moveDown ? bounds.top - low : high - bounds.bottom
            let distance = min(max(55, gap + 20), max(55, (bounds.bottom - bounds.top) * 0.45))
            let startY = (bounds.top + bounds.bottom) / 2
            let endY = startY + (moveDown ? distance : -distance)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (startY - app.frame.minY) / app.frame.height))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (endY - app.frame.minY) / app.frame.height))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        attach(app, name: "Career control visibility diagnostic")
        print("Career visibility accessibility hierarchy:\n\(app.debugDescription)")
        XCTFail("The requested career control could not be brought clear of navigation and pinned actions", file: file, line: line)
    }

    private func visibleBounds(for target: XCUIElement, in app: XCUIApplication) -> (top: CGFloat, bottom: CGFloat) {
        var top = app.frame.minY + 12
        var bottom = app.frame.maxY - 12
        for bar in app.navigationBars.allElementsBoundByIndex where bar.isHittable {
            top = max(top, bar.frame.maxY + 12)
        }
        for bar in app.tabBars.allElementsBoundByIndex where bar.isHittable {
            if bar.frame.midY > app.frame.midY {
                bottom = min(bottom, bar.frame.minY - 12)
            } else {
                top = max(top, bar.frame.maxY + 12)
            }
        }
        for identifier in ["career.start", "career.play", "career.nextSeason", "friendly.kickoff"] {
            guard identifier != target.identifier else { continue }
            let bar = element(identifier, in: app)
            if bar.exists && bar.isHittable {
                bottom = min(bottom, bar.frame.minY - 20)
            }
        }
        return (top, bottom)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertValue(_ element: XCUIElement, contains token: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@", token)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 7),
                       .completed, "Expected \(token)", file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
