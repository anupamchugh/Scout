//
//  TagRecord.swift
//  Scout
//
//  The local tag catalog: every Medium tag seen on a fetched post, how many posts carried it, and which
//  tags shared those posts. Counted in code as posts are stored; nothing leaves the device.
//

import Foundation
import ScoutKit
import SwiftData

@Model
final class TagRecord {
    @Attribute(.unique) var tag: String
    var postCount: Int
    var firstSeen: Date
    var lastSeen: Date
    /// JSON of [other tag: posts carrying both].
    var neighboursData: Data

    init(tag: String, now: Date = .now) {
        self.tag = tag
        postCount = 0
        firstSeen = now
        lastSeen = now
        neighboursData = Data("{}".utf8)
    }

    var neighbours: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self, from: neighboursData)) ?? [:] }
        set { neighboursData = (try? JSONEncoder().encode(newValue)) ?? neighboursData }
    }
}

enum TagCatalogStore {

    /// Adds one newly stored post's tags to the catalog. Call once per post, when it is first stored.
    static func record(_ tags: [String], in context: ModelContext, now: Date = .now) throws {
        let neighbours = TagCatalog.neighbours(of: tags)
        guard !neighbours.isEmpty else { return }
        let names = Array(neighbours.keys)
        let existing = try context.fetch(FetchDescriptor<TagRecord>(predicate: #Predicate { names.contains($0.tag) }))
        var byTag = Dictionary(existing.map { ($0.tag, $0) }, uniquingKeysWith: { first, _ in first })
        for (tag, others) in neighbours {
            let record = byTag[tag] ?? {
                let created = TagRecord(tag: tag, now: now)
                context.insert(created)
                byTag[tag] = created
                return created
            }()
            record.postCount += 1
            record.lastSeen = max(record.lastSeen, now)
            var counts = record.neighbours
            for other in others { counts[other, default: 0] += 1 }
            record.neighbours = counts
        }
    }

    /// Builds the catalog from posts already stored, once, for stores created before the catalog existed.
    static func backfillIfEmpty(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<TagRecord>()) == 0 else { return }
        for post in try context.fetch(FetchDescriptor<StoredPost>()) {
            try record(post.categories, in: context, now: post.firstSeen)
        }
        try context.save()
    }

    /// Every tag seen, most posts first.
    static func all(_ context: ModelContext, limit: Int = 200) -> [TagRecord] {
        var descriptor = FetchDescriptor<TagRecord>(sortBy: [SortDescriptor(\.postCount, order: .reverse), SortDescriptor(\.tag)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Tags that often share posts with the lane's tags, counted in code.
    static func potential(for laneTags: Set<String>, in context: ModelContext, limit: Int = 12) -> [TagCatalog.Potential] {
        let lane = TagCatalog.normalized(Array(laneTags))
        guard !lane.isEmpty else { return feedLaneTags(laneTags, in: context, limit: limit) }
        let records = (try? context.fetch(FetchDescriptor<TagRecord>(predicate: #Predicate { lane.contains($0.tag) }))) ?? []
        let cooccurrence = Dictionary(records.map { ($0.tag, $0.neighbours) }, uniquingKeysWith: { first, _ in first })
        let candidates = Array(Set(cooccurrence.values.flatMap(\.keys)))
        let counts = Dictionary(((try? context.fetch(FetchDescriptor<TagRecord>(predicate: #Predicate { candidates.contains($0.tag) }))) ?? [])
            .map { ($0.tag, $0.postCount) }, uniquingKeysWith: { first, _ in first })
        return TagCatalog.potential(for: Set(lane), counts: counts, cooccurrence: cooccurrence, limit: limit)
    }

    /// A lane made of feeds (a publication such as Better Programming) has no tags of its own:
    /// its potential tags are the tags its posts carry most.
    private static func feedLaneTags(_ keys: Set<String>, in context: ModelContext, limit: Int) -> [TagCatalog.Potential] {
        guard !keys.isEmpty, let posts = try? context.fetch(FetchDescriptor<StoredPost>()) else { return [] }
        let tagged = posts.filter { !keys.isDisjoint(with: $0.foundUnder) }.map(\.categories)
        let (counts, _) = TagCatalog.tally(tagged)
        return counts.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).map { TagCatalog.Potential(tag: $0.key, together: $0.value, seen: $0.value) }
    }
}
