//
//  IssueChecker.swift
//  ScoutKit
//
//  The newsletter agents choose and write; this code checks. Story IDs must exist and appear once,
//  model text may not carry digits or links, lengths are capped, and Spotlight questions must cite a
//  real post title. Anything that fails is replaced with plain data and flagged for the editor.
//

import Foundation
import FoundationModels

/// One story as the agents see it. Every field comes from the feed.
public struct StoryCard: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var tags: [String]
    public var author: String
    public var handle: String?
    public var link: String
    public var lane: String

    public init(id: String, title: String, subtitle: String, tags: [String], author: String, handle: String?, link: String, lane: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tags = tags
        self.author = author
        self.handle = handle
        self.link = link
        self.lane = lane
    }
}

extension StoryCard: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt("<feed>id: \(id); lane: \(lane); title: \(title); subtitle: \(subtitle); tags: \(tags.joined(separator: ", ")); by \(author)</feed>")
    }
}

/// A writer as the Spotlight agent sees them: their own recent posts, and their site's llms.txt summary if found.
public struct AuthorDigest: Sendable, Hashable {
    public struct Post: Sendable, Hashable {
        public var title: String
        public var snippet: String
        public init(title: String, snippet: String) {
            self.title = title
            self.snippet = snippet
        }
    }

    public var authorKey: String
    public var name: String
    public var handle: String?
    public var posts: [Post]
    public var siteSummary: String?

    public init(authorKey: String, name: String, handle: String?, posts: [Post], siteSummary: String? = nil) {
        self.authorKey = authorKey
        self.name = name
        self.handle = handle
        self.posts = posts
        self.siteSummary = siteSummary
    }
}

extension AuthorDigest: PromptRepresentable {
    public var promptRepresentation: Prompt {
        let list = posts.prefix(6).map { "title: \($0.title); text: \($0.snippet)" }.joined(separator: "\n")
        let site = siteSummary.map { "\nTheir site says: \($0)" } ?? ""
        return Prompt("<feed>Writer: \(name)\n\(list)\(site)</feed>")
    }
}

public struct LineupSection: Sendable, Hashable {
    public var lane: String
    public var storyIDs: [String]
    public init(lane: String, storyIDs: [String]) {
        self.lane = lane
        self.storyIDs = storyIDs
    }
}

public struct SpotlightBlock: Sendable, Hashable {
    public var name: String
    public var handle: String?
    public var intro: String
    public var questions: [String]
    public init(name: String, handle: String?, intro: String, questions: [String]) {
        self.name = name
        self.handle = handle
        self.intro = intro
        self.questions = questions
    }
}

public enum IssueChecker {
    public static let maxBlurbWords = 45
    public static let maxIntroWords = 60

    /// Drops unknown and repeated IDs and empty sections, then files any story the Curator left out
    /// into a section for its own lane, so every chosen story appears exactly once.
    public static func repairLineup(_ sections: [LineupSection], cards: [StoryCard]) -> [LineupSection] {
        let known = Set(cards.map(\.id))
        var used = Set<String>()
        var repaired: [LineupSection] = []
        for section in sections {
            let ids = section.storyIDs.filter { known.contains($0) && used.insert($0).inserted }
            guard !ids.isEmpty else { continue }
            if let index = repaired.firstIndex(where: { $0.lane == section.lane }) {
                repaired[index].storyIDs += ids
            } else {
                repaired.append(LineupSection(lane: section.lane, storyIDs: ids))
            }
        }
        for card in cards where !used.contains(card.id) {
            if let index = repaired.firstIndex(where: { $0.lane == card.lane }) {
                repaired[index].storyIDs.append(card.id)
            } else {
                repaired.append(LineupSection(lane: card.lane, storyIDs: [card.id]))
            }
        }
        return repaired
    }

