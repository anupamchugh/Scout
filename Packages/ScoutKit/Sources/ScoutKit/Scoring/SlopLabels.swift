//
//  SlopLabels.swift
//  ScoutKit
//
//  An editor's own ratings of real articles on the StoryCritique rubric, so the on-device reader can be measured
//  against a person instead of trusted. The set lives outside this repository (articles are other people's writing):
//  `runs/slop-labels/labels.json` beside one Markdown file per article in WritingCorpus. The SlopLabelSet tool adds
//  articles with empty ratings; the editor fills them in by hand; only fully rated entries are evaluated.
//

import Foundation

public struct SlopLabel: Codable, Sendable, Equatable {
    /// The editor's ratings; nil until rated.
    public struct Ratings: Codable, Sendable, Equatable {
        public var clarity: CritiqueRating?
        public var depth: CritiqueRating?
        public var evidence: CritiqueRating?
        public var originality: CritiqueRating?
        public var specificity: CritiqueRating?

        public init(clarity: CritiqueRating? = nil, depth: CritiqueRating? = nil, evidence: CritiqueRating? = nil,
                    originality: CritiqueRating? = nil, specificity: CritiqueRating? = nil) {
            self.clarity = clarity; self.depth = depth; self.evidence = evidence
            self.originality = originality; self.specificity = specificity
        }

        /// The ratings as a critique, when every one is set, so code scores the editor exactly as it scores the model.
        public var critique: StoryCritique? {
            guard let clarity, let depth, let evidence, let originality, let specificity else { return nil }
            return StoryCritique(evidenceQuote: "", clarity: clarity, depth: depth, evidence: evidence,
                                 originality: originality, specificity: specificity, reason: "")
        }
    }

    public var id: String
    public var publication: String
    public var title: String
    public var link: String
    /// Path of the article's Markdown, relative to the label set's folder.
    public var article: String
    public var editor: Ratings

    public init(id: String, publication: String, title: String, link: String, article: String, editor: Ratings = .init()) {
        self.id = id; self.publication = publication; self.title = title; self.link = link
        self.article = article; self.editor = editor
    }
}

public enum SlopLabels {
    /// Adds new articles to an existing set without touching any rating already there; order is kept, new ones last.
    public static func merge(_ existing: [SlopLabel], adding new: [SlopLabel]) -> [SlopLabel] {
        let known = Set(existing.map(\.id))
        return existing + new.filter { !known.contains($0.id) }
    }

    public static func load(_ file: URL) throws -> [SlopLabel] {
        try JSONDecoder().decode([SlopLabel].self, from: Data(contentsOf: file))
    }

    public static func save(_ labels: [SlopLabel], to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(labels).write(to: file, options: .atomic)
    }
}
