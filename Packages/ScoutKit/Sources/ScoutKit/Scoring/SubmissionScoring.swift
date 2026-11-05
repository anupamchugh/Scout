//
//  SubmissionScoring.swift
//  ScoutKit
//
//  Scores a submitted piece (a title and its opening) the way the deck scores a story, so the editor's
//  past accept-or-pass decisions can check Scout's ranking. Code ranks; the model only writes the "why".
//

import Foundation

public enum SubmissionScoring {

    /// The story score of a piece against each lane, best lane first, as `Matching.stories` computes it.
    /// A submission has no feed tags or age, so only the semantic signal tells pieces apart.
    public static func score(title: String, text: String, lanes: [LaneSpec], now: Date = .now) -> (score: Int, lane: String) {
        let post = PostRecord(guid: "submission", title: title, link: "", snippet: text, authorKey: "submission",
                              authorName: "", handle: nil, categories: [], foundUnder: [], published: now, readingMinutes: nil)
        let vector = Embedder.vector("\(title). \(text)")
        let best = lanes.compactMap { lane -> StoryCandidate? in
            var similarity = 0.0
            if let vector, let theme = Embedder.vector(lane.theme) { similarity = max(0, min(1, Embedder.cosine(vector, theme))) }
            return Matching.stories(from: [post], lane: lane, lanes: lanes, semantic: [post.guid: similarity],
                                    excluding: [], now: now, window: 86_400).first
        }
        .max { $0.score != $1.score ? $0.score < $1.score : $0.lane > $1.lane }
        return (best?.score ?? 0, best?.lane ?? "")
    }

    /// Share of `others` that `score` beats, ties counting half. Averaged over the accepted pieces
    /// against the passed ones, this is the ROC AUC (Mann–Whitney): 0.5 is a coin flip.
    public static func outrankShare(_ score: Double, over others: [Double]) -> Double {
        guard !others.isEmpty else { return 0.5 }
        return others.reduce(0) { $0 + ($1 < score ? 1 : $1 == score ? 0.5 : 0) } / Double(others.count)
    }

    /// ROC AUC of positives over negatives.
    public static func auc(positives: [Double], negatives: [Double]) -> Double {
        guard !positives.isEmpty else { return 0.5 }
        return positives.reduce(0) { $0 + outrankShare($1, over: negatives) } / Double(positives.count)
    }
}

extension RolePack {
    /// The pack's lanes as the deck scores them: Medium tag slugs become lane tags.
    public var laneSpecs: [LaneSpec] {
        lanes.map { LaneSpec(name: $0.name, tags: Set($0.sources), theme: $0.theme) }
    }
}
