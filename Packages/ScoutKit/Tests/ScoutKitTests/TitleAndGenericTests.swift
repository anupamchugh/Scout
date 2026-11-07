//
//  TitleAndGenericTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct TitleShapeTests {
    @Test func classifiesCommonShapes() {
        #expect(TitleShape.classify("7 Ways to Speed Up Xcode") == .listicle)
        #expect(TitleShape.classify("How to Ship a Widget") == .howTo)
        #expect(TitleShape.classify("Real-Time CDC From PostgreSQL to Snowflake, Step by Step") == .howTo)
        #expect(TitleShape.classify("Hexagonal Architecture in Go, Part 1: Where Does This Code Go?") == .question)
        #expect(TitleShape.classify("Vision Transformers Part1: Why Replace Convolution with Attention") == .seriesPart)
        #expect(TitleShape.classify("Caching in LLMs: The Layers That Make AI Systems Fast") == .colonSubtitle)
        #expect(TitleShape.classify("I DIYed a flight radar") == .plain)
    }

    @Test func markersIgnoreTopicWords() {
        #expect(TitleMarker.markers("Iterator Pattern in .NET C#: From First/Next/IsDone to yield return (2026)")
                == [.colon, .fromTo, .yearInBrackets])
        #expect(TitleMarker.markers("Top 10 tools of 2026") == [.yearInTitle])
    }

    @Test func findsAWriterReusingOneTemplate() {
        let titles: [(writer: String, title: String)] = [
            ("Emanuele Longo", "Iterator Pattern in .NET C#: From First/Next/IsDone to yield return and async streams (2026)"),
            ("Emanuele Longo", "Interpreter Pattern in .NET C#: From grammar classes to compiled expression trees (2026)"),
            ("Emanuele Longo", "Static Abstract Members and Generic Math in C# 11+: From copy-pasted overloads to INumber<T>"),
            ("Vlad Zoff", "Multi-Tenant RAG in Next.js: Relevance Is Not Authorization"),
            ("Brian Jones", "Hexagonal Architecture in Go, Part 1: Where Does This Code Go?"),
        ]
        let repeated = TitleTemplates.repeated(titles)
        #expect(repeated.count == 1)
        #expect(repeated.first?.writer == "Emanuele Longo")
        #expect(repeated.first?.markers == [.colon, .fromTo, .yearInBrackets])
        #expect(repeated.first?.titles.count == 2)
    }
}

struct GenericWritingTests {
    @Test func countsStockPhrasesOutsideCode() {
        let md = """
            In today's fast-paced world, caching matters. Let's dive in.

            ```swift
            // let's dive in: this comment is code, not prose
            let cache = Cache()
            ```

            In conclusion, measure first.
            """
        let s = GenericWriting.signals(md)
        #expect(s.stockPhrases == ["in today's fast-paced", "let's dive in", "in conclusion"])
        #expect(s.codeLineShare > 0.3 && s.codeLineShare < 0.6)
    }

    @Test func measuresRepeatedSentenceOpenings() {
        let md = """
            You can cache the prompt prefix here. You can cache the full answer too. You can cache embeddings as well. \
            Semantic caches compare meaning rather than text.
            """
        let s = GenericWriting.signals(md)
        #expect(s.repeatedOpeningShare == 0.75)
    }

    @Test func detectsTheAssistantVoice() {
        let md = """
            You're right, and that's on me — two real misses. I'm adding a **standing rule** so it's automatic, \
            not something I have to remember. A public PR has to stand on its own — not our shorthand.
            """
        let s = GenericWriting.signals(md)
        #expect(s.assistantPhrases == ["you're right", "that's on me", "standing rule"])
        #expect(s.reframesPerThousandWords > 0)
        #expect(s.emDashesPerThousandWords > 0)
        #expect(s.boldPerThousandWords > 0)
    }

    @Test func plainTechnicalProseHasNoAssistantVoice() {
        let s = GenericWriting.signals("The cache stores KV tensors per prefix. Eviction is least recently used.")
        #expect(s.assistantPhrases.isEmpty)
        #expect(s.reframesPerThousandWords == 0 && s.emDashesPerThousandWords == 0 && s.boldPerThousandWords == 0)
    }

    @Test func specificProseHasNoHits() {
        let s = GenericWriting.signals("The server keeps the computed KV tensors for the shared prefix and reuses them.")
        #expect(s.stockPhrases.isEmpty)
        #expect(s.stockPerThousandWords == 0)
    }
}

struct SpecificityCheckTests {
    let article = "Caching is the cheapest speed-up you have. It matters in many systems today."

    @Test func genericSentenceMustBeInTheArticle() {
        let ok = StoryCritique(evidenceQuote: "Caching is the cheapest speed-up you have", clarity: .strong, depth: .adequate,
                               evidence: .adequate, originality: .adequate,
                               genericSentence: "It matters in many systems today.", specificity: .weak,
                               reason: "Clear opening but much of it is general.")
        #expect(CritiqueCheck.problems(ok, articleText: article).isEmpty)
        var invented = ok
        invented.genericSentence = "Technology is changing the world."
        #expect(CritiqueCheck.problems(invented, articleText: article) == ["generic sentence not found in the article"])
    }
}
