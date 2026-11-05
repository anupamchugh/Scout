//
//  TopicTagsTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct TopicTagsTests {

    @Test func slugsAreMediumShaped() {
        #expect(TopicTags.slug("Engineering Management") == "engineering-management")
        #expect(TopicTags.slug("  #AI / RAG ") == "ai-rag")
        #expect(TopicTags.slug("Café") == "cafe")
        #expect(TopicTags.slug("!!!") == nil)
    }

    @Test func candidatesPutGuessesFirstAndDropFillerWords() {
        let candidates = TopicTags.candidates(topic: "blogging and newsletters", guesses: ["Blogging", "Substack", "content creation"])
        #expect(candidates == ["blogging", "substack", "content-creation", "blogging-and-newsletters", "newsletters"])
        #expect(!candidates.contains("and"))
    }

    @Test func laneTagsKeepOnlyLiveFeedsThenNearby() {
        let checked = [TopicTags.Checked(tag: "substack", posts: 4), TopicTags.Checked(tag: "made-up-tag", posts: 0),
                       TopicTags.Checked(tag: "blogging", posts: 10)]
        #expect(TopicTags.laneTags(checked: checked, nearby: ["writing", "blogging"]) == ["blogging", "substack", "writing"])
    }

    @Test func nearbyRanksKnownTagsByMeaning() {
        let ranked = TopicTags.nearby("Apple platforms and iPhone apps",
                                      among: ["ios-development", "cooking", "iphone", "gardening"], threshold: 0)
        #expect(ranked.first.map { ["ios-development", "iphone"].contains($0.tag) } == true)
        #expect(ranked.last?.tag == "cooking" || ranked.last?.tag == "gardening")
    }
}
