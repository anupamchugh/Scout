//
//  DemoTour.swift
//  ScoutUITests
//
//  The README demo: the whole flow on fictional demo writers, paced for a screen recording.
//  Runs only when SCOUT_SCREENSHOT_DIR is set (TEST_RUNNER_SCOUT_SCREENSHOT_DIR=<folder> for xcodebuild).
//

import XCTest

final class DemoTour: XCTestCase {

    private var folder: URL? {
        ProcessInfo.processInfo.environment["SCOUT_SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    @MainActor
    private func shoot(_ name: String) {
        guard let folder else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("demo-\(name).png"))
    }

    @MainActor
    func testDemo() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-pack", "engineering-editor", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // Today: the deck of writers, ranked in code.
        let card = app.otherElements["deck.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        // Wait for the on-device "why" line (code hides it if it fails a check, so this may not appear).
        _ = card.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "why this writer")).firstMatch
            .waitForExistence(timeout: 45)
        sleep(2)
        shoot("01-today")
        card.swipeRight()
        sleep(2)
        app.buttons["deck.issue"].tap()
        sleep(2)
        app.buttons["deck.shortlist"].tap()
        sleep(2)
        app.segmentedControls["today.mode"].buttons["Stories"].tap()
        sleep(4)
        shoot("02-stories")
        app.buttons["deck.issue"].tap()
        sleep(2)
        app.buttons["deck.issue"].tap()
        sleep(2)

        // Shortlist: outreach notes drafted on device, checked in code.
        app.tabBars.buttons["Shortlist"].tap()
        // Outreach notes draft on device; wait until the first note has text.
        let copy = app.buttons["Copy note"].firstMatch
        if copy.waitForExistence(timeout: 10) {
            expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: copy)
            waitForExpectations(timeout: 90)
        }
        sleep(4)
        shoot("03-shortlist")

        // Issue: newsletter agents (Curator, Blurber, Spotlight, Editor), then a code checker.
        app.buttons["shortlist.openIssue"].firstMatch.tap()
        sleep(2)
        let agents = app.buttons["issue.agents"]
        if agents.waitForExistence(timeout: 5) && agents.isEnabled {
            agents.tap()
            expectation(for: NSPredicate(format: "label == %@", "Draft with agents"), evaluatedWith: agents)
            waitForExpectations(timeout: 240)
        }
        sleep(2)
        shoot("04-issue")
        app.swipeUp()
        sleep(2)
        shoot("05-issue-agents")
        app.buttons["issue.preview"].tap()
        sleep(3)
        shoot("06-issue-preview")
        app.buttons["preview.done"].tap()
        sleep(1)

        // Search: potential tags beside your lanes, and every tag Scout has seen.
        app.tabBars.buttons["Search"].tap()
        sleep(3)
        shoot("07-search-tags")
        app.buttons["search.catalog"].tap()
        sleep(2)
        shoot("08-tag-catalog")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)

        // Any topic in plain words becomes a lane of checked tags.
        app.tabBars.buttons["Today"].tap()
        sleep(1)
        app.buttons["today.lanePicker"].tap()
        app.buttons["New topic…"].tap()
        let field = app.textFields["topic.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("blogging and newsletters\n")
        let add = app.buttons["topic.add"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: add)
        waitForExpectations(timeout: 90)
        sleep(3)
        shoot("09-new-topic")
        add.tap()
        sleep(6)
        shoot("10-topic-lane")
    }

    @MainActor
    func testSiriCard() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-siriCardStage", "-pack", "engineering-editor", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["Open deck"].waitForExistence(timeout: 60))
        sleep(2)
        shoot("11-siri-card")
    }
}
