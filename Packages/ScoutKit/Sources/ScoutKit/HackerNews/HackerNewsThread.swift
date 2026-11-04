//
//  HackerNewsThread.swift
//  ScoutKit
//
//  Copied from anupamchugh/Feedloom, Packages/FeedloomSources/Sources/FeedloomSources/HackerNewsThread.swift,
//  commit 64e548c (the code began in Distill). URLTransport and PublicURLPolicy came from ThreadmarkConnectors; Scout defines a minimal transport below.
//
// ABOUTME: Read-only Hacker News reader on the official Hacker News API: story lists, one item, and a thread read breadth-first
// up to a comment cap. Ported from Distill's HN client onto Feedloom's transport and URL policy. Facts such as points
// and comment counts come from these values and are rendered from data, never from a model.

import Foundation

public struct HNItem: Sendable, Equatable, Decodable, Identifiable {
    public let id: Int
    public let type: String?
    /// The poster. Scout shows it on HN cards and builds per-person stats from the public API (owner-approved);
    /// thread briefs still never send usernames to the model.
    public let by: String?
    public let time: TimeInterval?
    public let title: String?
    /// HTML. Run through `HNTextCleaner` before reading.
    public let text: String?
    public let url: String?
    public let kids: [Int]?
    public let deleted: Bool?
    public let dead: Bool?
    public let score: Int?
    public let descendants: Int?

    public var isStory: Bool { type == "story" }
    public var isRemoved: Bool { deleted == true || dead == true }
    public var date: Date? { time.map { Date(timeIntervalSince1970: $0) } }
    public var permalink: URL { HackerNewsLink.permalink(forItem: id) }
}

public struct HNThread: Sendable, Equatable {
    public let story: HNItem
    /// Live comments in breadth-first order (top-level first), at most the cap the reader was given.
    public let comments: [HNItem]
    /// True when the read stopped early because a request failed, so the comments are a sample of a sample.
    public let isPartial: Bool

    public init(story: HNItem, comments: [HNItem], isPartial: Bool = false) {
        self.story = story
        self.comments = comments
        self.isPartial = isPartial
    }
}

public struct HNStoryList: Sendable, Equatable {
    public let stories: [HNItem]
    /// Stories whose request failed (not ones that no longer exist). The list shows "Some stories didn't load" when above zero.
    public let failedCount: Int
}

public enum HNList: String, CaseIterable, Sendable, Identifiable {
    case top, new, best, ask, show

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .top: "Top"
        case .new: "New"
        case .best: "Best"
        case .ask: "Ask"
        case .show: "Show"
        }
    }
    var endpoint: String { "\(rawValue)stories.json" }
}

public enum HackerNewsError: Error, Equatable, Sendable {
    case http(Int)
    case notFound
    case notAStory
    case unreadable
    case privateHost
}

public enum HackerNewsLink {
    /// The item id of a `news.ycombinator.com/item?id=` link, or nil for any other address.
    public static func itemID(from link: String) -> Int? {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https" || components.scheme?.lowercased() == "http",
              components.host?.lowercased() == "news.ycombinator.com",
              components.path == "/item",
              let value = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = Int(value), id > 0 else { return nil }
        return id
    }

    public static func permalink(forItem id: Int) -> URL {
        URL(string: "https://news.ycombinator.com/item?id=\(id)")!
    }
}

public struct HackerNewsReader<Transport: URLTransport>: Sendable {
    public static var defaultBaseURL: URL { URL(string: "https://hacker-news.firebaseio.com/v0")! }
    static var batchSize: Int { 10 }

    private let transport: Transport
    private let baseURL: URL

    /// Throws `.privateHost` unless the base URL is https (Feedloom's fuller `PublicURLPolicy` is not copied).
    public init(transport: Transport, baseURL: URL = Self.defaultBaseURL) throws {
        guard baseURL.scheme == "https" else { throw HackerNewsError.privateHost }
        self.transport = transport
        self.baseURL = baseURL
    }

