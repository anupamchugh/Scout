//
//  TitleOriginalityTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct TitleOriginalityTests {
    @Test func nearestNeighbourAndNearDuplicatesFromVectors() {
        let titles = ["Claude Code tips A", "Claude Code tips B", "CSS clip paths", "Unembeddable"]
        let vectors: [[Double]?] = [[1, 0, 0], [0.99, 0.14, 0], [0, 0, 1], nil]
        let r = TitleOriginality.report(titles: titles, vectors: vectors, threshold: 0.9)
        #expect(r.titles == 4 && r.unembedded == 1)
        #expect(r.closestPairs.first?.first == "Claude Code tips A")
        #expect(r.closestPairs.first?.second == "Claude Code tips B")
        #expect((r.closestPairs.first?.similarity ?? 0) > 0.98)
        // A and B are near-duplicates of each other; the CSS title is not.
        #expect(r.nearDuplicateShare == 2.0 / 3.0)
    }

    @Test func oneTitleHasNoNeighbour() {
        let r = TitleOriginality.report(titles: ["Only"], vectors: [[1, 0]])
        #expect(r.meanNearest == nil && r.nearDuplicateShare == nil && r.closestPairs.isEmpty)
    }
}
