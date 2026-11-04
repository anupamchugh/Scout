//
//  Store.swift
//  Scout
//

import Foundation
import SwiftData

enum ScoutStore {
    static let schema = Schema([StoredPost.self, AuthorInfo.self, Lane.self, Decision.self, BlockedAuthor.self,
                                IssueDraft.self, IssueEntry.self, Pitch.self])

    /// One store for the app and its App Intents.
    static let container: ModelContainer = make(inMemory: false)

    static func make(inMemory: Bool) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the Scout store: \(error)")
        }
    }

    static let defaultLanes: [(name: String, tags: [String], theme: String)] = [
        ("Swift concurrency", ["swift", "swiftui", "ios", "concurrency", "ios-development"],
         "Swift concurrency, async await, actors, structured concurrency, SwiftUI and iOS app architecture"),
        ("Coffee Bytes", ["software-engineering", "programming", "artificial-intelligence", "llm", "web-development"],
         "Practical software engineering, developer tools, AI for programmers and lessons from shipping code"),
    ]

    static func seedIfNeeded(_ context: ModelContext) {
        if (try? context.fetchCount(FetchDescriptor<Lane>())) == 0 {
            for (index, lane) in defaultLanes.enumerated() {
                context.insert(Lane(name: lane.name, tags: lane.tags, theme: lane.theme, position: index))
            }
        }
        if (try? context.fetchCount(FetchDescriptor<IssueDraft>())) == 0 {
            context.insert(IssueDraft(number: 1, title: "Coffee Bytes"))
        }
        try? context.save()
    }

    /// The issue new "Issue" swipes go to: the newest draft.
    static func currentIssue(_ context: ModelContext) -> IssueDraft? {
        try? context.fetch(FetchDescriptor<IssueDraft>(sortBy: [SortDescriptor(\.created, order: .reverse)])).first
    }
}

enum Ingest {
    /// Inserts new feed items and merges repeats. Posts by blocked writers are never stored.
    @discardableResult
    static func upsert(_ report: FeedClient.Report, into context: ModelContext, now: Date = .now) throws -> Int {
        let blocked = Set(try context.fetch(FetchDescriptor<BlockedAuthor>()).map(\.authorKey))
        let guids = Array(Set(report.items.values.flatMap { $0.map(\.guid) }))
        let existing = try context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { guids.contains($0.guid) }))
        var byGuid = Dictionary(existing.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        var inserted = 0

        for (source, items) in report.items {
            for item in items where !blocked.contains(item.authorKey) {
                if let post = byGuid[item.guid] {
                    post.title = item.title
                    if !item.snippet.isEmpty { post.snippet = item.snippet }
                    post.categories = item.categories
                    post.readingMinutes = post.readingMinutes ?? item.readingMinutes
                    if let tag = source.tag, !post.foundUnder.contains(tag) { post.foundUnder.append(tag) }
                } else {
                    let post = StoredPost(
                        guid: item.guid, title: item.title, link: item.canonicalLink.absoluteString,
                        authorName: item.creator, authorKey: item.authorKey, handle: item.handle,
                        snippet: item.snippet, categories: item.categories, foundUnder: source.tag.map { [$0] } ?? [],
                        published: item.published, firstSeen: now, readingMinutes: item.readingMinutes,
                        imageURL: item.imageURL?.absoluteString)
                    context.insert(post)
                    byGuid[item.guid] = post
                    inserted += 1
                }
            }
        }

        for (source, image) in report.channelImages {
            guard case .author(let handle) = source else { continue }
            let infos = try context.fetch(FetchDescriptor<AuthorInfo>(predicate: #Predicate { $0.authorKey == handle }))
            if let info = infos.first {
                info.avatarURL = image.absoluteString
                info.fetched = now
            } else {
                context.insert(AuthorInfo(authorKey: handle, avatarURL: image.absoluteString, fetched: now))
            }
        }
        try context.save()
        return inserted
    }
}
