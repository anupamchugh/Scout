//
//  Store.swift
//  Scout
//

import Foundation
import SwiftData

enum ScoutStore {
    static let schema = Schema([StoredPost.self, AuthorInfo.self, Lane.self, Decision.self, StoryPick.self, BlockedAuthor.self,
                                IssueDraft.self, IssueEntry.self, Pitch.self, TasteRecord.self])

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

    static func seedIfNeeded(_ context: ModelContext, pack: RolePack = .engineering) {
        seedLanes(for: pack, in: context)
        if (try? context.fetchCount(FetchDescriptor<IssueDraft>())) == 0 {
            context.insert(IssueDraft(number: 1, title: "Coffee Bytes"))
        }
        try? context.save()
    }

    /// Adds a pack's lanes the first time the pack is used; edits to them are kept after that.
    static func seedLanes(for pack: RolePack, in context: ModelContext) {
        let id = pack.id
        guard (try? context.fetchCount(FetchDescriptor<Lane>(predicate: #Predicate { $0.packID == id }))) == 0 else { return }
        let existing = Set(((try? context.fetch(FetchDescriptor<Lane>())) ?? []).map(\.name))
        for (index, lane) in pack.lanes.enumerated() where !existing.contains(lane.name) {
            context.insert(Lane(name: lane.name, tags: lane.sources, theme: lane.theme, position: index, packID: pack.id))
        }
        try? context.save()
    }

    static func taste(for pack: RolePack, in context: ModelContext) -> TasteRecord {
        let id = pack.id
        if let record = try? context.fetch(FetchDescriptor<TasteRecord>(predicate: #Predicate { $0.packID == id })).first {
            return record
        }
        let record = TasteRecord(packID: id)
        context.insert(record)
        return record
    }

    /// The issue new "Issue" swipes go to: the newest draft.
    static func currentIssue(_ context: ModelContext) -> IssueDraft? {
        try? context.fetch(FetchDescriptor<IssueDraft>(sortBy: [SortDescriptor(\.created, order: .reverse)])).first
    }
}

enum Ingest {
    /// The feed's creator, or for feeds without one (Hacker News) the site the link points to.
    static func author(_ item: FeedItem, _ source: FeedSource) -> String {
        if !item.creator.isEmpty { return item.creator }
        return item.link.host()?.replacingOccurrences(of: "www.", with: "") ?? source.label
    }

    /// Inserts new feed items and merges repeats. A post is the same post when its RSS guid or its canonical
    /// link matches (the same story appears in several tag feeds); merging keeps every feed that surfaced it.
    /// Posts by blocked writers are never stored.
    @discardableResult
    static func upsert(_ report: FeedClient.Report, into context: ModelContext, now: Date = .now) throws -> Int {
        let blocked = Set(try context.fetch(FetchDescriptor<BlockedAuthor>()).map(\.authorKey))
        let guids = Array(Set(report.items.values.flatMap { $0.map(\.guid) }))
        let links = Array(Set(report.items.values.flatMap { $0.map { $0.canonicalLink.absoluteString } }))
        let existing = try context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { guids.contains($0.guid) || links.contains($0.link) }))
        var byGuid = Dictionary(existing.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        var byLink = Dictionary(existing.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })
        var inserted = 0

        for (source, items) in report.items {
            for item in items where !blocked.contains(item.authorKey) {
                if let post = byGuid[item.guid] ?? byLink[item.canonicalLink.absoluteString] {
                    post.title = item.title
                    if !item.snippet.isEmpty { post.snippet = item.snippet }
                    post.categories = Array(Set(post.categories).union(item.categories)).sorted()
                    post.readingMinutes = post.readingMinutes ?? item.readingMinutes
                    if let key = source.laneKey, !post.foundUnder.contains(key) { post.foundUnder.append(key) }
                } else {
                    let post = StoredPost(
                        guid: item.guid, title: item.title, link: item.canonicalLink.absoluteString,
                        authorName: author(item, source), authorKey: item.creator.isEmpty && item.handle == nil ? "name:\(author(item, source))" : item.authorKey,
                        handle: item.handle,
                        snippet: item.snippet, categories: item.categories, foundUnder: source.laneKey.map { [$0] } ?? [],
                        published: item.published, firstSeen: now, readingMinutes: item.readingMinutes,
                        imageURL: item.imageURL?.absoluteString)
                    context.insert(post)
                    byGuid[item.guid] = post
                    byLink[post.link] = post
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
