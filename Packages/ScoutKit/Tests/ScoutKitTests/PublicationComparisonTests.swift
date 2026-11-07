//
//  PublicationComparisonTests.swift
//  ScoutKitTests
//

import Foundation
import Testing
@testable import ScoutKit

struct PublicationComparisonTests {
    @Test func parsesSlugsMediumLinksAndFeeds() {
        #expect(PublicationChoice.parse("gitconnected")?.source == .publication("gitconnected"))
        #expect(PublicationChoice.parse("https://medium.com/better-programming")?.key == "better-programming")
        #expect(PublicationChoice.parse("https://medium.com/feed/itnext")?.key == "itnext")
        #expect(PublicationChoice.parse("https://example.com/rss.xml")?.source == .feed(URL(string: "https://example.com/rss.xml")!))
        // A writer's page is not a publication slug; it stays a URL the feed client will try as given.
        #expect(PublicationChoice.parse("https://medium.com/@someone")?.key == "https://medium.com/@someone")
        #expect(PublicationChoice.parse("Level Up!") == nil)
        #expect(PublicationChoice.parse("  ") == nil)
    }

    func story(_ id: String, writer: String, title: String, verdict: CritiqueVerdict, words: Int? = 800) -> ComparedStory {
        ComparedStory(id: id, title: title, writer: writer, link: "https://example.com/\(id)",
                      published: Date(timeIntervalSince1970: Double(id.hashValue & 0xFFFF)),
                      shape: TitleShape.classify(title), verdict: verdict,
                      signals: words.map { _ in GenericWriting.signals("Let's dive in. The cache stores tensors per prefix.") })
    }

    func scored(_ ratings: [CritiqueRating], specificity: CritiqueRating = .adequate) -> CritiqueVerdict {
        CritiqueVerdict(status: .scored, critique: StoryCritique(
            evidenceQuote: "q", clarity: ratings[0], depth: ratings[1], evidence: ratings[2], originality: ratings[3],
            genericSentence: "", specificity: specificity, reason: "r"), problems: [])
    }

    @Test func summarizesASideInCode() {
        let preview = CritiqueVerdict(status: .previewOnly, critique: nil, problems: ["preview"])
        let stories = [
            story("a", writer: "Ana", title: "Iterator Pattern in C#: From Loops to Streams (2026)", verdict: scored([.strong, .strong, .strong, .strong], specificity: .strong)),
            story("b", writer: "Ana", title: "Visitor Pattern in C#: From Switches to Visitors (2026)", verdict: scored([.adequate, .weak, .adequate, .adequate])),
            story("c", writer: "Ana", title: "Members only", verdict: preview, words: nil),
            story("d", writer: "Ben", title: "7 Ways to Cache", verdict: CritiqueVerdict(status: .flagged, critique: nil, problems: ["x"])),
        ]
        let side = PublicationComparison.summarize(PublicationChoice(name: "Test", key: "test"), stories: stories)
        #expect(side.writers == 2)
        #expect(side.topWriter == "Ana")
        #expect(side.topWriterShare == 0.75)
        #expect(side.scored == 2 && side.flagged == 1 && side.previewOnly == 1)
        #expect(side.readable == 3)
        #expect(side.score == (3.0 + 1.75) / 2)
        #expect(side.depthStrong == 0.5)
        #expect(side.specificStrong == 0.5)
        #expect(side.colonTitles == 0.5)
        #expect(side.listicleTitles == 0.25)
        #expect(side.templated.first?.writer == "Ana")
        #expect(side.templatedShare == 0.5)
        #expect(side.topStory?.id == "a")
        #expect((side.stockPerThousand ?? 0) > 0)
    }

    @Test func readUsesTheInjectedCriticAndReportsProgress() async {
        let html = "<p>" + String(repeating: "Caching keeps computed tensors for reuse. ", count: 40) + "</p>"
        let items = [
            FeedItem(guid: "1", title: "Caching in LLMs: Layers", link: URL(string: "https://e.com/1")!, creator: "Nagesh",
                     published: .now, categories: [], snippet: "", contentHTML: html),
            FeedItem(guid: "2", title: "Members only", link: URL(string: "https://e.com/2")!, creator: "Kemal",
                     published: .now, categories: [], snippet: "", contentHTML: "<p>Short preview.</p>"),
        ]
        actor Calls { var progress: [Int] = []; func add(_ i: Int) { progress.append(i) } }
        let calls = Calls()
        let stories = await PublicationComparison.read(items, critic: { _, markdown in
            markdown.map { HTMLToMarkdown.isPreview($0) } == false
                ? CritiqueVerdict(status: .scored, critique: nil, problems: [])
                : CritiqueVerdict(status: .previewOnly, critique: nil, problems: [])
        }, progress: { done, _ in await calls.add(done) })
        #expect(stories.map(\.verdict.status) == [.scored, .previewOnly])
        #expect(stories[0].shape == .colonSubtitle)
        #expect(stories[0].signals != nil && stories[1].signals == nil)
        #expect(await calls.progress == [0, 1, 2])
    }
}
