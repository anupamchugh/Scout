//
//  SearchRouteTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct SearchRouteTests {
    let levelUp = PublicationChoice.presets[0]
    let bp = PublicationChoice.presets[1]

    @Test func publicationQuestionsOpenCompare() {
        #expect(SearchRoute.route("check programming publications") == .compare(levelUp, bp))
        #expect(SearchRoute.route("Is Level Up Coding slop?") == .compare(levelUp, bp))
        #expect(SearchRoute.route("better programming") == .compare(bp, levelUp))
        #expect(SearchRoute.route("compare ITNEXT and Stackademic")
                == .compare(PublicationChoice.presets[2], PublicationChoice.presets[4]))
        #expect(SearchRoute.route("Stackademic vs level up")
                == .compare(PublicationChoice.presets[4], levelUp))
    }

    @Test func otherQuestionsSearchWritersAndStories() {
        #expect(SearchRoute.route("  swift concurrency writers ") == .search("swift concurrency writers"))
        #expect(SearchRoute.route("actors") == .search("actors"))
    }
}
