//
//  PublicationDigestTests.swift
//  ScoutKitTests
//

import Foundation
import Testing
@testable import ScoutKit

struct PublicationDigestTests {
    let base = Date(timeIntervalSince1970: 1_794_000_000)

    func side(_ minutesApart: [Double], writers: [String]) -> PublicationSide {
        let none = CritiqueVerdict(status: .previewOnly, critique: nil, problems: [])
        let stories = zip(minutesApart, writers).enumerated().map { i, pair in
            ComparedStory(id: "\(i)", title: "Post \(i)", writer: pair.1, link: "https://e.com/\(i)",
                          published: base.addingTimeInterval(pair.0 * 60), shape: .plain, verdict: none, signals: nil)
        }
        return PublicationComparison.summarize(PublicationChoice(name: "Pub", key: "pub"), stories: stories)
    }

    @Test func cadenceNamesBatchesHoursAndDays() {
        #expect(PublicationDigest.cadence(side([0, 0.2, 1.8], writers: ["A", "B", "C"]))
                == "3 posts released within 2 minutes (one batch)")
        #expect(PublicationDigest.cadence(side([0, 300], writers: ["A", "B"])) == "2 posts within 5 hours")
        #expect(PublicationDigest.cadence(side([0, 1440, 2880], writers: ["A", "B", "C"]))
                == "3 posts over 2.0 days, about 1.5 a day")
    }

    @Test func writersAreCountedMostFirst() {
        let w = PublicationDigest.writers(side([0, 1, 2, 3], writers: ["Ben", "Ana", "Ana", "Cy"]))
        #expect(w.map(\.writer) == ["Ana", "Ben", "Cy"])
        #expect(w.map(\.posts) == [2, 1, 1])
    }

    @Test func markdownHasTheGlanceRowAndEveryTitle() {
        let md = PublicationDigest.markdown([side([0, 1], writers: ["Ana", "Ana"])], generated: base, where: "in a test")
        #expect(md.contains("| Pub | "))
        #expect(md.contains("Ana (2)"))
        #expect(md.contains("[Post 0](https://e.com/0)") && md.contains("[Post 1](https://e.com/1)"))
    }
}
