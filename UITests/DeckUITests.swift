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
        let names = ["Mara Quill", "Theo Lantern", "Iris Fernhall", "Juno Ashby", "Ola Brightwater", "Felix Marrow", "Wren Calloway"]
        let shortlisted = app.staticTexts.matching(NSPredicate(format: "label IN %@", names)).firstMatch
        XCTAssertTrue(shortlisted.waitForExistence(timeout: 5))
    }
}
