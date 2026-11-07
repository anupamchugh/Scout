//
//  PublicationBriefingTests.swift
//  ScoutKitTests
//

import Foundation
import Testing
@testable import ScoutKit

struct PublicationBriefingTests {
    let now = Date(timeIntervalSince1970: 1_794_000_000)   // Nov 2026

    func story(_ id: String, _ writer: String, _ title: String, _ verdict: CritiqueVerdict, daysAgo: Double = 1) -> ComparedStory {
        ComparedStory(id: id, title: title, writer: writer, link: "https://e.com/\(id)",
                      published: now.addingTimeInterval(-daysAgo * 86_400), shape: TitleShape.classify(title),
                      verdict: verdict, signals: nil)
    }

    func scored(_ r: CritiqueRating, _ s: CritiqueRating) -> CritiqueVerdict {
        CritiqueVerdict(status: .scored, critique: StoryCritique(evidenceQuote: "q", clarity: r, depth: r, evidence: r,
                                                                 originality: r, specificity: s, reason: "x"), problems: [])
    }

    var levelUp: PublicationSide {
        let preview = CritiqueVerdict(status: .previewOnly, critique: nil, problems: [])
        return PublicationComparison.summarize(PublicationChoice(name: "Level Up Coding", key: "gitconnected"), stories: [
            story("1", "Ana", "Iterator Pattern in C#: From Loops to Streams (2026)", scored(.weak, .weak)),
            story("2", "Ana", "Visitor Pattern in C#: From Switches to Visitors (2026)", preview),
            story("3", "Ana", "Builder Pattern in C#: From Setters to Builders (2026)", preview),
            story("4", "Ben", "Caching in LLMs: The Layers", scored(.strong, .strong)),
        ])
    }

    @Test func overviewNamesFormulaTitlesTemplatesAndConcentration() {
        let text = PublicationBriefing.overview([levelUp], now: now)
        #expect(text.hasPrefix("Level Up Coding: 4 recent posts by 2 writers."))
        #expect(text.contains("100 percent formula titles"))
        #expect(text.contains("Ana reuses one title template 3 times"))
        #expect(text.contains("Ana wrote 75 percent of them"))
    }

    @Test func overviewSaysWhenAPublicationIsArchived() {
        let bp = PublicationComparison.summarize(PublicationChoice(name: "Better Programming", key: "better-programming"),
                                                 stories: [story("a", "Cy", "WebAssembly with Go", scored(.strong, .strong), daysAgo: 1_090)])
        let text = PublicationBriefing.overview([bp], now: now)
        #expect(text.hasPrefix("Better Programming is archived; its latest post is from"))
        #expect(text.contains("No strong slop patterns in the titles."))
    }

    @Test func slopReportCountsBucketsAndNamesBadSlop() {
        let text = PublicationBriefing.slopReport(levelUp, now: now)
        #expect(text.contains("I read 2 of its 4 latest posts on this device"))
        #expect(text.contains("1 solid, 1 bad slop, 1 good slop."))
        #expect(text.contains("Bad slop: “Iterator Pattern in C#: From Loops to Streams (2026)” by Ana."))
        #expect(text.contains("Best read: “Caching in LLMs: The Layers” by Ben."))
        #expect(text.contains("2 member-only posts were not judged."))
    }

    @Test func slopReportWithNothingReadable() {
        let preview = CritiqueVerdict(status: .previewOnly, critique: nil, problems: [])
        let side = PublicationComparison.summarize(PublicationChoice(name: "Paywalled", key: "p"),
                                                   stories: [story("x", "Dee", "Members only", preview)])
        #expect(PublicationBriefing.slopReport(side, now: now)
                == "Paywalled. None of its 1 latest posts had full text in the feed, so none were judged.")
    }

    @Test func slopReportSaysWhenTheModelFailed() {
        let failed = CritiqueVerdict(status: .failed, critique: nil, problems: ["Model assets unavailable"])
        let side = PublicationComparison.summarize(PublicationChoice(name: "ITNEXT", key: "itnext"),
                                                   stories: [story("x", "Dee", "Kubernetes operators", failed)])
        #expect(PublicationBriefing.slopReport(side, now: now)
                == "ITNEXT. The on-device model couldn’t read 1 of its 1 latest posts (Model assets unavailable), so none were judged.")
    }
}
