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

@MainActor
struct TagCatalogStoreTests {

    /// Each post counts once, however many tag feeds surfaced it; potential tags come from what shared posts.
    @Test func ingestFillsTheCatalogOncePerPost() throws {
        let container = ScoutStore.make(inMemory: true)
        let context = container.mainContext
        let shared = item("https://medium.com/p/1", link: "https://medium.com/@a/one", tags: ["ai", "rag", "llm"])
        var report = FeedClient.Report()
        report.items[.tag("ai")] = [shared, item("https://medium.com/p/2", link: "https://medium.com/@b/two", tags: ["ai", "rag"])]
        report.items[.tag("rag")] = [shared]
        report.items[.author("c")] = [item("https://medium.com/p/3", link: "https://medium.com/@c/three",
                                           tags: ["engineering-management", "programming"])]
        try Ingest.upsert(report, into: context, now: now)

        let records = Dictionary(uniqueKeysWithValues: TagCatalogStore.all(context).map { ($0.tag, $0) })
        #expect(records["ai"]?.postCount == 2)
        #expect(records["rag"]?.postCount == 2)
        #expect(records["engineering-management"]?.postCount == 1, "a writer's own feed adds its tags too")
        #expect(records["ai"]?.neighbours["rag"] == 2)

        let potential = TagCatalogStore.potential(for: ["ai"], in: context)
        #expect(potential.map(\.tag) == ["rag"], "llm shared only one post, under the minimum of two")
    }

    @Test func backfillBuildsTheCatalogFromStoredPosts() throws {
        let container = ScoutStore.make(inMemory: true)
        let context = container.mainContext
        context.insert(StoredPost(guid: "g", title: "T", link: "https://medium.com/@w/t", authorName: "W", authorKey: "w",
                                  handle: "w", snippet: "", categories: ["swift", "ios"], foundUnder: ["swift"],
                                  published: now, firstSeen: now, readingMinutes: nil, imageURL: nil))
        try TagCatalogStore.backfillIfEmpty(context)
        #expect(TagCatalogStore.all(context).map(\.tag).sorted() == ["ios", "swift"])
        try TagCatalogStore.backfillIfEmpty(context)
        #expect(TagCatalogStore.all(context).first { $0.tag == "swift" }?.postCount == 1, "a second backfill is a no-op")
    }
}
