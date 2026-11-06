//
//  Taste.swift
//  ScoutKit
//
//  Learning from swipes happens here, in code: tag weights move up on right swipes and down on
//  left swipes, every weight decays a little each swipe, and nothing leaves -1...1. Cards that read like
//  liked items rise a little; cards that read like passed items sink a little. The model plays no part.
//

import Accelerate
import Foundation

public struct Taste: Codable, Sendable, Equatable {

    public init() {}

    public static let decay = 0.97
    public static let likeStep = 0.25
    public static let passStep = 0.15
    /// How far taste can move a 0...100 match score in either direction.
    public static let maxTagShift = 12.0
    public static let maxSimilarityShift = 10.0
    /// How far looking like passed items can pull a score down; nothing is pushed up by it.
    public static let maxPassShift = 8.0

    public var tagWeights: [String: Double] = [:]
    /// Running mean of the text embeddings of liked items.
    public var centroid: [Double]?
    /// Running mean of the text embeddings of passed items. Optional, so taste saved before it existed still decodes.
    public var passCentroid: [Double]?
    public var likes = 0
    public var passes = 0

    /// One swipe. `embedding` is the item's on-device text vector, when there is one.
    public mutating func record(tags: [String], liked: Bool, embedding: [Double]? = nil) {
        for key in tagWeights.keys { tagWeights[key]! *= Self.decay }
        tagWeights = tagWeights.filter { abs($0.value) > 0.005 }
        for tag in Set(tags) {
            let step = liked ? Self.likeStep : -Self.passStep
            tagWeights[tag] = max(-1, min(1, (tagWeights[tag] ?? 0) + step))
        }
        if liked {
            likes += 1
            if let embedding {
                if let current = centroid, current.count == embedding.count {
                    let n = Double(likes)
                    centroid = zip(current, embedding).map { $0 + ($1 - $0) / n }
                } else {
                    centroid = embedding
                }
            }
        } else {
            passes += 1
            if let embedding {
                if let current = passCentroid, current.count == embedding.count {
                    let n = Double(passes)
                    passCentroid = zip(current, embedding).map { $0 + ($1 - $0) / n }
                } else {
                    passCentroid = embedding
                }
            }
        }
    }

    /// Mean weight of the item's tags that taste has an opinion on, in -1...1; 0 when it has none.
    public func affinity(for tags: [String]) -> Double {
        let known = Set(tags).compactMap { tagWeights[$0] }
        return known.isEmpty ? 0 : known.reduce(0, +) / Double(known.count)
    }

    /// The deterministic blend: the lane score, shifted by tag affinity and by similarity to liked items,
    /// and lowered (only above the 0.5 midpoint) by similarity to passed items.
    public func adjusted(_ score: Int, tags: [String], similarity: Double? = nil, passSimilarity: Double? = nil) -> Int {
        var value = Double(score) + Self.maxTagShift * affinity(for: tags)
        if let similarity { value += Self.maxSimilarityShift * (min(1, max(0, similarity)) - 0.5) * 2 }
        if let passSimilarity { value -= Self.maxPassShift * max(0, min(1, passSimilarity) - 0.5) * 2 }
        return Int(max(0, min(100, value.rounded())))
    }
}

extension Matching {
    /// Re-orders writers by the taste-adjusted score (ties keep the lane order).
    public static func applyTaste(_ candidates: [AuthorCandidate], taste: Taste, similarity: [String: Double] = [:],
                                  passSimilarity: [String: Double] = [:]) -> [AuthorCandidate] {
        candidates.enumerated().map { index, candidate in
            (index, candidate.withScore(taste.adjusted(candidate.score, tags: candidate.topics, similarity: similarity[candidate.authorKey],
                                                       passSimilarity: passSimilarity[candidate.authorKey])))
        }
        .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
        .map(\.1)
    }

    public static func applyTaste(_ stories: [StoryCandidate], taste: Taste, similarity: [String: Double] = [:],
                                  passSimilarity: [String: Double] = [:]) -> [StoryCandidate] {
        stories.enumerated().map { index, story in
            (index, story.withScore(taste.adjusted(story.score, tags: story.post.categories, similarity: similarity[story.id],
                                                   passSimilarity: passSimilarity[story.id])))
        }
        .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
        .map(\.1)
    }
}

extension AuthorCandidate {
    public func withScore(_ score: Int) -> AuthorCandidate {
        var copy = AuthorCandidate(authorKey: authorKey, name: name, handle: handle, bestPost: bestPost, posts: posts,
                                   topics: topics, signals: signals, score: score, lane: lane)
        copy.avatarURL = avatarURL
        return copy
    }
}

extension StoryCandidate {
    public func withScore(_ score: Int) -> StoryCandidate {
        StoryCandidate(post: post, lanesSurfacing: lanesSurfacing, overlapCount: overlapCount, semantic: semantic, score: score,
                       lane: lane)
    }
}