    /// The first `limit` live stories of a list, in list order. Ids that are not stories (jobs, polls) are skipped.
    public func stories(_ list: HNList, limit: Int) async throws -> HNStoryList {
        let ids = try await decode([Int].self, path: list.endpoint) ?? []
        let (items, failure, failed) = try await items(Array(ids.prefix(max(limit, 0))))
        if let failure, items.isEmpty { throw failure }
        return HNStoryList(stories: items.filter { $0.isStory && !$0.isRemoved }, failedCount: failed)
    }

    public func item(id: Int) async throws -> HNItem? {
        try await decode(HNItem.self, path: "item/\(id).json")
    }

    /// The story plus its comments, breadth-first, stopping at `maxComments`. Dead and deleted comments are skipped
    /// and do not count towards the cap, so a total fetch ceiling (4x the cap) bounds a heavily moderated tree.
    /// A comment that fails to load does not discard the rest: once something was read, the first failure ends the read
    /// and the partial thread is returned. A failure before any comment was read is thrown.
    public func thread(storyID: Int, maxComments: Int) async throws -> HNThread {
        guard let story = try await item(id: storyID), !story.isRemoved else { throw HackerNewsError.notFound }
        guard story.isStory else { throw HackerNewsError.notAStory }
        var seen: Set<Int> = [story.id]
        var queue = (story.kids ?? []).filter { seen.insert($0).inserted }
        var comments: [HNItem] = []
        var fetched = 0
        var partial = false
        let ceiling = max(maxComments, 0) * 4
        reading: while !queue.isEmpty, comments.count < maxComments, fetched < ceiling {
            let batch = Array(queue.prefix(Self.batchSize))
            queue.removeFirst(batch.count)
            fetched += batch.count
            let (found, failure, _) = try await items(batch)
            try Task.checkCancellation()
            if let failure, found.isEmpty, comments.isEmpty { throw failure }
            for comment in found where !comment.isRemoved {
                comments.append(comment)
                for kid in comment.kids ?? [] where seen.insert(kid).inserted { queue.append(kid) }
            }
            if failure != nil { partial = true; break reading }
        }
        return HNThread(story: story, comments: Array(comments.prefix(maxComments)), isPartial: partial)
    }

    /// Fetches ids concurrently; returns the ones that exist in the order asked, plus the first failure if any.
    /// Cancellation is never swallowed.
    private func items(_ ids: [Int]) async throws -> (found: [HNItem], failure: (any Error)?, failedCount: Int) {
        try await withThrowingTaskGroup(of: (Int, HNItem?, (any Error)?).self) { group in
            for (position, id) in ids.enumerated() {
                group.addTask {
                    do { return (position, try await item(id: id), nil) }
                    catch is CancellationError { throw CancellationError() }
                    catch let error as URLError where error.code == .cancelled { throw error }
                    catch { return (position, nil, error) }
                }
            }
            var found: [(Int, HNItem)] = []
            var failure: (any Error)?
            var failed = 0
            for try await (position, item, error) in group {
                if let item { found.append((position, item)) }
                if let error { failed += 1; if failure == nil { failure = error } }
            }
            return (found.sorted { $0.0 < $1.0 }.map(\.1), failure, failed)
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, path: String) async throws -> Value? {
        let response = try await transport.send(URLRequest(url: baseURL.appendingPathComponent(path)))
        guard (200..<300).contains(response.statusCode) else {
            throw response.statusCode == 404 ? HackerNewsError.notFound : HackerNewsError.http(response.statusCode)
        }
        // The API answers a missing item with the JSON text `null`.
        if String(decoding: response.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null" { return nil }
        guard let value = try? JSONDecoder().decode(Value.self, from: response.data) else { throw HackerNewsError.unreadable }
        return value
    }
}


// MARK: - Scout additions (not in Feedloom)

/// What Feedloom's `URLTransport` provides, reduced to the one call the reader uses.
public protocol URLTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int)
}

/// URLSession as the transport, with a timeout. Read-only: Scout never posts, votes or comments.
public struct SessionTransport: URLTransport {
    public var session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        var request = request
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
