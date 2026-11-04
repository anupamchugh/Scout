//
//  AuthorStats.swift
//  Scout
//
//  Writer statistics come from this plain function over the writer's own feed, never from the model.
//

import Foundation
import FoundationModels

enum TitlePattern: String, CaseIterable, Sendable, Codable {
    case youYour = "you/your problem"
    case comparison = "comparison"
    case fixHowTo = "fix / how-to"
    case careerGuide = "career guide"
    case mythThenFact = "myth then fact"
    case plain = "plain"

    /// Each title gets the first rule that matches, in this order.
    static func classify(_ title: String) -> TitlePattern {
        let lower = title.lowercased()
        func matches(_ pattern: String) -> Bool { lower.range(of: pattern, options: .regularExpression) != nil }

        if lower.hasPrefix("you ") || lower.hasPrefix("your ") { return .youYour }
        if matches(#"\bvs\.?\b"#) || lower.contains("difference between") { return .comparison }
        if matches(#"\bhow to\b"#) || matches(#"\bfix(es|ed|ing)?\b"#) || matches(#"\bwhy\b.*\bhappens\b"#) { return .fixHowTo }
        if matches(#"^from .+ to .+"#) || lower.contains("what you need to learn") { return .careerGuide }
        if matches(#"\b(is not|isn't|does not|doesn't)\b"#) { return .mythThenFact }
        let sentences = title.split(whereSeparator: { ".?!".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if sentences.count >= 2 && sentences.allSatisfy({ $0.split(separator: " ").count <= 8 }) { return .mythThenFact }
        return .plain
    }
}

struct AuthorStats: Sendable, Equatable {
    let postCount: Int
    /// Posts divided by the days between the first and last post, times seven.
    let postsPerWeek: Double
    /// Median word count of the full text, when the feed carries it.
    let typicalWords: Int?
    let topTags: [(tag: String, count: Int)]
    let titlePatterns: [TitlePattern: Int]

    var typicalReadingMinutes: Int? { typicalWords.map { max(1, Int((Double($0) / 265).rounded(.up))) } }

    /// The commonest title shapes, most frequent first (ties alphabetical), ignoring plain titles.
    var leadingPatterns: [TitlePattern] {
        titlePatterns.filter { $0.key != .plain }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .map(\.key)
    }

    static func == (lhs: AuthorStats, rhs: AuthorStats) -> Bool {
        lhs.postCount == rhs.postCount && lhs.postsPerWeek == rhs.postsPerWeek && lhs.typicalWords == rhs.typicalWords
            && lhs.topTags.map(\.tag) == rhs.topTags.map(\.tag) && lhs.topTags.map(\.count) == rhs.topTags.map(\.count)
            && lhs.titlePatterns == rhs.titlePatterns
    }
}

func stats(for posts: [FeedItem]) -> AuthorStats {
    let dates = posts.map(\.published)
    let days = (dates.max().map { last in dates.min().map { last.timeIntervalSince($0) } ?? 0 } ?? 0) / 86_400
    let perWeek = posts.count < 2 || days <= 0 ? Double(posts.count) : Double(posts.count) / days * 7

    let words = posts.compactMap(\.wordCount).sorted()
    let median: Int? = words.isEmpty ? nil
        : words.count.isMultiple(of: 2) ? (words[words.count / 2 - 1] + words[words.count / 2]) / 2 : words[words.count / 2]

    var tagCounts: [String: Int] = [:]
    for post in posts {
        for tag in Set(post.categories) { tagCounts[tag, default: 0] += 1 }
    }
    let tags: [(tag: String, count: Int)] = tagCounts
        .map { (tag: $0.key, count: $0.value) }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    let patterns = Dictionary(posts.map { (TitlePattern.classify($0.title), 1) }, uniquingKeysWith: +)

    return AuthorStats(postCount: posts.count, postsPerWeek: perWeek, typicalWords: median,
                       topTags: Array(tags.prefix(5)), titlePatterns: patterns)
}

extension AuthorStats: PromptRepresentable {
    /// What the model may read about the writer. It may describe these; the card shows the numbers itself.
    var promptRepresentation: Prompt {
        Prompt("""
            Writer facts, computed by the app: about \(String(format: "%.1f", postsPerWeek)) posts a week; \
            usual length \(typicalWords.map { "\($0) words" } ?? "unknown"); \
            top tags \(topTags.map(\.tag).joined(separator: ", ")); \
            common title shapes \(leadingPatterns.map(\.rawValue).joined(separator: ", ")).
            """)
    }
}
