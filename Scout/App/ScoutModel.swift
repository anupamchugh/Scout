//
//  ScoutModel.swift
//  Scout
//

import Foundation
import Observation
import SwiftData

enum DeckWindow: String, CaseIterable, Identifiable, Sendable {
    case day = "Last 24 hours"
    case week = "Last 7 days"
    case month = "Last 30 days"

    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }
}

enum DeckMode: String, CaseIterable, Identifiable, Sendable {
    case stories = "Stories"
    case writers = "Writers"

    var id: String { rawValue }
}

@Observable
@MainActor
final class ScoutModel {
    let container: ModelContainer
    let usesDemoData: Bool
    var context: ModelContext { container.mainContext }

    var window: DeckWindow = .week
    var activeLaneName: String = ScoutStore.defaultLanes[0].name
    var mode: DeckMode = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-stories") { return .stories }
        #endif
        return .writers
    }()

    private(set) var deck: [AuthorCandidate] = []
    private(set) var storyDeck: [StoryCandidate] = []
    /// Tag pairs that keep appearing together in the window, offered as new lanes.
    private(set) var suggestedPairs: [(pair: TagPair, count: Int)] = []
    /// Statistics from each writer's own feed, computed in code, by author key.
    private(set) var authorStats: [String: AuthorStats] = [:]
    /// "Why this story" lines that passed `TextGuard`, by post guid.
    private(set) var storyWhyLines: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var failedFeeds: [String] = []
    /// "Why this writer" lines that passed `TextGuard`, by author key.
    private(set) var whyLines: [String: String] = [:]
    private var whyRequested: Set<String> = []

    init(container: ModelContainer, usesDemoData: Bool) {
        self.container = container
        self.usesDemoData = usesDemoData
        ScoutStore.seedIfNeeded(container.mainContext)
    }

    var lanes: [Lane] {
        (try? context.fetch(FetchDescriptor<Lane>(sortBy: [SortDescriptor(\.position)]))) ?? []
    }

    var activeLane: LaneSpec {
        let lane = lanes.first { $0.name == activeLaneName } ?? lanes.first
        return lane.map { LaneSpec(name: $0.name, tags: Set($0.tags), theme: $0.theme) }
            ?? LaneSpec(name: activeLaneName, tags: [], theme: activeLaneName)
    }

    var laneSpecs: [LaneSpec] {
        lanes.map { LaneSpec(name: $0.name, tags: Set($0.tags), theme: $0.theme) }
    }

    func addLane(from pair: TagPair) {
        let name = pair.label
        guard !lanes.contains(where: { $0.name == name }) else { return }
        context.insert(Lane(name: name, tags: [pair.first, pair.second], theme: "\(pair.first) and \(pair.second)",
                            position: (lanes.map(\.position).max() ?? -1) + 1))
        try? context.save()
        activeLaneName = name
    }

    // MARK: Deck

    /// Fetches the lane's feeds, scores writers in code and fills the deck.
    /// Called from `.task(id:)`, so changing the lane or window cancels a load in progress.
    func loadDeck() async {
        let lane = activeLane
        isLoading = true
        defer { isLoading = false }

        // Every lane's feeds, so a story's "surfaced by N lanes" signal sees all of them.
        let allTags = Set(laneSpecs.flatMap(\.tags)).union(lane.tags)
        let report = await fetch(allTags.sorted().map(FeedSource.tag))
        guard !Task.isCancelled else { return }
        failedFeeds = report.failures.keys.map(\.label).sorted()
        _ = try? Ingest.upsert(report, into: context)

        var candidates = await rank(lane)
        guard !Task.isCancelled else { return }

        // The top writers' own feeds add their avatar, other recent posts and full-text reading times.
        let handles = candidates.prefix(8).compactMap(\.handle)
        if !handles.isEmpty {
            let authors = await fetch(handles.map(FeedSource.author))
            guard !Task.isCancelled else { return }
            _ = try? Ingest.upsert(authors, into: context)
            record(authors)
            candidates = await rank(lane)
            guard !Task.isCancelled else { return }
        }

        let avatars = Dictionary(((try? context.fetch(FetchDescriptor<AuthorInfo>())) ?? []).map { ($0.authorKey, $0.avatarURL) },
                                 uniquingKeysWith: { first, _ in first })
        deck = candidates.prefix(30).map { candidate in
            var candidate = candidate
            candidate.avatarURL = avatars[candidate.authorKey].flatMap { $0 }.flatMap(URL.init(string:))
            return candidate
        }
        storyDeck = Array(await rankStories(lane).prefix(40))
        guard !Task.isCancelled else { return }
        prefetchWhy()
    }

    private func record(_ authors: FeedClient.Report) {
        for (source, items) in authors.items {
            if case .author(let handle) = source, !items.isEmpty { authorStats[handle] = stats(for: items) }
        }
    }

    /// Fetches a writer's own feed when their card reaches the top, in a child task the view cancels.
    func ensureStats(for candidate: AuthorCandidate) async {
        guard let handle = candidate.handle, authorStats[candidate.authorKey] == nil else { return }
        let report = await fetch([.author(handle)])
        guard !Task.isCancelled else { return }
        _ = try? Ingest.upsert(report, into: context)
        record(report)
    }

    private func rankStories(_ lane: LaneSpec) async -> [StoryCandidate] {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-window.seconds)
        let posts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.published >= cutoff }))) ?? []
        let records = Matching.unifyAuthors(posts.map(Self.record))
        let picked = ((try? context.fetch(FetchDescriptor<StoryPick>())) ?? []).map(\.guid)
        let blocked = ((try? context.fetch(FetchDescriptor<BlockedAuthor>())) ?? []).map(\.authorKey)
        let excluded = Set(picked + blocked)
        let texts = Dictionary(records.filter { !excluded.contains($0.guid) }.map { ($0.guid, "\($0.title). \($0.snippet)") },
                               uniquingKeysWith: { first, _ in first })
        let semantic = await Embedder.similarities(texts, to: lane.theme)
        suggestedPairs = TagCooccurrence.suggestions(records, existing: laneSpecs.map(\.tags))
        return Matching.stories(from: records, lane: lane, lanes: laneSpecs, semantic: semantic, excluding: excluded,
                                now: now, window: window.seconds)
    }

    private func fetch(_ sources: [FeedSource]) async -> FeedClient.Report {
        #if DEBUG
        if usesDemoData { return DemoData.report(for: sources) }
        #endif
        return await FeedCache.shared.load(sources)
    }

    private func rank(_ lane: LaneSpec) async -> [AuthorCandidate] {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-window.seconds)
        let posts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.published >= cutoff }))) ?? []
        let records = Matching.unifyAuthors(posts.map(Self.record))
        let excluded = decidedOrBlocked()
        let texts = Dictionary(grouping: records.filter { !excluded.contains($0.authorKey) }, by: \.authorKey)
            .mapValues { $0.map { "\($0.title). \($0.snippet)" }.joined(separator: " ") }
        let semantic = await Embedder.similarities(texts, to: lane.theme)
        return Matching.candidates(from: records, lane: lane, semantic: semantic, excluding: excluded,
                                   now: now, window: window.seconds)
    }

    static func record(_ post: StoredPost) -> PostRecord {
        PostRecord(guid: post.guid, title: post.title, link: post.link, snippet: post.snippet, authorKey: post.authorKey,
                   authorName: post.authorName, handle: post.handle, categories: post.categories,
                   foundUnder: post.foundUnder, published: post.published, readingMinutes: post.readingMinutes)
    }

    private func decidedOrBlocked() -> Set<String> {
        let decided = ((try? context.fetch(FetchDescriptor<Decision>())) ?? []).map(\.authorKey)
        let blocked = ((try? context.fetch(FetchDescriptor<BlockedAuthor>())) ?? []).map(\.authorKey)
        return Set(decided + blocked)
    }

    // MARK: Decisions

    func decide(_ candidate: AuthorCandidate, _ verdict: Verdict) {
        let post = candidate.bestPost
        context.insert(Decision(authorKey: candidate.authorKey, authorName: candidate.name, handle: candidate.handle,
                                lane: activeLane.name, verdict: verdict, score: candidate.score,
                                bestPostGuid: post.guid, bestPostTitle: post.title, bestPostLink: post.link))
        if verdict == .issue, let issue = ScoutStore.currentIssue(context) {
            let entry = IssueEntry(position: (issue.entries.map(\.position).max() ?? -1) + 1, postGuid: post.guid,
                                   title: post.title, link: post.link, authorName: candidate.name, handle: candidate.handle)
            entry.issue = issue
            context.insert(entry)
        }
        try? context.save()
        deck.removeAll { $0.authorKey == candidate.authorKey }
        prefetchWhy()
        if verdict != .pass { Task { await reindexSpotlight() } }
    }

    func decideStory(_ story: StoryCandidate, _ verdict: Verdict) {
        let post = story.post
        context.insert(StoryPick(guid: post.guid, title: post.title, link: post.link, authorKey: post.authorKey,
                                 authorName: post.authorName, handle: post.handle, tags: post.categories,
                                 lane: activeLane.name, verdict: verdict, score: story.score))
        if verdict == .issue, let issue = ScoutStore.currentIssue(context),
           !issue.entries.contains(where: { $0.postGuid == post.guid }) {
            let entry = IssueEntry(position: (issue.entries.map(\.position).max() ?? -1) + 1, postGuid: post.guid,
                                   title: post.title, link: post.link, authorName: post.authorName, handle: post.handle)
            entry.issue = issue
            context.insert(entry)
        }
        try? context.save()
        storyDeck.removeAll { $0.id == story.id }
        prefetchWhy()
    }

    func undoStory(_ pick: StoryPick) {
        if pick.verdict == .issue, let issue = ScoutStore.currentIssue(context) {
            for entry in issue.entries where entry.postGuid == pick.guid { context.delete(entry) }
        }
        context.delete(pick)
        try? context.save()
    }

    /// Outreach targets a writer, so a shortlisted story can put its writer on the shortlist too.
    func shortlistWriter(of pick: StoryPick) {
        let key = pick.authorKey
        guard (try? context.fetchCount(FetchDescriptor<Decision>(predicate: #Predicate { $0.authorKey == key }))) == 0 else { return }
        context.insert(Decision(authorKey: pick.authorKey, authorName: pick.authorName, handle: pick.handle, lane: pick.lane,
                                verdict: .shortlist, score: pick.score, bestPostGuid: pick.guid,
                                bestPostTitle: pick.title, bestPostLink: pick.link))
        try? context.save()
    }

    func undo(_ decision: Decision) {
        if decision.verdict == .issue, let issue = ScoutStore.currentIssue(context) {
            for entry in issue.entries where entry.postGuid == decision.bestPostGuid { context.delete(entry) }
        }
        context.delete(decision)
        try? context.save()
    }

    func block(_ candidate: AuthorCandidate) {
        context.insert(BlockedAuthor(authorKey: candidate.authorKey, name: candidate.name))
        try? context.save()
        deck.removeAll { $0.authorKey == candidate.authorKey }
        prefetchWhy()
    }

    var shortlistedCount: Int {
        let shortlist = Verdict.shortlist.rawValue
        return (try? context.fetchCount(FetchDescriptor<Decision>(predicate: #Predicate { $0.verdictRaw == shortlist }))) ?? 0
    }

    func reindexSpotlight() async {
        let decisions = (try? context.fetch(FetchDescriptor<Decision>())) ?? []
        let keys = decisions.filter { $0.verdict != .pass }.map(\.authorKey)
        let posts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { keys.contains($0.authorKey) }))) ?? []
        await SpotlightIndex.index(decisions, posts: posts)
    }

    // MARK: Writing

    /// Asks the model for the top cards' "why" lines; only lines that pass `TextGuard` are kept.
    private func prefetchWhy() {
        guard ModelAvailability.current.isAvailable else { return }
        let lane = activeLane
        for story in storyDeck.prefix(3) where !whyRequested.contains(story.id) {
            whyRequested.insert(story.id)
            Task {
                if let line = try? await Writer.why(title: story.post.title, snippet: story.post.snippet, lane: lane) {
                    storyWhyLines[story.id] = line
                }
            }
        }
        for candidate in deck.prefix(3) where !whyRequested.contains(candidate.authorKey) {
            whyRequested.insert(candidate.authorKey)
            Task {
                if let line = try? await Writer.why(for: candidate, lane: lane, stats: authorStats[candidate.authorKey]) {
                    whyLines[candidate.authorKey] = line
                }
            }
        }
    }

    func draftNote(for decision: Decision) async -> String? {
        let guid = decision.bestPostGuid
        let snippet = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.guid == guid })).first?.snippet) ?? ""
        guard ModelAvailability.current.isAvailable else {
            return Writer.templateNote(name: decision.authorName, title: decision.bestPostTitle, lane: decision.lane)
        }
        return try? await Writer.outreach(title: decision.bestPostTitle, snippet: snippet, lane: decision.lane)
    }
}
