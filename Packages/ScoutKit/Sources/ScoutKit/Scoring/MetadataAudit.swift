//
//  MetadataAudit.swift
//  ScoutKit
//
//  What a post's title, tags and subtitle say about its packaging, computed in code: how many tags it uses (Medium
//  allows five), how many share a word with the title, trending tags the title and text never mention, and whether
//  the subtitle is missing or generic. These describe packaging only; they never score the writing.
//

import Foundation

public struct MetadataAudit: Sendable, Equatable, Codable {
    public var tagCount: Int
    /// Medium's maximum of five tags used.
    public var atTagLimit: Bool
    /// Tags with at least one word in the title.
    public var tagsInTitle: Int
    /// Trending tags (AI and similar) whose words appear in neither the title nor the article text read.
    public var trendingTagsUnmentioned: [String]
    public var hasSubtitle: Bool
    /// The subtitle restates that an article exists ("This article explains…") instead of saying anything.
    public var genericSubtitle: Bool

    public static let tagLimit = 5

    /// Tags that attract readers on their own; flagged only when nothing in the title or text mentions them.
    public static let trendingTags: [String: [String]] = [
        "artificial-intelligence": ["ai", "artificial", "intelligence", "llm", "model", "agent"],
        "ai": ["ai", "llm", "model", "agent"],
        "generative-ai-tools": ["generative", "ai", "llm", "gpt"],
        "chatgpt": ["chatgpt", "gpt", "openai"],
        "llm": ["llm", "language", "model"],
        "machine-learning": ["machine", "learning", "model", "ml"],
        "programming": ["programming", "code", "coding", "program"],
        "technology": ["technology", "tech"],
    ]

    static let genericSubtitleOpeners = [
        "the article contains", "this article", "in this article", "this post", "in this post", "a guide to",
        "an introduction to", "everything you need to know",
    ]

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    public static func audit(title: String, tags: [String], subtitle: String?, articleText: String?) -> MetadataAudit {
        let titleWords = words(title)
        let textWords = words(articleText ?? "")
        let inTitle = tags.filter { tag in !Set(tag.split(separator: "-").map(String.init)).isDisjoint(with: titleWords) }.count
        // Only with the article text: a title alone is too short to say a tag is never mentioned.
        let unmentioned = articleText == nil ? [] : tags.filter { tag in
            guard let cues = trendingTags[tag] else { return false }
            let seen = titleWords.union(textWords)
            return cues.allSatisfy { !seen.contains($0) }
        }
        let sub = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowerSub = sub.lowercased()
        return MetadataAudit(
            tagCount: tags.count, atTagLimit: tags.count >= tagLimit, tagsInTitle: inTitle,
            trendingTagsUnmentioned: unmentioned, hasSubtitle: !sub.isEmpty,
            genericSubtitle: genericSubtitleOpeners.contains { lowerSub.hasPrefix($0) })
    }

    /// The first heading in the article's Markdown (Medium's subtitle is the first h3/h4 under the title).
    public static func subtitle(fromMarkdown markdown: String) -> String? {
        for line in markdown.split(separator: "\n").prefix(12) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let text = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : text
            }
        }
        return nil
    }
}
