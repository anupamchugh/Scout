//
//  StoreTests.swift
//  ScoutTests
//
//  Tests that need the app's SwiftData store or model sessions; pure logic is tested in ScoutKit.
//

import Foundation
import ScoutKit
import SwiftData
import Testing
@testable import Scout

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func item(_ guid: String, link: String, tags: [String]) -> FeedItem {
    FeedItem(guid: guid, title: "Title \(guid)", link: URL(string: link)!, creator: "Writer",
             published: now, categories: tags, snippet: "Snippet")
}

@MainActor
struct DedupeTests {

    @Test func sameStoryFromTwoTagFeedsBecomesOnePost() throws {
        let container = ScoutStore.make(inMemory: true)
        let context = container.mainContext
        let post = item("https://medium.com/p/abc", link: "https://medium.com/@w/story-abc?source=rss------swift-5",
                        tags: ["swift", "concurrency"])
        var report = FeedClient.Report()
        report.items[.tag("swift")] = [post]
        report.items[.tag("concurrency")] = [post]
        try Ingest.upsert(report, into: context, now: now)

        let stored = try context.fetch(FetchDescriptor<StoredPost>())
        #expect(stored.count == 1)
        #expect(Set(stored[0].foundUnder) == ["swift", "concurrency"])
        #expect(Set(stored[0].categories) == ["swift", "concurrency"])
        #expect(stored[0].link == "https://medium.com/@w/story-abc")
    }

    @Test func differentGuidSameCanonicalLinkMerges() throws {
        let container = ScoutStore.make(inMemory: true)
        let context = container.mainContext
        var first = FeedClient.Report()
        first.items[.tag("swift")] = [item("guid-1", link: "https://medium.com/@w/story?source=a", tags: ["swift"])]
        try Ingest.upsert(first, into: context, now: now)
        var second = FeedClient.Report()
        second.items[.tag("ios")] = [item("guid-2", link: "https://medium.com/@w/story?source=b", tags: ["ios"])]
        try Ingest.upsert(second, into: context, now: now)

        let stored = try context.fetch(FetchDescriptor<StoredPost>())
        #expect(stored.count == 1)
        #expect(Set(stored[0].foundUnder) == ["swift", "ios"])
        #expect(Set(stored[0].categories) == ["swift", "ios"])
    }
}

struct ProfileTests {
    @Test func eachModeAndPackGetsItsOwnInstructions() {
        let visual = ScoutProfile.roleInstructions(pack: .illustrator, mode: .scouting)
        #expect(visual.contains("Never describe the artist as a person"))
        #expect(ScoutProfile.roleInstructions(pack: .engineering, mode: .scouting).contains("recentPosts"))
        #expect(ScoutProfile.roleInstructions(pack: .techWriter, mode: .issueWriting).contains(RolePack.techWriter.outreachStyle))
        #expect(ScoutMode.issueWriting.options.temperature == 0.6)
    }

    @Test func hackerNewsPostsAreCreditedToTheirSite() throws {
        let item = FeedItem(guid: "https://news.ycombinator.com/item?id=1", title: "Show HN: A tiny tool",
                            link: URL(string: "https://example.com/tool")!, creator: "", published: now,
                            categories: [], snippet: "")
        #expect(Ingest.author(item, .feed(URL(string: "https://news.ycombinator.com/rss")!)) == "example.com")
    }
}
