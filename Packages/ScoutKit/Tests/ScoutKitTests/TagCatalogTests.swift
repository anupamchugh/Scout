//
//  TagCatalogTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct TagCatalogTests {

    @Test func normalisesAndDropsFeedURLs() {
        #expect(TagCatalog.normalized([" Swift", "swift", "https://news.ycombinator.com/rss", "", "SwiftUI"]) == ["swift", "swiftui"])
    }

    @Test func potentialTagsAreCountedBesideLaneTags() {
        let posts = [
            ["swift", "concurrency", "actors"],
            ["swift", "actors", "ios"],
            ["swift-concurrency", "actors"],
            ["swift", "ios"],
            ["cooking", "soup"],
            ["cooking", "soup", "actors"],
        ]
        let (counts, cooccurrence) = TagCatalog.tally(posts)
        #expect(counts["actors"] == 4)
        #expect(cooccurrence["swift"]?["ios"] == 2)

        let potential = TagCatalog.potential(for: ["swift", "concurrency", "swift-concurrency"], counts: counts, cooccurrence: cooccurrence)
        // actors: beside swift twice, concurrency once, swift-concurrency once = 4; ios beside swift twice.
        #expect(potential.map(\.tag) == ["actors", "ios"])
        #expect(potential.first == .init(tag: "actors", together: 4, seen: 4))
        // Lane tags never suggest themselves, and tags never seen beside the lane (soup) don't appear.
        #expect(!potential.contains { ["swift", "concurrency", "soup", "cooking"].contains($0.tag) })
    }

    @Test func minimumFiltersOneOffs() {
        let (counts, cooccurrence) = TagCatalog.tally([["swift", "rare"], ["swift", "common"], ["swift", "common"]])
        #expect(TagCatalog.potential(for: ["swift"], counts: counts, cooccurrence: cooccurrence).map(\.tag) == ["common"])
        #expect(TagCatalog.potential(for: ["swift"], counts: counts, cooccurrence: cooccurrence, minimum: 1).map(\.tag) == ["common", "rare"])
    }
}
