//
//  SlopBucketTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct SlopBucketTests {
    func verdict(_ ratings: [CritiqueRating], specificity: CritiqueRating) -> CritiqueVerdict {
        CritiqueVerdict(status: .scored, critique: StoryCritique(
            evidenceQuote: "q", clarity: ratings[0], depth: ratings[1], evidence: ratings[2], originality: ratings[3],
            specificity: specificity, reason: "r"), problems: [])
    }

    @Test func packagingTimesSubstance() {
        let solid = verdict([.strong, .strong, .adequate, .strong], specificity: .strong)   // 2.75
        let thin = verdict([.adequate, .weak, .weak, .adequate], specificity: .weak)        // 1.5
        let solidButGeneric = verdict([.strong, .strong, .strong, .strong], specificity: .weak)
        #expect(SlopBucket.classify(shape: .plain, templated: false, verdict: solid) == .plainSolid)
        #expect(SlopBucket.classify(shape: .colonSubtitle, templated: false, verdict: solid) == .goodSlop)
        #expect(SlopBucket.classify(shape: .listicle, templated: false, verdict: thin) == .badSlop)
        #expect(SlopBucket.classify(shape: .plain, templated: true, verdict: thin) == .badSlop)
        #expect(SlopBucket.classify(shape: .question, templated: false, verdict: thin) == .plainThin)
        #expect(SlopBucket.classify(shape: .colonSubtitle, templated: false, verdict: solidButGeneric) == .badSlop)
        let preview = CritiqueVerdict(status: .previewOnly, critique: nil, problems: [])
        #expect(SlopBucket.classify(shape: .listicle, templated: false, verdict: preview) == .unknown)
    }

    @Test func readabilityMeasuresSentencesAndSyllables() throws {
        let easy = String(repeating: "The cat sat on the mat. It was warm. ", count: 6)
        let hard = String(repeating: "Organizational infrastructure modernization necessitates comprehensive architectural reconsideration across heterogeneous computational environments. ", count: 4)
        let e = try #require(Readability.measure(easy))
        let h = try #require(Readability.measure(hard))
        #expect(e.fleschReadingEase > 80)
        #expect(h.fleschReadingEase < 20)
        #expect(e.wordsPerSentence < h.wordsPerSentence)
        #expect(Readability.measure("Too short.") == nil)
        #expect(Readability.syllables("table") == 2 && Readability.syllables("cache") == 1)
    }
}
