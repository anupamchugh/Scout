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
        app.launch()

        let card = app.otherElements["deck.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90))
        sleep(8) // let avatars and the on-device "why" line arrive
        shoot("01-today-deck")

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
        sleep(6)
        shoot("04-issue-editor")
        app.buttons["issue.preview"].tap()
        sleep(2)
        shoot("05-issue-preview")
        app.buttons["preview.done"].tap()

        app.tabBars.buttons["Search"].tap()
        sleep(3)
        shoot("06-search")
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("writing about actors and async code")
            sleep(5)
            shoot("07-search-query")
        }
    }

    @MainActor
    func testSiriCardStage() throws {
        try XCTSkipIf(folder == nil, "SCOUT_SCREENSHOT_DIR not set")
        let app = XCUIApplication()
        app.launchArguments = ["-siriCardStage"]
        app.launch()
        XCTAssertTrue(app.buttons["Open deck"].waitForExistence(timeout: 90))
        shoot("08-siri-card-stage")
    }
}
