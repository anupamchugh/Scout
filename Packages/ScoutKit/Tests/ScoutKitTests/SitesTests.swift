//
//  SitesTests.swift
//  ScoutKitTests
//

import Foundation
import Testing
@testable import ScoutKit

struct FeedDiscoveryTests {

    @Test func findsAlternateLinksInHead() {
        let html = """
            <html><head><title>Swift by Sundell</title>
            <link rel="stylesheet" href="/style.css">
            <link rel="alternate" type="application/rss+xml" title="Articles" href="/rss">
            <LINK REL='alternate' TYPE='application/atom+xml' TITLE='Podcast &amp; more' HREF='https://cdn.example/atom.xml'>
            <link rel="alternate" type="application/rss+xml" href="/rss">
            <link rel="alternate" hreflang="fr" href="/fr">
            </head><body>…</body></html>
            """
        let feeds = FeedDiscovery.links(inHTML: html, base: URL(string: "https://www.swiftbysundell.com/articles/")!)
        #expect(feeds.map(\.url.absoluteString) == ["https://www.swiftbysundell.com/rss", "https://cdn.example/atom.xml"])
        #expect(feeds.map(\.title) == ["Articles", "Podcast & more"])
    }

    @Test func recognisesFeedBytes() {
        #expect(FeedDiscovery.isFeed(Data("<?xml version=\"1.0\"?><rss version=\"2.0\">".utf8)))
        #expect(FeedDiscovery.isFeed(Data("<feed xmlns=\"http://www.w3.org/2005/Atom\">".utf8)))
        #expect(!FeedDiscovery.isFeed(Data("<!doctype html><html>".utf8)))
    }
}

struct LLMSTxtTests {
    let sample = """
        # Sample Writer

        > Notes on Swift concurrency, testing and building small Mac apps.

        Some optional prose.

        ## Swift concurrency
        - [Actors without the fear](https://writer.example/actors): a calm tour of isolation
        - [Task groups](https://writer.example/groups)

        ## Testing
        - [Swift Testing tips](https://writer.example/testing): parameterised tests
        """

    @Test func parsesTitleSummarySectionsAndLinks() throws {
        let document = try #require(LLMSTxt.parse(sample))
        #expect(document.title == "Sample Writer")
        #expect(document.summary == "Notes on Swift concurrency, testing and building small Mac apps.")
        #expect(document.sectionTitles == ["Swift concurrency", "Testing"])
        #expect(document.sections[0].links.count == 2)
        #expect(document.sections[0].links[0] == .init(name: "Actors without the fear", url: "https://writer.example/actors",
                                                        note: "a calm tour of isolation"))
        #expect(document.sections[0].links[1].note == "")
    }

    @Test func rejectsHTMLAndUntitledText() {
        #expect(LLMSTxt.parse("<html><body># Not found</body></html>") == nil)
        #expect(LLMSTxt.parse("just text") == nil)
    }

    @Test func personalDomainsAndLaneOverlap() {
        #expect(LLMSTxt.isPersonalDomain("www.swiftbysundell.com"))
        #expect(!LLMSTxt.isPersonalDomain("medium.com"))
        #expect(!LLMSTxt.isPersonalDomain("someone.substack.com"))
        let lane = LaneSpec(name: "Swift concurrency", tags: ["concurrency", "swift"], theme: "actors and task groups")
        #expect(LLMSTxt.laneOverlap(sectionTitles: ["Swift concurrency", "Testing"], lane: lane) == 2.0 / 3)
        #expect(LLMSTxt.laneOverlap(sectionTitles: ["Cooking"], lane: lane) == 0)
    }
}
