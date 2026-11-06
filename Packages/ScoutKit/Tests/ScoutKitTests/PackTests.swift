//
//  PackTests.swift
//  ScoutKitTests
//

import Foundation
import Testing
@testable import ScoutKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

struct TasteTests {

    @Test func rightSwipesRaiseAndLeftSwipesLowerTagWeights() {
        var taste = Taste()
        taste.record(tags: ["swift", "concurrency"], liked: true)
        taste.record(tags: ["crypto"], liked: false)
        // The second swipe decays the first swipe's weights once.
        #expect(abs(taste.tagWeights["swift"]! - Taste.likeStep * Taste.decay) < 1e-9)
        #expect(abs(taste.tagWeights["concurrency"]! - Taste.likeStep * Taste.decay) < 1e-9)
        #expect(taste.tagWeights["crypto"] == -Taste.passStep)
        #expect(taste.likes == 1)
        #expect(taste.passes == 1)
    }

    @Test func weightsStayWithinBounds() {
        var taste = Taste()
        for _ in 0..<50 { taste.record(tags: ["swift"], liked: true) }
        for _ in 0..<50 { taste.record(tags: ["spam"], liked: false) }
        #expect(taste.tagWeights["swift"]! <= 1)
        #expect(taste.tagWeights["spam"]! >= -1)
        #expect(taste.tagWeights["spam"] == -1)
    }

    @Test func untouchedWeightsDecayAway() {
        var taste = Taste()
        taste.record(tags: ["old"], liked: true)
        for _ in 0..<300 { taste.record(tags: ["new"], liked: true) }
        #expect(taste.tagWeights["old"] == nil)
    }

    @Test func centroidIsTheMeanOfLikedEmbeddings() {
        var taste = Taste()
        taste.record(tags: [], liked: true, embedding: [1, 0])
        taste.record(tags: [], liked: true, embedding: [0, 1])
        taste.record(tags: [], liked: false, embedding: [9, 9])
        #expect(taste.centroid == [0.5, 0.5])
    }

    @Test func adjustedScoreIsBoundedBlend() {
        var taste = Taste()
        for _ in 0..<10 { taste.record(tags: ["swift"], liked: true) }
        #expect(taste.adjusted(50, tags: ["swift"]) == 50 + Int(Taste.maxTagShift))
        #expect(taste.adjusted(50, tags: ["rust"]) == 50)
        #expect(taste.adjusted(99, tags: ["swift"], similarity: 1) == 100)
        #expect(taste.adjusted(50, tags: [], similarity: 0) == 40)
    }

    @Test func swipesReorderTheDeck() {
        func story(_ id: String, _ tags: [String], score: Int) -> StoryCandidate {
            StoryCandidate(post: PostRecord(guid: id, title: id, link: id, snippet: "", authorKey: id, authorName: id,
                                            handle: nil, categories: tags, foundUnder: [], published: now, readingMinutes: nil),
                           lanesSurfacing: 1, overlapCount: 0, semantic: 0, score: score)
        }
        let deck = [story("crypto", ["crypto"], score: 60), story("other", ["x"], score: 56), story("swift", ["swift"], score: 55)]
        var taste = Taste()
        #expect(Matching.applyTaste(deck, taste: taste).map(\.id) == ["crypto", "other", "swift"])
        for _ in 0..<3 {
            taste.record(tags: ["swift"], liked: true)
            taste.record(tags: ["crypto"], liked: false)
        }
        #expect(Matching.applyTaste(deck, taste: taste).map(\.id) == ["swift", "other", "crypto"])
    }

    @Test func passCentroidIsTheMeanOfPassedEmbeddings() {
        var taste = Taste()
        taste.record(tags: [], liked: false, embedding: [1, 0])
        taste.record(tags: [], liked: false, embedding: [0, 1])
        taste.record(tags: [], liked: true, embedding: [9, 9])
        #expect(taste.passCentroid == [0.5, 0.5])
        #expect(taste.centroid == [9, 9])
    }

    @Test func lookingLikePassedItemsOnlyLowersAndIsBounded() {
        let taste = Taste()
        #expect(taste.adjusted(50, tags: [], passSimilarity: 1) == 50 - Int(Taste.maxPassShift))
        #expect(taste.adjusted(50, tags: [], passSimilarity: 0.75) == 50 - Int(Taste.maxPassShift / 2))
        // At or below the midpoint, and out of range low, there's no effect; above 1 is clamped.
        #expect(taste.adjusted(50, tags: [], passSimilarity: 0.5) == 50)
        #expect(taste.adjusted(50, tags: [], passSimilarity: -3) == 50)
        #expect(taste.adjusted(50, tags: [], passSimilarity: 7) == 50 - Int(Taste.maxPassShift))
        #expect(taste.adjusted(3, tags: [], passSimilarity: 1) == 0)
    }

