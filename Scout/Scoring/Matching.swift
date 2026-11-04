//
//  Matching.swift
//  Scout
//
//  Code decides every score, count and order. The model never sees or writes these numbers.
//

import Foundation

/// The lane being matched against, as plain values.
struct LaneSpec: Sendable, Hashable {
    var name: String
    var tags: Set<String>
    var theme: String
}

/// A post as plain values, so scoring runs off the main actor and in tests without SwiftData.
struct PostRecord: Sendable, Hashable {
    var guid: String
    var title: String
    var link: String
    var snippet: String
    var authorKey: String
    var authorName: String
    var handle: String?
    var categories: [String]
    var foundUnder: [String]
    var published: Date
    var readingMinutes: Int?

    var topics: Set<String> { Set(categories).union(foundUnder) }
}

struct MatchSignals: Sendable, Hashable {
    /// Cosine similarity of the writer's text to the lane theme, clamped to 0...1.
    var semantic: Double
    /// Share of the lane's tags (up to three) the writer's posts carry.
    var overlap: Double
    var postsInWindow: Int
    var hoursSinceLatest: Double
}

struct MatchWeights: Sendable, Hashable, Codable {
    var semantic = 0.35
    var overlap = 0.30
    var frequency = 0.20
    var recency = 0.15
}

struct AuthorCandidate: Identifiable, Sendable, Hashable {
    var id: String { authorKey }
    let authorKey: String
    let name: String
    let handle: String?
    let bestPost: PostRecord
    let posts: [PostRecord]
    /// Most frequent topics across the writer's posts, most common first.
    let topics: [String]
    let signals: MatchSignals
    let score: Int
    var avatarURL: URL?

    var latest: Date { posts.map(\.published).max() ?? bestPost.published }

    /// The feed text the model may draw on: titles and snippets, newest first.
    var sourceText: String {
        posts.prefix(4).map { "\($0.title). \($0.snippet)" }.joined(separator: "\n")
    }
}

enum Matching {

    static func overlap(_ topics: Set<String>, lane: Set<String>) -> Double {
        guard !lane.isEmpty else { return 0 }
        return min(1, Double(topics.intersection(lane).count) / Double(min(3, lane.count)))
    }

    /// Three posts in the window is the most frequency can add.
    static func frequency(_ posts: Int) -> Double {
        min(1, Double(max(0, posts)) / 3)
    }

    /// Halves roughly every two days.
    static func recency(hours: Double) -> Double {
        exp(-max(0, hours) / 72)
    }

    static func score(_ s: MatchSignals, weights: MatchWeights = MatchWeights()) -> Int {
        let total = weights.semantic + weights.overlap + weights.frequency + weights.recency
        guard total > 0 else { return 0 }
        let value = weights.semantic * min(1, max(0, s.semantic)) + weights.overlap * s.overlap
            + weights.frequency * frequency(s.postsInWindow) + weights.recency * recency(hours: s.hoursSinceLatest)
        return Int((value / total * 100).rounded())
    }

    /// The post most on-topic for the lane, then longest, then newest.
    static func bestPost(_ posts: [PostRecord], lane: LaneSpec) -> PostRecord? {
        posts.max { a, b in
            let (oa, ob) = (a.topics.intersection(lane.tags).count, b.topics.intersection(lane.tags).count)
            if oa != ob { return oa < ob }
            if (a.readingMinutes ?? 0) != (b.readingMinutes ?? 0) { return (a.readingMinutes ?? 0) < (b.readingMinutes ?? 0) }
            if a.published != b.published { return a.published < b.published }
            return a.guid > b.guid
        }
    }

    static func topTopics(_ posts: [PostRecord], limit: Int = 4) -> [String] {
        let counts = Dictionary(posts.flatMap(\.categories).map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
    }

    /// A post on a publication's own domain has no @handle, so its author key is `name:<creator>`.
    /// When exactly one handle is known for that name, file the post under the handle.
    static func unifyAuthors(_ posts: [PostRecord]) -> [PostRecord] {
        let handlesByName = Dictionary(grouping: posts.compactMap { post in post.handle.map { (post.authorName, $0) } }, by: \.0)
            .mapValues { Set($0.map(\.1)) }
        return posts.map { post in
            guard post.handle == nil, let handles = handlesByName[post.authorName], handles.count == 1 else { return post }
            var merged = post
            merged.handle = handles.first
            merged.authorKey = handles.first!
            return merged
        }
    }

    /// Writers who posted in the window, minus decided and blocked ones, highest score first
    /// (ties: newest post, then name).
    static func candidates(from posts: [PostRecord], lane: LaneSpec, semantic: [String: Double],
                           excluding: Set<String>, now: Date, window: TimeInterval,
                           weights: MatchWeights = MatchWeights()) -> [AuthorCandidate] {
        let cutoff = now.addingTimeInterval(-window)
        let recent = unifyAuthors(posts).filter { $0.published >= cutoff && !excluding.contains($0.authorKey) }
        return Dictionary(grouping: recent, by: \.authorKey).compactMap { key, posts -> AuthorCandidate? in
            guard let best = bestPost(posts, lane: lane) else { return nil }
            let sorted = posts.sorted { $0.published > $1.published }
            let signals = MatchSignals(
                semantic: semantic[key] ?? 0,
                overlap: overlap(Set(posts.flatMap(\.topics)), lane: lane.tags),
                postsInWindow: posts.count,
                hoursSinceLatest: now.timeIntervalSince(sorted[0].published) / 3600)
            return AuthorCandidate(authorKey: key, name: best.authorName, handle: best.handle, bestPost: best,
                                   posts: sorted, topics: topTopics(posts), signals: signals,
                                   score: score(signals, weights: weights))
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.latest != $1.latest { return $0.latest > $1.latest }
            return $0.name < $1.name
        }
    }
}

/// Checks on model-written text. The model may phrase; it may not add numbers or links.
enum TextGuard {
    static func hasDigits(_ text: String) -> Bool {
        text.contains { $0.isNumber }
    }

    static func hasLink(_ text: String) -> Bool {
        text.range(of: #"(https?://|www\.|\b[a-z0-9-]+\.(com|io|dev|org|net|app|pub|co)\b)"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isClean(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !hasDigits(trimmed) && !hasLink(trimmed)
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "[\u{2018}\u{2019}]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[\u{201C}\u{201D}]", with: "\"", options: .regularExpression)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// True when `phrase` (two words or more) appears in `source`, ignoring case, spacing and quote style.
    static func quotes(_ phrase: String, from source: String) -> Bool {
        let trimmed = normalized(phrase).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        guard trimmed.split(separator: " ").count >= 2 else { return false }
        return normalized(source).contains(trimmed)
    }
}
