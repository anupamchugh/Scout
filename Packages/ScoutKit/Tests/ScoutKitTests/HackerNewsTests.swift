//
//  HackerNewsTests.swift
//  ScoutKitTests
//
//  Fixture: a public HN user's record and 30 most recent items from the official API, 2026-11-05.
//  Keep it in the private repo unless the owner approves publishing it.
//

import Foundation
import Testing
@testable import ScoutKit

private struct Fixture: Decodable {
    let user: HNUser
    let items: [HNItem]
}

struct HackerNewsTests {

    private func fixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "hn-user-2026-11-05", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func statsComeFromCode() throws {
        let data = try fixture()
        let stats = HNStats.stats(user: data.user, items: data.items)
        #expect(stats.user == "daniel_rh")
        #expect(stats.stories == 3)
        #expect(stats.comments == 27)
        #expect(stats.showHN == 2)
        #expect(stats.topDomains.first?.domain == "fireflyk64.github.io")
        #expect(stats.topDomains.first?.count == 2)
        #expect(stats.medianPoints == 5)
        #expect(stats.medianComments == 4)
        #expect(Array(stats.titleWords.prefix(3).map(\.word)) == ["commander", "reversing", "wing"])
        #expect(abs(stats.submissionsPerWeek - 0.092) < 0.01)
    }

    @Test func threadPromptNeverNamesCommenters() {
        let story = HNItem(id: 1, type: "story", by: "poster", time: 0, title: "Show HN: A tool", text: nil, url: "https://x.dev",
                           kids: [2], deleted: nil, dead: nil, score: 10, descendants: 1)
        let comment = HNItem(id: 2, type: "comment", by: "commenter_name", time: 0, title: nil, text: "<p>Nice &amp; fast</p>",
                             url: nil, kids: nil, deleted: nil, dead: nil, score: nil, descendants: nil)
        let prompt = ThreadBriefService<SessionTransport>.prompt(for: HNThread(story: story, comments: [comment]))
        #expect(!prompt.contains("commenter_name"))
        #expect(!prompt.contains("poster"))
        #expect(prompt.contains("Nice & fast"))
    }

    @Test func itemIDsComeFromCommentLinks() {
        #expect(HackerNewsLink.itemID(from: "https://news.ycombinator.com/item?id=50371246") == 50371246)
        #expect(HackerNewsLink.itemID(from: "https://example.com/item?id=1") == nil)
    }

    @Test func cleanerHandlesHNHTML() {
        #expect(HNTextCleaner.plainText(fromHTML: "I build tools.<p>Mostly <i>Swift</i> &amp; Rust.") == "I build tools. Mostly Swift & Rust.")
    }
}
