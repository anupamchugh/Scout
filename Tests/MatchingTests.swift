//
//  MatchingTests.swift
//  ScoutTests
//

import Foundation
import Testing
@testable import Scout

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let lane = LaneSpec(name: "Swift concurrency", tags: ["swift", "concurrency", "ios"], theme: "Swift concurrency")

private func post(_ guid: String, _ author: String, tags: [String], hoursAgo: Double, minutes: Int? = nil) -> PostRecord {
    PostRecord(guid: guid, title: "Title \(guid)", link: "https://medium.com/@\(author)/\(guid)", snippet: "Snippet \(guid)",
               authorKey: author, authorName: author.capitalized, handle: author, categories: tags, foundUnder: [],
               published: now.addingTimeInterval(-hoursAgo * 3600), readingMinutes: minutes)
}

struct MatchingTests {

    @Test func scoreIsAWeightedBlendInCode() {
        let perfect = MatchSignals(semantic: 1, overlap: 1, postsInWindow: 3, hoursSinceLatest: 0)
        #expect(Matching.score(perfect) == 100)
        let none = MatchSignals(semantic: 0, overlap: 0, postsInWindow: 0, hoursSinceLatest: 10_000)
        #expect(Matching.score(none) == 0)
        let half = MatchSignals(semantic: 0.5, overlap: 0.5, postsInWindow: 0, hoursSinceLatest: 10_000)
        #expect(Matching.score(half) == 33)
    }

    @Test func overlapCountsUpToThreeLaneTags() {
        #expect(Matching.overlap(["swift"], lane: lane.tags) == 1.0 / 3)
        #expect(Matching.overlap(["swift", "ios", "concurrency", "x"], lane: lane.tags) == 1)
        #expect(Matching.overlap(["rust"], lane: lane.tags) == 0)
    }

    @Test func candidatesOrderedByScoreThenRecency() {
        let posts = [
            post("1", "frequent", tags: ["swift", "concurrency"], hoursAgo: 5),
            post("2", "frequent", tags: ["swift"], hoursAgo: 20),
            post("3", "frequent", tags: ["ios"], hoursAgo: 40),
            post("4", "offtopic", tags: ["rust"], hoursAgo: 1),
            post("5", "once", tags: ["swift"], hoursAgo: 2),
            post("6", "old", tags: ["swift", "concurrency", "ios"], hoursAgo: 400),
        ]
        let ranked = Matching.candidates(from: posts, lane: lane, semantic: ["once": 0.2], excluding: [],
                                         now: now, window: 7 * 86_400)
        #expect(ranked.map(\.authorKey) == ["frequent", "once", "offtopic"])
        #expect(ranked[0].signals.postsInWindow == 3)
        #expect(ranked[0].bestPost.guid == "1")
    }

    @Test func decidedAndBlockedWritersAreExcluded() {
        let posts = [post("1", "a", tags: ["swift"], hoursAgo: 1), post("2", "b", tags: ["swift"], hoursAgo: 1)]
        let ranked = Matching.candidates(from: posts, lane: lane, semantic: [:], excluding: ["a"], now: now, window: 86_400)
        #expect(ranked.map(\.authorKey) == ["b"])
    }

    @Test func bestPostPrefersOnTopicThenLonger() {
        let posts = [post("short", "a", tags: ["swift"], hoursAgo: 1, minutes: 3),
                     post("long", "a", tags: ["swift"], hoursAgo: 9, minutes: 12),
                     post("off", "a", tags: ["cooking"], hoursAgo: 0, minutes: 30)]
        #expect(Matching.bestPost(posts, lane: lane)?.guid == "long")
    }
}

extension MatchingTests {
    @Test func publicationPostsJoinTheWritersHandle() {
        var pub = post("p", "x", tags: ["swift"], hoursAgo: 1)
        pub.handle = nil
        pub.authorKey = "name:Writer"
        pub.authorName = "Writer"
        var known = post("k", "writer", tags: ["swift"], hoursAgo: 2)
        known.authorName = "Writer"
        let unified = Matching.unifyAuthors([pub, known])
        #expect(unified.map(\.authorKey) == ["writer", "writer"])
        let ranked = Matching.candidates(from: [pub, known], lane: lane, semantic: [:], excluding: [], now: now, window: 86_400)
        #expect(ranked.count == 1)
        #expect(ranked[0].signals.postsInWindow == 2)
    }
}

struct TextGuardTests {
    @Test func modelTextMayNotContainDigitsOrLinks() {
        #expect(TextGuard.isClean("Writes clearly about actor isolation."))
        #expect(!TextGuard.isClean("Has written 40 posts on Swift."))
        #expect(!TextGuard.isClean("Read more at https://example.com"))
        #expect(!TextGuard.isClean("See medium.com for details"))
        #expect(!TextGuard.isClean("   "))
    }

    @Test func evidenceMustBeQuoted() {
        let source = "Capping concurrency in a task group. A walk through actor isolation."
        #expect(TextGuard.quotes("actor isolation", from: source))
        #expect(TextGuard.quotes("Capping  CONCURRENCY in a task", from: source))
        #expect(!TextGuard.quotes("thousands of claps", from: source))
        #expect(!TextGuard.quotes("actor", from: source))
    }
}
