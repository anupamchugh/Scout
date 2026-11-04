//
//  DeckUITests.swift
//  ScoutUITests
//

import XCTest

final class DeckUITests: XCTestCase {

    @MainActor
    func testSwipeRightShortlistsAndShowsInShortlist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()

        let card = app.otherElements["deck.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let count = app.staticTexts["today.shortlistCount"]
        XCTAssertEqual(count.label, "0 shortlisted")

        card.swipeRight()
        let updated = NSPredicate(format: "label == %@", "1 shortlisted")
        expectation(for: updated, evaluatedWith: count)
        waitForExpectations(timeout: 5)

        app.buttons["deck.shortlist"].tap()
        expectation(for: NSPredicate(format: "label == %@", "2 shortlisted"), evaluatedWith: count)
        waitForExpectations(timeout: 5)

        app.tabBars.buttons["Shortlist"].tap()
        XCTAssertTrue(app.staticTexts["Sample Writer A"].waitForExistence(timeout: 5)
                      || app.staticTexts["Sample Writer B"].waitForExistence(timeout: 1))
    }
}
