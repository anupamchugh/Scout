//
//  Embedder.swift
//  Scout
//

import Accelerate
import Foundation
import NaturalLanguage

/// On-device text similarity for the semantic match signal.
enum Embedder {

    /// Cosine similarity of each text to `theme`, clamped to 0...1. Empty when no embedding is available.
    @concurrent
    static func similarities(_ texts: [String: String], to theme: String) async -> [String: Double] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let target = embedding.vector(for: theme) else { return [:] }
        var result: [String: Double] = [:]
        for (key, text) in texts {
            if Task.isCancelled { return [:] }
            guard let vector = embedding.vector(for: text) else { continue }
            result[key] = max(0, min(1, cosine(vector, target)))
        }
        return result
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        let denominator = (vDSP.sumOfSquares(a) * vDSP.sumOfSquares(b)).squareRoot()
        return denominator == 0 ? 0 : vDSP.dot(a, b) / denominator
    }
}
