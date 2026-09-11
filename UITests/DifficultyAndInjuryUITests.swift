import XCTest

@MainActor
final class DifficultyAndInjuryUITests: XCTestCase {
    func testDifficultyPickerOffersAllLevelsAndRestoresMedium() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let settings = app.buttons["sandbox.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let picker = app.descendants(matching: .any).matching(identifier: "settings.difficulty").firstMatch
        for _ in 0..<6 where !(picker.exists && picker.isHittable) { app.swipeUp() }
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        for level in ["Easy", "Hard", "Medium"] {
            picker.tap()
            let option = app.buttons[level]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            XCTAssertTrue(picker.label.contains(level) || (picker.value as? String)?.contains(level) == true)
        }
        capture(app, "Difficulty settings")
        app.buttons["settings.done"].tap()
    }

    func testInjuryRequiresSquadChoiceAndReturnsToFreeKick() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--free-kick", "--injury"]
        app.launch()
        let injury = app.descendants(matching: .any).matching(identifier: "injury.player").firstMatch
        XCTAssertTrue(injury.waitForExistence(timeout: 15))
        let replacement = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "injury.replace.")).firstMatch
        for _ in 0..<6 where !(replacement.exists && replacement.isHittable) { app.swipeUp() }
        XCTAssertTrue(replacement.waitForExistence(timeout: 5))
        XCTAssertTrue(replacement.isHittable)
        capture(app, "Injury squad replacement")
        app.swipeDown()
        XCTAssertTrue(injury.exists, "The compulsory replacement cannot be dismissed by swiping")
        for _ in 0..<6 where !(replacement.exists && replacement.isHittable) { app.swipeUp() }
        replacement.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: injury)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        let status = app.staticTexts["sandbox.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("FREE KICK"))
        capture(app, "Play resumes after substitution")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
