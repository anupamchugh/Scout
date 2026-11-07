//
//  StoryCritique.swift
//  ScoutKit
//
//  A neutral editor's read of one article, for comparing publications and writers. The model fills a fixed
//  rubric with ratings from a closed set and quotes the article first; code checks the quote is really in the
//  text, turns ratings into numbers, and decides every average. No owner taste profile is involved: the
//  rubric is the same for every writer, and an optional lane theme is reported separately as topic fit.
//

import Foundation
import FoundationModels

@Generable
public enum CritiqueRating: String, Sendable, Codable, CaseIterable {
    case strong, adequate, weak

    /// Code, not the model, turns a rating into a number.
    public var points: Int {
        switch self {
        case .strong: 3
        case .adequate: 2
        case .weak: 1
        }
    }
}

@Generable
public struct StoryCritique: Sendable, Equatable {
    @Guide(description: "One sentence of six to thirty words copied exactly from the article that best shows its main point")
    public var evidenceQuote: String

    @Guide(description: "How clearly the article explains its subject to a working programmer")
    public var clarity: CritiqueRating

    @Guide(description: "How far it goes beyond an introduction: trade-offs, edge cases, measurements")
    public var depth: CritiqueRating

    @Guide(description: "Whether claims are backed by code, data, examples or sources in the article")
    public var evidence: CritiqueRating

    @Guide(description: "Whether it offers an angle, example or result that ordinary coverage of the topic lacks")
    public var originality: CritiqueRating

    @Guide(description: "One plain sentence under twenty-five words naming the main reason for the ratings. No numbers, no links, no praise words.")
    public var reason: String

    public init(evidenceQuote: String, clarity: CritiqueRating, depth: CritiqueRating, evidence: CritiqueRating,
                originality: CritiqueRating, reason: String) {
        self.evidenceQuote = evidenceQuote
        self.clarity = clarity
        self.depth = depth
        self.evidence = evidence
        self.originality = originality
        self.reason = reason
    }

    /// Mean of the four ratings, 1...3, computed in code.
    public var score: Double {
        Double(clarity.points + depth.points + evidence.points + originality.points) / 4
    }
}

/// What code concluded about one critique.
public struct CritiqueVerdict: Sendable, Equatable {
    public enum Status: String, Sendable, Codable { case scored, flagged, previewOnly, failed }
    public var status: Status
    public var critique: StoryCritique?
    public var problems: [String]

    public var score: Double? { status == .scored ? critique?.score : nil }
}

public enum CritiqueCheck {
    /// Lowercased, curly quotes straightened, runs of whitespace collapsed, so a faithful quote matches.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .\"'"))
    }

    /// Problems that make a critique unusable. Empty means it passes.
    public static func problems(_ critique: StoryCritique, articleText: String) -> [String] {
        var problems: [String] = []
        let quote = normalized(critique.evidenceQuote)
        if quote.split(separator: " ").count < 4 {
            problems.append("evidence quote too short")
        } else if !normalized(articleText).contains(quote) {
            problems.append("evidence quote not found in the article")
        }
        if critique.reason.contains(where: \.isNumber) { problems.append("reason contains a number") }
        if critique.reason.localizedCaseInsensitiveContains("http") { problems.append("reason contains a link") }
        return problems
    }

    public static func verdict(_ critique: StoryCritique, articleText: String) -> CritiqueVerdict {
        let found = problems(critique, articleText: articleText)
        return CritiqueVerdict(status: found.isEmpty ? .scored : .flagged, critique: critique, problems: found)
    }
}

public enum StoryCritic {
    public static let instructions = """
        You are an editor reviewing an article for a programming publication. Rate it on the fixed rubric using \
        only the article text given. First copy one sentence from the article exactly, then rate clarity, depth, \
        evidence and originality as strong, adequate or weak. Judge the writing, not whether the topic interests \
        you. Do not reward or punish a topic, language or platform.
        """

    /// The article text that fits the on-device context: the opening of the Markdown, trimmed by token count.
    public static func material(_ markdown: String, tokenBudget: Int = 2_600,
                                count: (String) async -> Int) async -> String {
        var text = markdown
        while await count(text) > tokenBudget, text.count > 400 {
            text = String(text.prefix(Int(Double(text.count) * 0.8)))
        }
        return text
    }

    /// Reads one article on device. Feed previews (member-only posts) are not judged.
    public static func critique(title: String, markdown: String?,
                                model: SystemLanguageModel = .default) async -> CritiqueVerdict {
        guard let markdown, !HTMLToMarkdown.isPreview(markdown) else {
            return CritiqueVerdict(status: .previewOnly, critique: nil, problems: ["feed carries a preview only"])
        }
        let material = await material(markdown) { text in
            (try? await model.tokenCount(for: text)) ?? text.count / 4
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Title: \(title)\n\n<article>\n\(material)\n</article>",
                generating: StoryCritique.self,
                options: GenerationOptions(samplingMode: .greedy))
            return CritiqueCheck.verdict(response.content, articleText: material)
        } catch {
            return CritiqueVerdict(status: .failed, critique: nil, problems: [error.localizedDescription])
        }
    }
}
