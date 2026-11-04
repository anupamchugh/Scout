//
//  FeedClient.swift
//  ScoutKit
//

import Foundation

public enum FeedError: Error, Equatable {
    case http(Int)
}

/// Fetches Medium RSS feeds, a few at a time.
public struct FeedClient: Sendable {
    public init(session: URLSession = .shared, maxConcurrent: Int = 6) {
        self.session = session
        self.maxConcurrent = maxConcurrent
    }

    public var session: URLSession = .shared
    /// Requests in flight at once; the rest wait their turn in the task group.
    public var maxConcurrent = 6

    public struct Report: Sendable {

        public init(items: [FeedSource: [FeedItem]] = [:], channelImages: [FeedSource: URL] = [:], failures: [FeedSource: String] = [:]) {
            self.items = items
            self.channelImages = channelImages
            self.failures = failures
        }

        public var items: [FeedSource: [FeedItem]] = [:]
        public var channelImages: [FeedSource: URL] = [:]
        public var failures: [FeedSource: String] = [:]
    }

    @concurrent
    public func fetch(_ source: FeedSource) async throws -> [FeedItem] {
        try await fetchDocument(source).items
    }

    @concurrent
    public func fetchDocument(_ source: FeedSource) async throws -> FeedDocument {
        var request = URLRequest(url: source.url, timeoutInterval: 20)
        request.setValue("application/rss+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FeedError.http(http.statusCode)
        }
        return try RSSParser.parseDocument(data)
    }

    @concurrent
    public func fetchAll(_ sources: [FeedSource]) async -> Report {
        await withTaskGroup(of: (FeedSource, Result<FeedDocument, any Error>).self) { group in
            var queue = sources.makeIterator()
            for _ in 0..<maxConcurrent {
                guard let source = queue.next() else { break }
                group.addTask { await Self.load(source, with: self) }
            }
            var report = Report()
            for await (source, result) in group {
                switch result {
                case .success(let document):
                    report.items[source] = document.items
                    report.channelImages[source] = document.channelImage
                case .failure(let error): report.failures[source] = String(describing: error)
                }
                if let next = queue.next() {
                    group.addTask { await Self.load(next, with: self) }
                }
            }
            return report
        }
    }

    private static func load(_ source: FeedSource, with client: FeedClient) async -> (FeedSource, Result<FeedDocument, any Error>) {
        do { return (source, .success(try await client.fetchDocument(source))) }
        catch { return (source, .failure(error)) }
    }
}
