//
//  HNPeople.swift
//  ScoutKit
//
//  Hacker News people from the official API (hacker-news.firebaseio.com), read-only: the user record and
//  their recent submissions, fetched six at a time and cached. HNAuthorStats is plain Swift; the model
//  only reads it.
//

import Foundation
import FoundationModels

public struct HNUser: Sendable, Equatable, Codable {
    public let id: String
    public let created: TimeInterval
    public let karma: Int
    /// HTML; run through `HNTextCleaner`.
    public let about: String?
    public let submitted: [Int]?
}

public struct HNAuthorStats: Sendable, Equatable {
    public let user: String
    public let karma: Int
    public let joined: Date
    public let submissionsPerWeek: Double
    public let stories: Int
    public let comments: Int
    public let showHN: Int
    public let topDomains: [(domain: String, count: Int)]
    /// Title words standing in for tags, stop words removed.
    public let titleWords: [(word: String, count: Int)]
    public let medianPoints: Int?
    public let medianComments: Int?
    /// The `about` text, cleaned of HTML.
    public let about: String

    public static func == (lhs: HNAuthorStats, rhs: HNAuthorStats) -> Bool {
        lhs.user == rhs.user && lhs.karma == rhs.karma && lhs.submissionsPerWeek == rhs.submissionsPerWeek
            && lhs.stories == rhs.stories && lhs.comments == rhs.comments && lhs.showHN == rhs.showHN
            && lhs.topDomains.map(\.domain) == rhs.topDomains.map(\.domain) && lhs.titleWords.map(\.word) == rhs.titleWords.map(\.word)
            && lhs.medianPoints == rhs.medianPoints && lhs.medianComments == rhs.medianComments && lhs.about == rhs.about
    }
}

public enum HNStats {
    static let stopWords: Set<String> = ["the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with", "is", "are", "was",
                                         "it", "its", "you", "your", "i", "my", "we", "our", "how", "why", "what", "show", "hn",
                                         "ask", "from", "by", "at", "as", "be", "this", "that", "new", "now", "can", "not", "do",
                                         "does", "vs", "about", "into", "using", "use", "made", "built", "launch"]

    /// Computed from the user record and the items they submitted.
    public static func stats(user: HNUser, items: [HNItem], now: Date = .now) -> HNAuthorStats {
        let live = items.filter { !$0.isRemoved }
        let stories = live.filter(\.isStory)
        let comments = live.filter { $0.type == "comment" }
        let dates = live.compactMap(\.date)
        let span = (dates.max().map { last in dates.min().map { last.timeIntervalSince($0) } ?? 0 } ?? 0) / 86_400
        let perWeek = live.count < 2 || span <= 0 ? Double(live.count) : Double(live.count) / span * 7

        var domains: [String: Int] = [:]
        for story in stories {
            if let host = story.url.flatMap(URL.init(string:))?.host()?.replacingOccurrences(of: "www.", with: "") {
                domains[host, default: 0] += 1
            }
        }
        var words: [String: Int] = [:]
        for story in stories {
            let tokens = (story.title ?? "").lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
            for token in Set(tokens) { words[token, default: 0] += 1 }
        }
        func median(_ values: [Int]) -> Int? {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return nil }
            return sorted.count.isMultiple(of: 2) ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
        }
        func ranked(_ counts: [String: Int]) -> [(String, Int)] {
            counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map { ($0.key, $0.value) }
        }
        return HNAuthorStats(
            user: user.id, karma: user.karma, joined: Date(timeIntervalSince1970: user.created),
            submissionsPerWeek: perWeek, stories: stories.count, comments: comments.count,
            showHN: stories.filter { ($0.title ?? "").hasPrefix("Show HN") }.count,
            topDomains: ranked(domains).map { (domain: $0.0, count: $0.1) },
            titleWords: ranked(words).map { (word: $0.0, count: $0.1) },
            medianPoints: median(stories.compactMap(\.score)), medianComments: median(stories.compactMap(\.descendants)),
            about: HNTextCleaner.plainText(fromHTML: user.about))
    }
}

extension HNAuthorStats: PromptRepresentable {
    /// What the model may read about an HN poster; the card shows the numbers itself.
    public var promptRepresentation: Prompt {
        Prompt("""
            Hacker News poster facts, computed by the app: \(stories) stories and \(comments) comments recently; \
            \(showHN) Show HN posts; links most to \(topDomains.map(\.domain).joined(separator: ", ")); \
            common title words \(titleWords.map(\.word).joined(separator: ", ")).
            <feed>About: \(about.isEmpty ? "none" : String(about.prefix(400)))</feed>
            """)
    }
}

/// Users and items from the HN API, cached so cards and Siri share one download.
public actor HNCache {
    public static let shared = HNCache()

    private var users: [String: HNUser] = [:]
    private var items: [Int: HNItem] = [:]
    private var lastFailure: Date?
    private let transport: any URLTransport
    private let base = URL(string: "https://hacker-news.firebaseio.com/v0")!

    public init(transport: any URLTransport = SessionTransport()) {
        self.transport = transport
    }

    /// After a failure, wait a minute before asking the API again (back off on errors).
    private var isBackingOff: Bool {
        lastFailure.map { Date.now.timeIntervalSince($0) < 60 } ?? false
    }

    public func user(_ id: String) async -> HNUser? {
        if let user = users[id] { return user }
        guard !isBackingOff, let user: HNUser = await get("user/\(id).json") else { return nil }
        users[id] = user
        return user
    }

    public func item(_ id: Int) async -> HNItem? {
        if let item = items[id] { return item }
        guard !isBackingOff, let item: HNItem = await get("item/\(id).json") else { return nil }
        items[id] = item
        return item
    }

    /// Up to `limit` of the user's most recent submissions, six requests at a time; cancelled with the caller.
    public func recentItems(of user: HNUser, limit: Int = 30) async -> [HNItem] {
        let ids = Array((user.submitted ?? []).prefix(limit))
        return await items(ids)
    }

    public func items(_ ids: [Int]) async -> [HNItem] {
        var found: [Int: HNItem] = [:]
        var missing: [Int] = []
        for id in ids {
            if let item = items[id] { found[id] = item } else { missing.append(id) }
        }
        let fetched = await withTaskGroup(of: HNItem?.self) { group in
            var queue = missing.makeIterator()
            for _ in 0..<6 {
                guard let id = queue.next() else { break }
                group.addTask { await self.item(id) }
            }
            var result: [HNItem] = []
            for await item in group {
                if let item { result.append(item) }
                if Task.isCancelled { group.cancelAll(); break }
                if let id = queue.next() { group.addTask { await self.item(id) } }
            }
            return result
        }
        for item in fetched { found[item.id] = item }
        return ids.compactMap { found[$0] }
    }

    public func stats(for userID: String, limit: Int = 30) async -> HNAuthorStats? {
        guard let user = await user(userID) else { return nil }
        return HNStats.stats(user: user, items: await recentItems(of: user, limit: limit))
    }

    private func get<Value: Decodable>(_ path: String) async -> Value? {
        do {
            let response = try await transport.send(URLRequest(url: base.appendingPathComponent(path)))
            guard (200..<300).contains(response.statusCode) else {
                lastFailure = .now
                return nil
            }
            return try? JSONDecoder().decode(Value.self, from: response.data)
        } catch {
            if !(error is CancellationError) { lastFailure = .now }
            return nil
        }
    }
}
