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
    var imageURL: String? = nil

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

/// One story (post) on the deck, scored against the lane in code.
struct StoryCandidate: Identifiable, Sendable, Hashable {
    var id: String { post.guid }
    let post: PostRecord
    /// How many of your lanes' tag feeds surfaced this post.
    let lanesSurfacing: Int
    let overlapCount: Int
    let semantic: Double
    let score: Int
}

struct StoryWeights: Sendable, Hashable, Codable {
    var semantic = 0.35
    var overlap = 0.30
    var surfaced = 0.15
    var recency = 0.20
}

enum Matching {

    /// Lanes whose tags include a feed that listed the post: a post found through several lanes is a stronger signal.
    static func lanesSurfacing(_ post: PostRecord, lanes: [LaneSpec]) -> Int {
        lanes.filter { !$0.tags.isDisjoint(with: post.foundUnder) }.count
    }

    /// Stories posted in the window, highest score first (ties: more lane tags matched, newest, title).
    static func stories(from posts: [PostRecord], lane: LaneSpec, lanes: [LaneSpec], semantic: [String: Double],
                        excluding: Set<String>, now: Date, window: TimeInterval,
                        weights: StoryWeights = StoryWeights()) -> [StoryCandidate] {
        let cutoff = now.addingTimeInterval(-window)
        let total = weights.semantic + weights.overlap + weights.surfaced + weights.recency
        return posts.filter { $0.published >= cutoff && !excluding.contains($0.guid) && !excluding.contains($0.authorKey) }
            .map { post in
                let shared = post.topics.intersection(lane.tags).count
                let surfacing = lanesSurfacing(post, lanes: lanes)
                let similarity = min(1, max(0, semantic[post.guid] ?? 0))
                let value = weights.semantic * similarity
                    + weights.overlap * overlap(post.topics, lane: lane.tags)
                    + weights.surfaced * min(1, Double(surfacing) / Double(max(1, min(3, lanes.count))))
                    + weights.recency * recency(hours: now.timeIntervalSince(post.published) / 3600)
                return StoryCandidate(post: post, lanesSurfacing: surfacing, overlapCount: shared, semantic: similarity,
                                      score: total > 0 ? Int((value / total * 100).rounded()) : 0)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.overlapCount != $1.overlapCount { return $0.overlapCount > $1.overlapCount }
                if $0.post.published != $1.post.published { return $0.post.published > $1.post.published }
                return $0.post.title < $1.post.title
            }
    }

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

/// Tag pairs that appear on the same post, counted across the window, as suggested lanes.
struct TagPair: Hashable, Sendable, Comparable {
    let first: String
    let second: String

    init(_ a: String, _ b: String) {
        (first, second) = a < b ? (a, b) : (b, a)
    }

    var label: String { "\(first) + \(second)" }

    static func < (lhs: TagPair, rhs: TagPair) -> Bool { (lhs.first, lhs.second) < (rhs.first, rhs.second) }
}

enum TagCooccurrence {
    /// Each post counts a pair once, however its tags repeat. Ordered by count, then alphabetically.
    static func count(_ posts: [PostRecord]) -> [(pair: TagPair, count: Int)] {
        var counts: [TagPair: Int] = [:]
        for post in posts {
            let tags = Array(Set(post.categories)).sorted()
            for i in tags.indices {
                for j in tags.indices where j > i { counts[TagPair(tags[i], tags[j]), default: 0] += 1 }
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.pair < $1.pair }
    }

    /// How many posts carry each tag, most common first.
    static func tagCounts(_ posts: [PostRecord]) -> [(tag: String, count: Int)] {
        Dictionary(posts.flatMap { Set($0.categories) }.map { ($0, 1) }, uniquingKeysWith: +)
            .map { ($0.key, $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// The strongest pairs seen on at least `minimum` posts that aren't already exactly a lane's tags.
    static func suggestions(_ posts: [PostRecord], existing: [Set<String>], minimum: Int = 3, limit: Int = 5) -> [(pair: TagPair, count: Int)] {
        Array(count(posts).filter { entry in
            entry.count >= minimum && !existing.contains { $0.isSuperset(of: [entry.pair.first, entry.pair.second]) }
        }.prefix(limit))
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
