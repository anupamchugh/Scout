//
//  FeedCache.swift
//  Scout
//

import Foundation

/// Remembers recent feed fetches so switching lanes or windows doesn't refetch Medium every time.
/// An actor, so concurrent loads from the deck, search and Siri share one cache safely.
actor FeedCache {
    static let shared = FeedCache()

    private var entries: [FeedSource: (fetched: Date, document: FeedDocument)] = [:]
    private let lifetime: TimeInterval
    private let client: FeedClient

    init(lifetime: TimeInterval = 15 * 60, client: FeedClient = FeedClient()) {
        self.lifetime = lifetime
        self.client = client
    }

    /// Cached documents still fresh at `now`, plus a network fetch (capped concurrency) for the rest.
    /// Cancelling the calling task cancels the fetches still running.
    func load(_ sources: [FeedSource], now: Date = .now) async -> FeedClient.Report {
        var report = FeedClient.Report()
        var missing: [FeedSource] = []
        for source in Set(sources) {
            if let entry = entries[source], now.timeIntervalSince(entry.fetched) < lifetime {
                report.items[source] = entry.document.items
                report.channelImages[source] = entry.document.channelImage
            } else {
                missing.append(source)
            }
        }
        guard !missing.isEmpty else { return report }
        let fetched = await client.fetchAll(missing)
        for (source, items) in fetched.items {
            let document = FeedDocument(channelImage: fetched.channelImages[source], items: items)
            entries[source] = (now, document)
            report.items[source] = items
            report.channelImages[source] = document.channelImage
        }
        report.failures.merge(fetched.failures) { first, _ in first }
        return report
    }

    func clear() {
        entries = [:]
    }
}
