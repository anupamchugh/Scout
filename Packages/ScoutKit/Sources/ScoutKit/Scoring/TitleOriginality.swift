//
//  TitleOriginality.swift
//  ScoutKit
//
//  How original a publication's titles are against each other, from Natural Language sentence embeddings: each title's
//  nearest neighbour among the others, and pairs so close they read as the same idea. Vectors come from
//  NLEmbedding (no text generation); similarity, thresholds and counts are code. Measures repetition of ideas in
//  titles, not the writing behind them.
//

import Foundation

public struct TitlePair: Sendable, Equatable {
    public var first: String
    public var second: String
    public var similarity: Double
}

public struct TitleOriginalityReport: Sendable, Equatable {
    public var titles: Int
    /// Titles the embedding model could not embed (empty or out of vocabulary).
    public var unembedded: Int
    /// Mean cosine similarity of each title to its nearest other title (higher = more repetitive).
    public var meanNearest: Double?
    /// Share of embedded titles whose nearest other title is at or above `threshold`.
    public var nearDuplicateShare: Double?
    public var threshold: Double
    /// The closest pairs, most similar first.
    public var closestPairs: [TitlePair]
}

public enum TitleOriginality {
    /// Cosine similarity at which two titles count as one idea or one template. Checked against real pairs on
    /// 8 Nov 2026: at 0.80 and above they were series parts or the same headline formula ("N Python libraries for…",
    /// "Junior devs … senior devs use these N … patterns"); below about 0.79 they were merely related topics.
    public static let defaultThreshold = 0.8

    /// Pure: from vectors (nil = not embedded) to the report.
    public static func report(titles: [String], vectors: [[Double]?], threshold: Double = defaultThreshold,
                              pairsToKeep: Int = 8) -> TitleOriginalityReport {
        let embedded = zip(titles, vectors).compactMap { title, vector in vector.map { (title, $0) } }
        var nearest: [Double] = []
        var pairs: [TitlePair] = []
        for i in embedded.indices {
            var best = -1.0
            for j in embedded.indices where j != i {
                let s = Embedder.cosine(embedded[i].1, embedded[j].1)
                best = max(best, s)
                if j > i { pairs.append(TitlePair(first: embedded[i].0, second: embedded[j].0, similarity: s)) }
            }
            if embedded.count > 1 { nearest.append(best) }
        }
        let close = pairs.sorted { $0.similarity > $1.similarity }.prefix(pairsToKeep)
        return TitleOriginalityReport(
            titles: titles.count, unembedded: titles.count - embedded.count,
            meanNearest: nearest.isEmpty ? nil : nearest.reduce(0, +) / Double(nearest.count),
            nearDuplicateShare: nearest.isEmpty ? nil : Double(nearest.filter { $0 >= threshold }.count) / Double(nearest.count),
            threshold: threshold, closestPairs: Array(close))
    }

    /// With Natural Language's English sentence embedding; titles it can't embed are counted, not guessed.
    public static func report(titles: [String], threshold: Double = defaultThreshold) -> TitleOriginalityReport {
        report(titles: titles, vectors: titles.map { Embedder.vector($0) }, threshold: threshold)
    }
}
