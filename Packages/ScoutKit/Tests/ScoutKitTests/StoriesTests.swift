//
//  StoriesTests.swift
//  ScoutKitTests
//

import Foundation
import Testing
@testable import ScoutKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let swiftLane = LaneSpec(name: "Swift", tags: ["swift", "concurrency", "ios"], theme: "Swift")
private let aiLane = LaneSpec(name: "AI", tags: ["llm", "rag"], theme: "AI")
private let webLane = LaneSpec(name: "Web", tags: ["javascript"], theme: "Web")

private func item(_ guid: String, link: String, tags: [String]) -> FeedItem {
    FeedItem(guid: guid, title: "Title \(guid)", link: URL(string: link)!, creator: "Writer",
             published: now, categories: tags, snippet: "Snippet")
}

private func story(_ guid: String, tags: [String], foundUnder: [String], hoursAgo: Double = 1) -> PostRecord {
    PostRecord(guid: guid, title: "Title \(guid)", link: "https://medium.com/@w/\(guid)", snippet: "", authorKey: "w\(guid)",
               authorName: "W\(guid)", handle: "w\(guid)", categories: tags, foundUnder: foundUnder,
               published: now.addingTimeInterval(-hoursAgo * 3600), readingMinutes: nil)
}

struct StoryScoringTests {

    @Test func lanesSurfacingCountsLanesWhoseFeedsListedThePost() {
        let post = story("1", tags: ["swift", "llm", "javascript"], foundUnder: ["swift", "rag", "javascript"])
        #expect(Matching.lanesSurfacing(post, lanes: [swiftLane, aiLane, webLane]) == 3)
        #expect(Matching.lanesSurfacing(story("2", tags: [], foundUnder: ["rust"]), lanes: [swiftLane, aiLane]) == 0)
    }

    @Test func storiesOrderByTagOverlapThenSurfacingThenRecency() {
        let posts = [
            story("one-tag", tags: ["swift"], foundUnder: ["swift"]),
            story("three-tags", tags: ["swift", "concurrency", "ios"], foundUnder: ["swift"]),
            story("multi-lane", tags: ["swift"], foundUnder: ["swift", "rag", "javascript"]),
            story("off", tags: ["cooking"], foundUnder: ["cooking"]),
            story("old", tags: ["swift", "concurrency", "ios"], foundUnder: ["swift"], hoursAgo: 500),
        ]
        let ranked = Matching.stories(from: posts, lane: swiftLane, lanes: [swiftLane, aiLane, webLane], semantic: [:],
                                      excluding: [], now: now, window: 7 * 86_400)
        #expect(ranked.map(\.id) == ["three-tags", "multi-lane", "one-tag", "off"])
        #expect(ranked[0].overlapCount == 3)
        #expect(ranked[1].lanesSurfacing == 3)
    }

    @Test func pickedStoriesAndBlockedWritersAreExcluded() {
        let posts = [story("a", tags: ["swift"], foundUnder: ["swift"]), story("b", tags: ["swift"], foundUnder: ["swift"])]
        let ranked = Matching.stories(from: posts, lane: swiftLane, lanes: [swiftLane], semantic: [:],
                                      excluding: ["a", "wb"], now: now, window: 86_400)
        #expect(ranked.isEmpty)
    }
}

struct TagCooccurrenceTests {

    @Test func countsEachPairOncePerPost() {
        let posts = [
            story("1", tags: ["swift", "concurrency", "ios"], foundUnder: []),
            story("2", tags: ["swift", "concurrency", "swift"], foundUnder: []),
            story("3", tags: ["llm", "rag"], foundUnder: []),
            story("4", tags: ["rag", "llm"], foundUnder: []),
            story("5", tags: ["concurrency", "swift"], foundUnder: []),
        ]
        let counts = TagCooccurrence.count(posts)
        #expect(counts.first?.pair == TagPair("swift", "concurrency"))
        #expect(counts.first?.count == 3)
        #expect(counts.first { $0.pair == TagPair("rag", "llm") }?.count == 2)
        #expect(counts.first { $0.pair == TagPair("ios", "swift") }?.count == 1)
        #expect(TagPair("b", "a").label == "a + b")
    }

    @Test func suggestionsSkipPairsALaneAlreadyCovers() {
        let posts = (0..<4).map { story("\($0)", tags: ["swift", "concurrency", "llm", "rag"], foundUnder: []) }
        let suggested = TagCooccurrence.suggestions(posts, existing: [["swift", "concurrency", "ios"]], minimum: 3, limit: 2)
        #expect(suggested.map(\.pair.label) == ["concurrency + llm", "concurrency + rag"])
    }
}

struct AuthorStatsTests {

    /// salari-dev.medium.com/feed as fetched on 2026-11-05 (10 posts, 14 Oct to 4 Nov 2026).
    private func fixture() throws -> [FeedItem] {
        let url = try #require(Bundle.module.url(forResource: "salari-dev-2026-11-05", withExtension: "xml", subdirectory: "Fixtures"))
        return try RSSParser.parse(Data(contentsOf: url))
    }

    @Test func realFeedStats() throws {
        let posts = try fixture()
        let result = stats(for: posts)
        #expect(result.postCount == 10)
        #expect(abs(result.postsPerWeek - 3.3) < 0.15)
        #expect(Array(result.topTags.prefix(3).map(\.tag)) == ["ios-development", "swift", "ios-interview-question"])
        #expect(Array(result.topTags.prefix(3).map(\.count)) == [6, 6, 4])
        #expect(abs((result.typicalWords ?? 0) - 1100) < 60)
        #expect(result.titlePatterns[.mythThenFact] == 3)
        #expect(result.titlePatterns[.youYour] == 3)
        #expect(result.titlePatterns[.comparison] == 2)
        #expect((result.titlePatterns[.fixHowTo] ?? 0) + (result.titlePatterns[.careerGuide] ?? 0) == 2)
    }

    @Test func titleRules() {
        #expect(TitlePattern.classify("Your backlog needs criteria") == .youYour)
        #expect(TitlePattern.classify("SwiftUI vs UIKit") == .comparison)
        #expect(TitlePattern.classify("Why the crash happens and how to fix it") == .fixHowTo)
        #expect(TitlePattern.classify("From junior to senior: what you need to learn") == .careerGuide)
        #expect(TitlePattern.classify("Swift 6 rejected the race. ARC stayed atomic.") == .mythThenFact)
        #expect(TitlePattern.classify("A prefix tree in Swift") == .plain)
    }

    @Test func modelNeverSeesTheCardNumbersAsItsOwn() {
        let result = AuthorStats(postCount: 2, postsPerWeek: 1.5, typicalWords: 900, topTags: [("swift", 2)],
                                 titlePatterns: [.youYour: 2])
        #expect(result.leadingPatterns == [.youYour])
        #expect(result.typicalReadingMinutes == 4)
    }
}

