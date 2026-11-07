//
//  StoryCritiqueTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct StoryCritiqueTests {
    let article = """
        Caching is the cheapest speed-up you have. A semantic cache returns a stored answer when a new prompt \
        means the same thing as an old one, which cuts cost but risks serving another user’s data.
        """

    func critique(quote: String, reason: String = "Explains semantic caching and its privacy risk with a concrete case.",
                  ratings: [CritiqueRating] = [.strong, .adequate, .adequate, .weak]) -> StoryCritique {
        StoryCritique(evidenceQuote: quote, clarity: ratings[0], depth: ratings[1], evidence: ratings[2],
                      originality: ratings[3], reason: reason)
    }

    @Test func faithfulQuotePassesDespiteCaseQuotesAndSpacing() {
        let c = critique(quote: "a semantic cache returns a stored answer when a new prompt  means the same thing")
        #expect(CritiqueCheck.problems(c, articleText: article).isEmpty)
        let curly = critique(quote: "risks serving another user's data.")
        #expect(CritiqueCheck.problems(curly, articleText: article).isEmpty)
    }

    @Test func inventedQuoteIsFlagged() {
        let c = critique(quote: "Caching makes every system ten times faster overnight")
        let verdict = CritiqueCheck.verdict(c, articleText: article)
        #expect(verdict.status == .flagged)
        #expect(verdict.problems == ["evidence quote not found in the article"])
        #expect(verdict.score == nil)
    }

    @Test func numbersLinksAndShortQuotesAreFlagged() {
        let c = critique(quote: "Caching is", reason: "Saves 40% — see https://example.com")
        #expect(CritiqueCheck.problems(c, articleText: article) ==
                ["evidence quote too short", "reason contains a number", "reason contains a link"])
    }

    @Test func scoreIsTheMeanOfRatingPointsComputedInCode() {
        let c = critique(quote: "Caching is the cheapest speed-up you have")
        #expect(c.score == (3 + 2 + 2 + 1) / 4.0)
        #expect(CritiqueCheck.verdict(c, articleText: article).score == 2.0)
    }

    @Test func materialIsTrimmedToTheTokenBudget() async {
        let long = String(repeating: "word ", count: 5_000)
        let trimmed = await StoryCritic.material(long, tokenBudget: 1_000) { $0.count / 4 }
        #expect(trimmed.count / 4 <= 1_000)
        #expect(long.hasPrefix(trimmed))
    }

    @Test func previewsAreNotJudged() async {
        let verdict = await StoryCritic.critique(title: "Members only", markdown: "A short preview of the post.")
        #expect(verdict.status == .previewOnly)
    }
}
