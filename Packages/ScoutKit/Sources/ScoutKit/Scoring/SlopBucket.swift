//
//  SlopBucket.swift
//  ScoutKit
//
//  Packaging × substance, decided in code. Packaging is formulaic when the title has a formula shape or the
//  writer reuses a title template; substance is solid when the on-device rubric scored the story 2.5 or more
//  (out of 3) and did not rate its specificity weak. "Good slop" is formula packaging over solid substance;
//  "bad slop" is formula packaging over thin, generic writing. Stories with no judged text are unknown.
//

import Foundation

public enum SlopBucket: String, Sendable, Codable, CaseIterable {
    case plainSolid = "Plain and solid"
    case goodSlop = "Formula, solid (good slop)"
    case badSlop = "Formula, thin (bad slop)"
    case plainThin = "Plain but thin"
    case unknown = "Not judged"

    public static let solidScore = 2.5

    public static func formulaic(_ shape: TitleShape, templated: Bool) -> Bool {
        templated || [.listicle, .colonSubtitle, .howTo].contains(shape)
    }

    public static func classify(shape: TitleShape, templated: Bool, verdict: CritiqueVerdict) -> SlopBucket {
        guard verdict.status == .scored, let critique = verdict.critique else { return .unknown }
        let solid = critique.score >= solidScore && critique.specificity != .weak
        switch (formulaic(shape, templated: templated), solid) {
        case (false, true): return .plainSolid
        case (true, true): return .goodSlop
        case (true, false): return .badSlop
        case (false, false): return .plainThin
        }
    }

    /// Buckets for every story on a side; templates are found across the side's own titles.
    public static func buckets(for side: PublicationSide) -> [String: SlopBucket] {
        let templatedTitles = Set(side.templated.flatMap(\.titles))
        return Dictionary(uniqueKeysWithValues: side.stories.map {
            ($0.id, classify(shape: $0.shape, templated: templatedTitles.contains($0.title), verdict: $0.verdict))
        })
    }
}

/// Readability of prose, in the style of writing assistants: average sentence length and Flesch reading ease.
public struct Readability: Sendable, Equatable, Codable {
    public var wordsPerSentence: Double
    /// 206.835 − 1.015 × words/sentence − 84.6 × syllables/word. Higher reads easier; 60–70 is plain English.
    public var fleschReadingEase: Double
    /// Share of sentences over 30 words.
    public var longSentenceShare: Double

    static func syllables(_ word: Substring) -> Int {
        let w = word.lowercased().filter(\.isLetter)
        guard !w.isEmpty else { return 0 }
        var count = 0, previousVowel = false
        for c in w {
            let vowel = "aeiouy".contains(c)
            if vowel && !previousVowel { count += 1 }
            previousVowel = vowel
        }
        if w.hasSuffix("e") && !w.hasSuffix("le") && count > 1 { count -= 1 }
        return max(count, 1)
    }

    public static func measure(_ prose: String) -> Readability? {
        let sentences = prose.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) } }
            .filter { !$0.isEmpty }
        let words = sentences.flatMap { $0 }
        guard !sentences.isEmpty, words.count >= 20 else { return nil }
        let wps = Double(words.count) / Double(sentences.count)
        let spw = Double(words.reduce(0) { $0 + syllables($1) }) / Double(words.count)
        return Readability(wordsPerSentence: wps,
                           fleschReadingEase: 206.835 - 1.015 * wps - 84.6 * spw,
                           longSentenceShare: Double(sentences.filter { $0.count > 30 }.count) / Double(sentences.count))
    }
}