    @Test func passedAndLikedLookalikesReorderTheDeck() {
        func story(_ id: String, score: Int) -> StoryCandidate {
            StoryCandidate(post: PostRecord(guid: id, title: id, link: id, snippet: "", authorKey: id, authorName: id,
                                            handle: nil, categories: [], foundUnder: [], published: now, readingMinutes: nil),
                           lanesSurfacing: 1, overlapCount: 0, semantic: 0, score: score)
        }
        let deck = [story("likePassed", score: 60), story("neutral", score: 56), story("likeKept", score: 54)]
        let taste = Taste()
        #expect(Matching.applyTaste(deck, taste: taste).map(\.id) == ["likePassed", "neutral", "likeKept"])
        let reordered = Matching.applyTaste(deck, taste: taste, similarity: ["likeKept": 0.9, "neutral": 0.5, "likePassed": 0.5],
                                            passSimilarity: ["likePassed": 0.95, "neutral": 0.4, "likeKept": 0.3])
        #expect(reordered.map(\.id) == ["likeKept", "neutral", "likePassed"])
        #expect(reordered.map(\.score) == [62, 56, 53])
        // Same inputs, same order.
        #expect(Matching.applyTaste(deck, taste: taste, similarity: ["likeKept": 0.9], passSimilarity: ["likePassed": 0.95]).map(\.id)
                == Matching.applyTaste(deck, taste: taste, similarity: ["likeKept": 0.9], passSimilarity: ["likePassed": 0.95]).map(\.id))
    }

    @Test func tasteSavedBeforePassCentroidStillDecodes() throws {
        let old = #"{"tagWeights":{"swift":0.5},"centroid":[1,0],"likes":2,"passes":1}"#
        let taste = try JSONDecoder().decode(Taste.self, from: Data(old.utf8))
        #expect(taste.passCentroid == nil)
        #expect(taste.tagWeights["swift"] == 0.5)
    }

    @Test func imageDistanceMapsToSimilarity() {
        #expect(ImageTaste.similarity(distance: 0) == 1)
        #expect(ImageTaste.similarity(distance: 1.5) == 0)
        #expect(ImageTaste.similarity(distance: 3) == 0)
        #expect(abs(ImageTaste.similarity(distance: 0.75) - 0.5) < 1e-9)
    }
}

struct RolePackTests {

    @Test func packsRoundTripAsJSON() throws {
        for pack in RolePack.builtIns {
            let decoded = try JSONDecoder().decode(RolePack.self, from: JSONEncoder().encode(pack))
            #expect(decoded == pack)
        }
    }

    @Test func builtInsAreHonestAboutTheirSources() {
        #expect(RolePack.builtIns.map(\.id) == ["engineering-editor", "tech-writer", "illustrator"])
        #expect(RolePack.illustrator.isVisual)
        #expect(RolePack.illustrator.summary.contains("Instagram and Behance have no public feeds"))
        #expect(RolePack.engineering.lanes.contains { $0.sources == ["https://news.ycombinator.com/showrss"] })
        for pack in RolePack.builtIns {
            for key in pack.lanes.flatMap(\.sources) {
                switch FeedSource(laneKey: key) {
                case .feed(let url): #expect(url.scheme == "https")
                case .tag(let slug): #expect(!slug.contains("/"))
                default: Issue.record("unexpected source \(key)")
                }
            }
        }
    }

    @Test func laneKeysDisplayAsHosts() {
        #expect(FeedSource.displayName("https://www.thisiscolossal.com/feed/") == "thisiscolossal.com")
        #expect(FeedSource.displayName("swift") == "swift")
        #expect(FeedSource(laneKey: "https://news.ycombinator.com/rss").laneKey == "https://news.ycombinator.com/rss")
    }
}

struct FeedFormatTests {

    @Test func parsesAtomEntries() throws {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
          <title>Release notes from swift</title>
          <entry>
            <id>tag:github.com,2008:Repository/44838949/swift-6.3</id>
            <updated>2026-11-02T14:11:28Z</updated>
            <link rel="alternate" type="text/html" href="https://github.com/swiftlang/swift/releases/tag/swift-6.3"/>
            <title>Swift 6.3 &amp; friends</title>
            <content type="html">&lt;p&gt;Tag build swift 6.3&lt;/p&gt;</content>
            <author><name>swift-ci</name></author>
            <category term="release"/>
            <media:thumbnail height="30" width="30" url="https://avatars.githubusercontent.com/u/1"/>
          </entry>
        </feed>
        """
        let item = try #require(try RSSParser.parse(Data(atom.utf8)).first)
        #expect(item.title == "Swift 6.3 & friends")
        #expect(item.link.absoluteString == "https://github.com/swiftlang/swift/releases/tag/swift-6.3")
        #expect(item.guid == "tag:github.com,2008:Repository/44838949/swift-6.3")
        #expect(item.creator == "swift-ci")
        #expect(item.categories == ["release"])
        #expect(item.snippet == "Tag build swift 6.3")
        #expect(item.imageURL?.absoluteString == "https://avatars.githubusercontent.com/u/1")
        #expect(item.published == Date(timeIntervalSince1970: 1_793_628_688))
    }

    @Test func parsesHackerNewsItemsWithoutGuidOrAuthor() throws {
        let hn = """
        <rss version="2.0"><channel><title>Hacker News</title>
        <item><title>Show HN: A tiny tool</title><link>https://example.com/tool</link>
        <pubDate>Wed, 04 Nov 2026 20:45:18 +0000</pubDate><comments>https://news.ycombinator.com/item?id=1</comments>
        <description><![CDATA[<a href="https://news.ycombinator.com/item?id=1">Comments</a>]]></description></item>
        </channel></rss>
        """
        let item = try #require(try RSSParser.parse(Data(hn.utf8)).first)
        #expect(item.guid == "https://news.ycombinator.com/item?id=1")
        #expect(item.creator == "")
        #expect(item.snippet == "")
        #expect(item.published == Date(timeIntervalSince1970: 1_793_825_118))
    }
}
