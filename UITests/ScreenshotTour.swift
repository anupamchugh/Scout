//
//  ScreenshotTour.swift
//  ScoutUITests
//
//  Drives the app on live RSS data and saves screenshots. Runs only when SCOUT_SCREENSHOT_DIR is set
//  (pass TEST_RUNNER_SCOUT_SCREENSHOT_DIR=<folder> to xcodebuild).
//

import XCTest

final class ScreenshotTour: XCTestCase {

    private var folder: URL? {
        ProcessInfo.processInfo.environment["SCOUT_SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    @MainActor
    private func shoot(_ name: String) {
        guard let folder else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testTour() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-pack", "engineering-editor"]
        app.launch()

        let card = app.otherElements["deck.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90))
        sleep(8) // let avatars and the on-device "why" line arrive
        shoot("01-today-deck")

        app.segmentedControls["today.mode"].buttons["Stories"].tap()
        sleep(6)
        shoot("01b-today-stories")

        app.buttons["today.lanePicker"].tap()
        sleep(1)
        shoot("12-lane-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.55)).tap()
        sleep(1)

        app.segmentedControls["today.mode"].buttons["Writers"].tap()
        sleep(1)
        app.buttons["card.ask"].firstMatch.tap()
        let why = app.buttons["ask.chip.Why this writer?"]
        if why.waitForExistence(timeout: 5) {
            why.tap()
            _ = app.staticTexts["On-device model"].waitForExistence(timeout: 45)
        }
        app.buttons["ask.chip.What else did they write?"].tap()
        sleep(2)
        shoot("13-ask-sheet")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)

        card.swipeRight()
        sleep(2)
        app.buttons["deck.shortlist"].tap()
        sleep(2)
        app.buttons["deck.issue"].tap()
        sleep(2)
        app.buttons["deck.issue"].tap()
        sleep(4)
        shoot("02-today-after-swipes")

        app.tabBars.buttons["Shortlist"].tap()
        sleep(12) // outreach notes draft on device
        shoot("03-shortlist")

        app.buttons["shortlist.openIssue"].firstMatch.tap()
        sleep(4)
        let agents = app.buttons["issue.agents"]
        if agents.waitForExistence(timeout: 5) && agents.isEnabled {
            agents.tap()
            let done = NSPredicate(format: "label == %@", "Draft with agents")
            expectation(for: done, evaluatedWith: agents)
            waitForExpectations(timeout: 240)
            sleep(2)
        }
        shoot("04-issue-editor")
        app.swipeUp()
        sleep(1)
        shoot("04b-issue-agents")
        app.swipeUp()
        sleep(1)
        shoot("04c-issue-spotlight")
        app.buttons["issue.preview"].tap()
        sleep(2)
        shoot("05-issue-preview")
        app.buttons["preview.done"].tap()

        app.tabBars.buttons["Search"].tap()
        sleep(3)
        shoot("06-search")
        let catalog = app.buttons["search.catalog"]
        if catalog.waitForExistence(timeout: 5) {
            catalog.tap()
            sleep(2)
            shoot("06b-tag-catalog")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("writing about actors and async code")
            sleep(5)
            shoot("07-search-query")
        }
    }

    /// The same app in Hindi: catalog strings in hi, model text in Hindi where the on-device model supports it.
    @MainActor
    func testHindi() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(hi)", "-AppleLocale", "hi_IN", "-pack", "engineering-editor"]
        app.launch()
        XCTAssertTrue(app.otherElements["deck.card"].firstMatch.waitForExistence(timeout: 90))
        sleep(8)
        shoot("09-today-hindi")
        app.terminate()
        app.launchArguments += ["-tab", "search"]
        app.launch()
        sleep(6)
        shoot("10-search-hindi")
    }

    /// Any topic in plain words becomes a lane: the model suggests tags, Scout keeps those with live Medium feeds.
    @MainActor
    func testNewTopic() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-pack", "engineering-editor"]
        app.launch()
        XCTAssertTrue(app.otherElements["deck.card"].firstMatch.waitForExistence(timeout: 90))
        app.buttons["today.lanePicker"].tap()
        app.buttons["New topic…"].tap()
        let field = app.textFields["topic.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("blogging and newsletters")
        app.buttons["topic.find"].tap()
        let add = app.buttons["topic.add"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: add)
        waitForExpectations(timeout: 90)
        sleep(1)
        shoot("15-new-topic-tags")
        add.tap()
        sleep(10)
        shoot("16-topic-lane-deck")
    }

    @MainActor
    func testSiriCardStage() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-siriCardStage", "-pack", "engineering-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["Open deck"].waitForExistence(timeout: 90))
        shoot("08-siri-card-stage")
    }

    @MainActor
    func testPacks() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-choosePack"]
        app.launch()
        XCTAssertTrue(app.buttons["pack.illustrator"].waitForExistence(timeout: 20))
        sleep(1)
        shoot("09-pack-picker")
        app.buttons["pack.illustrator"].tap()

        app.segmentedControls["today.mode"].buttons["Stories"].tap()
        let appeared = app.otherElements["deck.card"].firstMatch.waitForExistence(timeout: 90)
        if !appeared { shoot("debug-illustrator") }
        XCTAssertTrue(appeared)
        sleep(8)
        shoot("10-illustrator-stories")

        app.buttons["deck.shortlist"].tap()
        sleep(2)
        app.buttons["today.packChip"].tap()
        sleep(2)
        shoot("11-settings-pack-taste")
    }

    @MainActor
    func testHackerNews() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-pack", "engineering-editor", "-lane", "Show HN builders", "-stories"]
        app.launch()
        XCTAssertTrue(app.otherElements["deck.card"].firstMatch.waitForExistence(timeout: 90))
        sleep(6)
        shoot("14-hn-story")

        let brief = app.buttons["hn.threadBrief"].firstMatch
        if brief.waitForExistence(timeout: 5) {
            brief.tap()
            _ = app.staticTexts["Arguments in the comments"].waitForExistence(timeout: 240)
            sleep(1)
            shoot("16-thread-brief")
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }

        app.segmentedControls["today.mode"].buttons["Writers"].tap()
        XCTAssertTrue(app.otherElements["deck.card"].firstMatch.waitForExistence(timeout: 30))
        sleep(10)
        shoot("15-hn-person")
    }

    @MainActor
    func testReader() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-pack", "engineering-editor", "-lane", "Swift concurrency", "-stories"]
        app.launch()
        XCTAssertTrue(app.otherElements["deck.card"].firstMatch.waitForExistence(timeout: 90))
        // Find a story whose article has a code block: open, look, close, pass, up to six stories.
        for _ in 0..<6 {
            app.descendants(matching: .any)["card.title"].firstMatch.tap()
            sleep(6)
            if app.descendants(matching: .any)["reader.code"].firstMatch.exists || app.scrollViews.firstMatch.otherElements["reader.code"].exists {
                shoot("17-reader")
                let code = app.descendants(matching: .any)["reader.code"].firstMatch
                for _ in 0..<12 where !code.isHittable { app.swipeUp() }
                sleep(1)
                shoot("17b-reader-code")
                return
            }
            for _ in 0..<10 { app.swipeUp() }
            if app.descendants(matching: .any)["reader.code"].firstMatch.exists {
                shoot("17b-reader-code")
                app.buttons["Done"].firstMatch.tap()
                return
            }
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
            app.buttons["deck.pass"].tap()
            sleep(2)
        }
        app.descendants(matching: .any)["card.title"].firstMatch.tap()
        sleep(6)
        shoot("17-reader")
    }
}
