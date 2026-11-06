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

    /// The editor's line is typed on the issue, kept, and (where Apple Intelligence runs) steers the agents' draft.
    @MainActor
    func testEditorsLineIsKeptOnTheIssue() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()

        let card = app.otherElements["deck.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        app.buttons["deck.issue"].tap()
        sleep(1)
        app.buttons["deck.issue"].tap()
        sleep(1)

        app.tabBars.buttons["Shortlist"].tap()
        let open = app.buttons["shortlist.openIssue"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()

        let line = app.textFields["issue.editorLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        line.tap()
        line.typeText("This week: agents that ship")
        app.keyboards.buttons["return"].firstMatch.tap()
        XCTAssertEqual(line.value as? String, "This week: agents that ship")
        attach("01 Editor's line typed")

        let agents = app.buttons["issue.agents"]
        if agents.waitForExistence(timeout: 5) && agents.isEnabled {
            agents.tap()
            expectation(for: NSPredicate(format: "label == %@", "Draft with agents"), evaluatedWith: agents)
            waitForExpectations(timeout: 240)
            sleep(2)
            attach("02 Drafted with the editor's line")
        }
        XCTAssertEqual(line.value as? String, "This week: agents that ship", "the line survives the agents' run")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
