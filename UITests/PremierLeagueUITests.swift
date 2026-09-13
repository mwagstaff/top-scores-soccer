import XCTest
import UIKit

@MainActor
final class PremierLeagueUITests: XCTestCase {
    func testSelectClubsEditLineupAndPlayElevenAside() {
        let app = launchFriendly()
        chooseClub("Arsenal", side: "home", in: app)
        chooseClub("Liverpool", side: "away", in: app)

        element("friendly.home.lineup", in: app).tap()
        let formation = element("friendly.formation", in: app)
        XCTAssertTrue(formation.waitForExistence(timeout: 5))
        formation.tap()
        app.buttons["4–3–3"].firstMatch.tap()

        let defender = element("friendly.lineup.slot.1", in: app)
        XCTAssertTrue(defender.waitForExistence(timeout: 5))
        defender.tap()
        let replacement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "friendly.replacement.")).firstMatch
        let replacementExists = replacement.waitForExistence(timeout: 5)
        if !replacementExists {
            attach(app, name: "Player replacement picker diagnostic")
            print("Player replacement accessibility hierarchy:\n\(app.debugDescription)")
        }
        XCTAssertTrue(replacementExists)
        let replacementName = replacement.label.components(separatedBy: ",")[0]
        replacement.tap()
        XCTAssertTrue(defender.waitForExistence(timeout: 5))
        XCTAssertTrue(defender.label.contains(replacementName), "The selected player should occupy the edited slot")
        element("friendly.lineup.done", in: app).tap()
        XCTAssertTrue(element("friendly.home.lineup", in: app).label.contains("4–3–3"))
        attach(app, name: "Premier League match setup")

        element("friendly.kickoff", in: app).tap()
        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        assertValue(action, contains: "players:22;")
        assertValue(action, contains: "keepers:2;")
        let score = element("sandbox.score", in: app)
        XCTAssertTrue(score.label.localizedCaseInsensitiveContains("Arsenal"))
        XCTAssertTrue(score.label.localizedCaseInsensitiveContains("Liverpool"))
        element("sandbox.pause", in: app).tap()
        XCTAssertTrue(element("sandbox.resume", in: app).waitForExistence(timeout: 5))
        element("sandbox.resume", in: app).tap()
        assertValue(action, contains: "restartReady:true;")
        attach(app, name: "Premier League paired kickoff ready")
        app.buttons["sandbox.pass"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertValue(action, contains: "kicks:1;")
        attach(app, name: "Premier League eleven-a-side live pitch")
        element("sandbox.pause", in: app).tap()
        element("sandbox.exit", in: app).tap()
        XCTAssertTrue(element("friendly.kickoff", in: app).waitForExistence(timeout: 5))
    }

    func testLargestTextKeepsSetupAndLineupActionsReachable() {
        let app = launchFriendly(largeText: true)
        let kickoff = element("friendly.kickoff", in: app)
        XCTAssertTrue(kickoff.isHittable, "Kick off remains pinned above the bottom safe area")
        attach(app, name: "Premier League setup at accessibility XXXL")
        let lineup = element("friendly.home.lineup", in: app)
        for _ in 0..<6 where !lineup.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(lineup.isHittable)
        lineup.tap()
        let done = element("friendly.lineup.done", in: app)
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        XCTAssertTrue(element("friendly.formation", in: app).exists)
        attach(app, name: "Premier League lineup at accessibility XXXL")
        done.tap()
        XCTAssertTrue(kickoff.waitForExistence(timeout: 5))
        XCTAssertTrue(kickoff.isHittable)
    }

    func testDistinctClubsAndFullTimeReturnToSelection() {
        let app = launchFriendly(short: true)
        chooseClub("Arsenal", side: "home", in: app)
        element("friendly.away.club", in: app).tap()
        let arsenal = app.buttons.matching(NSPredicate(format: "label == %@", "Arsenal")).firstMatch
        XCTAssertTrue(arsenal.waitForExistence(timeout: 5))
        XCTAssertFalse(arsenal.isEnabled, "The two sides must be different clubs")
        app.buttons["Cancel"].firstMatch.tap()

        element("friendly.kickoff", in: app).tap()
        let action = element("sandbox.action", in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        assertValue(action, contains: "restartReady:true;")
        app.buttons["sandbox.pass"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let secondHalf = element("match.second-half", in: app)
        XCTAssertTrue(secondHalf.waitForExistence(timeout: 10))
        secondHalf.tap()
        XCTAssertTrue(element("match.results", in: app).waitForExistence(timeout: 12))
        XCTAssertEqual(element("match.clock", in: app).label, "2nd half, time remaining 0:00")
        attach(app, name: "Premier League full time")
        element("match.choose-clubs", in: app).tap()
        XCTAssertTrue(element("friendly.kickoff", in: app).waitForExistence(timeout: 5))
    }

    private func launchFriendly(short: Bool = false, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--premier-league"] + (short ? ["--short-match"] : [])
            + (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
        XCTAssertTrue(element("friendly.kickoff", in: app).waitForExistence(timeout: 10))
        return app
    }

    private func chooseClub(_ name: String, side: String, in app: XCUIApplication) {
        element("friendly.\(side).club", in: app).tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(name)
        let club = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@", "friendly.club.", name)).firstMatch
        XCTAssertTrue(club.waitForExistence(timeout: 5))
        club.tap()
        let selection = element("friendly.\(side).club", in: app)
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        XCTAssertTrue(selection.label.contains(name))
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