    /// A blurb is one or two clean sentences within the word cap; otherwise the card's subtitle is used.
    public static func blurb(_ text: String?, card: StoryCard) -> (text: String, flag: String?) {
        let fallback = card.subtitle.isEmpty ? "" : String(card.subtitle.prefix(180))
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return (fallback, "No blurb was written; showing the feed's subtitle.")
        }
        // Numbers are allowed only if the story's own title or subtitle has them; links never.
        if !TextGuard.isGrounded(text, in: card.title + " " + card.subtitle) {
            return (fallback, "The blurb had numbers or links that aren't in the story; showing the feed's subtitle.")
        }
        if words(text) > maxBlurbWords || OutreachCheck.sentences(in: text).count > 2 {
            return (fallback, "The blurb was too long; showing the feed's subtitle.")
        }
        return (text, nil)
    }

    public static func intro(_ text: String?) -> (text: String, flag: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return ("", nil) }
        if !TextGuard.isClean(text) { return ("", "The drafted intro had numbers or links, so it was left blank.") }
        if words(text) > maxIntroWords { return ("", "The drafted intro was over \(maxIntroWords) words, so it was left blank.") }
        return (text, nil)
    }

    public static func title(_ text: String?, fallback: String) -> (text: String, flag: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return (fallback, nil) }
        if !TextGuard.isClean(text) || text.count > 70 { return (fallback, "The drafted title didn't pass the checks; kept the old one.") }
        return (text, nil)
    }

    /// Keeps only questions that cite one of the writer's real post titles (or three words of one), and a clean intro.
    public static func spotlight(intro: String, questions: [String], digest: AuthorDigest) -> (block: SpotlightBlock?, flag: String?) {
        let titles = digest.posts.map(\.title)
        let kept = questions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { question in
            !question.isEmpty && !TextGuard.hasLink(question)
                && titles.contains { title in
                    TextGuard.normalized(question).contains(TextGuard.normalized(title)) || OutreachCheck.sharesPhrase(question, with: title)
                }
        }
        let cleanIntro = TextGuard.isClean(intro) && words(intro) <= maxIntroWords ? intro : ""
        guard !kept.isEmpty else { return (nil, "No interview question cited one of the writer's posts, so the Spotlight was left out.") }
        let flag = kept.count < questions.count ? "Dropped \(questions.count - kept.count) question(s) that didn't cite a real post." : nil
        return (SpotlightBlock(name: digest.name, handle: digest.handle, intro: cleanIntro, questions: Array(kept.prefix(3))), flag)
    }

    /// Titles, links and authors in an issue must match the cards they came from.
    public static func mismatches(_ entries: [IssueContent.Entry], cards: [StoryCard]) -> [String] {
        let byLink = Dictionary(cards.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            guard let card = byLink[entry.url] else { return "“\(entry.title)” has a link Scout didn't store." }
            if card.title != entry.title || card.author != entry.author { return "“\(entry.title)” doesn't match its stored post." }
            return nil
        }
    }

    static func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// Buttons an agent may propose. Only a tap runs them.
public enum ScoutAction: String, CaseIterable, Sendable, Codable {
    case shortlist, addToIssue, draftOutreach, followWriter, muteTag, openPost, askFollowUp
}

public struct Suggestion: Sendable, Hashable {
    public var action: ScoutAction
    public var targetID: String
    public var label: String
    public init(action: ScoutAction, targetID: String, label: String) {
        self.action = action
        self.targetID = targetID
        self.label = label
    }
}

public enum SuggestionFilter {
    /// Code decides what's allowed: targets must be on screen, outreach needs a handle, adding to an issue
    /// needs a draft, labels are four words at most with no digits; duplicates go; at most three remain.
    public static func filter(_ suggestions: [Suggestion], onScreen: Set<String>, withHandle: Set<String>,
                              hasIssue: Bool, alreadyDone: Set<ScoutAction> = []) -> [Suggestion] {
        var seen = Set<String>()
        return Array(suggestions.filter { suggestion in
            let label = suggestion.label.trimmingCharacters(in: .whitespaces)
            guard onScreen.contains(suggestion.targetID), !alreadyDone.contains(suggestion.action),
                  !label.isEmpty, label.split(separator: " ").count <= 4, !TextGuard.hasDigits(label) else { return false }
            if suggestion.action == .draftOutreach && !withHandle.contains(suggestion.targetID) { return false }
            if suggestion.action == .addToIssue && !hasIssue { return false }
            return seen.insert("\(suggestion.action.rawValue)|\(suggestion.targetID)").inserted
        }.prefix(3))
    }
}
