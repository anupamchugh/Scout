//
//  TopicTags.swift
//  ScoutKit
//
//  A topic in plain words ("Apple tech", "blogging and newsletters") becomes a lane's tags. The model may
//  suggest tag names; code turns them into Medium slugs, keeps only those whose feed has posts, and ranks
//  tags Scout already knows by on-device similarity to the topic. Nothing a model says becomes a tag unchecked.
//

import Foundation

public enum TopicTags {

    /// A Medium tag slug: lowercase words joined by hyphens, letters and digits only. Nil when nothing is left.
    public static func slug(_ text: String) -> String? {
        let words = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let slug = words.joined(separator: "-")
        return slug.count <= 40 ? slug : nil
    }

    /// Candidates to check: the model's guesses, then the topic's own words and phrase, as unique slugs in order.
    /// Short filler words ("and", "the") are never candidates on their own.
    public static func candidates(topic: String, guesses: [String], limit: Int = 10) -> [String] {
        let stop: Set<String> = ["and", "the", "for", "with", "about", "of", "in", "on", "to", "a", "an", "or"]
        let topicWords = topic.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !stop.contains($0.lowercased()) && $0.count > 1 }
        var seen = Set<String>()
        return (guesses + [topic] + topicWords).compactMap(slug)
            .filter { !stop.contains($0) && seen.insert($0).inserted }
            .prefix(limit).map { $0 }
    }

    /// Known tags ranked by meaning against the topic (cosine similarity of on-device sentence embeddings),
    /// above `threshold`, best first. Tags are compared as words ("engineering-management" → "engineering management").
    public static func nearby(_ topic: String, among tags: [String], threshold: Double = 0.55, limit: Int = 10) -> [(tag: String, similarity: Double)] {
        guard let target = Embedder.vector(topic) else { return [] }
        return tags.compactMap { tag -> (String, Double)? in
            guard let vector = Embedder.vector(tag.replacingOccurrences(of: "-", with: " ")), vector.count == target.count else { return nil }
            let similarity = Embedder.cosine(vector, target)
            return similarity >= threshold ? (tag, similarity) : nil
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        .prefix(limit).map { (tag: $0.0, similarity: $0.1) }
    }

    /// A checked candidate: how many posts its Medium feed returned just now.
    public struct Checked: Sendable, Hashable {
        public let tag: String
        public let posts: Int
        public init(tag: String, posts: Int) {
            self.tag = tag
            self.posts = posts
        }
        public var isLive: Bool { posts > 0 }
    }

    /// The lane's tags: live checked tags (most posts first), then nearby known tags, unique, at most `limit`.
    public static func laneTags(checked: [Checked], nearby: [String], limit: Int = 6) -> [String] {
        var seen = Set<String>()
        let live = checked.filter(\.isLive).sorted { $0.posts != $1.posts ? $0.posts > $1.posts : $0.tag < $1.tag }.map(\.tag)
        return (live + nearby).filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }
}
