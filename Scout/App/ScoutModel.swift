//
//  ScoutModel.swift
//  Scout
//

import Foundation
import Observation
import os
import ScoutKit
import SwiftData

enum DeckWindow: String, CaseIterable, Identifiable, Sendable {
    case day = "Last 24 hours"
    case week = "Last 7 days"
    case month = "Last 30 days"

    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        }
    }
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
    var title: LocalizedStringResource {
        switch self {
        case .stories: "Stories"
        case .writers: "Writers"
        }
    }
}

private let log = Logger(subsystem: "com.anupamchugh.scout", category: "deck")

@Observable
@MainActor
final class ScoutModel {
    let container: ModelContainer
    let usesDemoData: Bool
    var context: ModelContext { container.mainContext }

    var window: DeckWindow = .week
    private(set) var activePack: RolePack = PackStore.pack(id: PackStore.activeID)
    static let allLanes = "All my lanes"
    var activeLaneName: String = ScoutModel.allLanes
    /// True until the person picks a role pack (onboarding).
    var needsPackChoice: Bool { PackStore.activeID == nil && !usesDemoData }
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
    /// llms.txt context for writers' own sites, by host (only found ones).
    private(set) var siteContexts: [String: SiteContext] = [:]
    /// Writers' avatars from their own feeds, by author key.
    private(set) var avatars: [String: URL] = [:]
    /// Hacker News poster statistics from the official API, computed in code, by author key ("hn:<user>").
    private(set) var hnStats: [String: HNAuthorStats] = [:]
    /// Statistics from each writer's own feed, computed in code, by author key.
    private(set) var authorStats: [String: AuthorStats] = [:]
    /// "Why this story" lines that passed `TextGuard`, by post guid.
    private(set) var storyWhyLines: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var failedFeeds: [String] = []
    /// "Why this writer" lines that passed `TextGuard`, by author key.
    private(set) var whyLines: [String: String] = [:]
    private var whyRequested: Set<String> = []
    private var loadGeneration = 0

    init(container: ModelContainer, usesDemoData: Bool) {
        self.container = container
        self.usesDemoData = usesDemoData
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        // Demo data only covers Medium tags, so it starts on the Engineering pack whatever was saved.
        if usesDemoData {
            activePack = .engineering
        }
        // -lane <name>: start on one lane.
        if let i = args.firstIndex(of: "-lane"), i + 1 < args.count { activeLaneName = args[i + 1] }
        // -choosePack: show the onboarding pack picker again.
        if args.contains("-choosePack") { PackStore.activeID = nil }
        if let i = args.firstIndex(of: "-pack"), i + 1 < args.count {
            PackStore.activeID = args[i + 1]
            activePack = PackStore.pack(id: args[i + 1])
        }
        #endif
        ScoutStore.seedIfNeeded(container.mainContext, pack: activePack)
        try? TagCatalogStore.backfillIfEmpty(container.mainContext)
        Writer.pack = activePack
        Writer.container = container
    }

    func switchPack(to pack: RolePack) {
        PackStore.activeID = pack.id
        // Choosing the pack already in use (the onboarding default, say) must not empty a deck that won't reload.
        guard pack.id != activePack.id else { return }
        activePack = pack
        ScoutStore.seedLanes(for: pack, in: context)
        activeLaneName = Self.allLanes
        Writer.pack = pack
        deck = []
        storyDeck = []
    }

    var lanes: [Lane] {
        let id = activePack.id
        return (try? context.fetch(FetchDescriptor<Lane>(predicate: #Predicate { $0.packID == id },
                                                        sortBy: [SortDescriptor(\.position)]))) ?? []
    }

    var isAllLanes: Bool { activeLaneName == Self.allLanes }

    /// One lane, or with "All my lanes" every lane's sources and themes together (for filters and fetching).
    var activeLane: LaneSpec {
        if isAllLanes {
            let specs = laneSpecs
            return LaneSpec(name: Self.allLanes, tags: Set(specs.flatMap(\.tags)), theme: specs.map(\.theme).joined(separator: ". "))
        }
        let lane = lanes.first { $0.name == activeLaneName } ?? lanes.first
        return lane.map { LaneSpec(name: $0.name, tags: Set($0.tags), theme: $0.theme) }
            ?? LaneSpec(name: activeLaneName, tags: [], theme: activeLaneName)
    }

    var laneSpecs: [LaneSpec] {
        lanes.map { LaneSpec(name: $0.name, tags: Set($0.tags), theme: $0.theme) }
    }

    /// The lanes a ranking scores against: all of the pack's lanes, or the chosen one.
    private var rankingLanes: [LaneSpec] { isAllLanes ? laneSpecs : [activeLane] }

    func addLane(from pair: TagPair) {
        addLane(name: pair.label, tags: [pair.first, pair.second], theme: "\(pair.first) and \(pair.second)")
    }

    func addLane(name: String, tags: [String], theme: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !tags.isEmpty, name != Self.allLanes,
              (try? context.fetchCount(FetchDescriptor<Lane>(predicate: #Predicate { $0.name == name }))) == 0 else { return }
        context.insert(Lane(name: name, tags: tags, theme: theme.isEmpty ? tags.joined(separator: ", ") : theme,
                            position: (lanes.map(\.position).max() ?? -1) + 1, packID: activePack.id))
        try? context.save()
        activeLaneName = name
    }

    /// Tags seen on posts in the window, most common first, for building a new lane.
    var tagCloud: [(tag: String, count: Int)] {
        let cutoff = Date.now.addingTimeInterval(-window.seconds)
        let posts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.published >= cutoff }))) ?? []
        return Array(TagCooccurrence.tagCounts(posts.map(Self.record)).prefix(40))
    }

    // MARK: Deck

    /// Fetches the lane's feeds, scores writers in code and fills the deck.
    /// Called from `.task(id:)`, so changing the lane or window cancels a load in progress.
    func loadDeck() async {
        let lane = activeLane
        // A newer load (lane, window or pack changed) owns the loading flag; a cancelled one must not clear it.
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        log.info("load \(generation) start pack=\(self.activePack.id, privacy: .public) lane=\(lane.name, privacy: .public) keys=\(lane.tags.count)")

        // Every lane's feeds, so a story's "surfaced by N lanes" signal sees all of them.
        let allTags = Set(laneSpecs.flatMap(\.tags)).union(lane.tags)
        let report = await fetch(allTags.sorted().map(FeedSource.init(laneKey:)))
        log.info("load \(generation) fetched \(report.items.values.map(\.count).reduce(0, +)) items, failures=\(report.failures.count) cancelled=\(Task.isCancelled)")
        guard !Task.isCancelled else { return }
        failedFeeds = report.failures.keys.map(\.label).sorted()
        _ = try? Ingest.upsert(report, into: context)
        let cutoff = Date.now.addingTimeInterval(-window.seconds)
        let hnPosts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.hnID != nil && $0.published >= cutoff }))) ?? []
        if !hnPosts.isEmpty {
            await ScoutStore.enrichHackerNews(hnPosts)
            try? context.save()
            guard !Task.isCancelled else { return }
        }

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

        avatars = Dictionary(((try? context.fetch(FetchDescriptor<AuthorInfo>())) ?? []).compactMap { info in
            info.avatarURL.flatMap(URL.init(string:)).map { (info.authorKey, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let avatars = avatars
        let stories = await rankStories(lane)
        guard !Task.isCancelled else { return }

        // Taste from past swipes in this pack shifts the scores, in code. Tag weights apply at once; the deck
        // re-sorts when similarity to liked items (image downloads for visual packs) arrives.
        let record = ScoutStore.taste(for: activePack, in: context)
        let taste = record.taste
        func fill(writerSimilarity: [String: Double], storySimilarity: [String: Double]) {
            deck = Matching.applyTaste(Array(candidates.prefix(40)), taste: taste, similarity: writerSimilarity).prefix(30).map { candidate in
                var candidate = candidate
                candidate.avatarURL = avatars[candidate.authorKey]
                return candidate
            }
            storyDeck = Array(Matching.applyTaste(Array(stories.prefix(60)), taste: taste, similarity: storySimilarity).prefix(40))
        }
        fill(writerSimilarity: [:], storySimilarity: [:])
        await loadSiteContexts()
        guard !Task.isCancelled else { return }
        applySiteSignal(lane)
        log.info("load \(generation) filled writers=\(self.deck.count) stories=\(self.storyDeck.count) ranked=\(stories.count)")
        prefetchWhy()

        let (writerSimilarity, storySimilarity) = await tasteSimilarity(writers: Array(candidates.prefix(20)),
                                                                       stories: Array(stories.prefix(20)), record: record)
        guard !Task.isCancelled, !(writerSimilarity.isEmpty && storySimilarity.isEmpty) else { return }
        // Keep cards already on screen in place: only cards not yet swiped are re-sorted.
        let remainingWriters = Set(deck.map(\.authorKey))
        let remainingStories = Set(storyDeck.map(\.id))
        fill(writerSimilarity: writerSimilarity, storySimilarity: storySimilarity)
        deck.removeAll { !remainingWriters.contains($0.authorKey) }
        storyDeck.removeAll { !remainingStories.contains($0.id) }
    }

    /// Fetches /llms.txt for the personal sites behind the top cards, at most weekly per site, quietly on 404.
    private func loadSiteContexts() async {
        let hosts = Set((storyDeck.prefix(15).map(\.post) + deck.prefix(10).map(\.bestPost)).compactMap(\.domain))
            .filter(LLMSTxt.isPersonalDomain)
        let stored = Dictionary(((try? context.fetch(FetchDescriptor<SiteContext>())) ?? []).map { ($0.host, $0) },
                                uniquingKeysWith: { first, _ in first })
        for host in hosts.sorted() {
            if let existing = stored[host], !existing.isStale {
                if existing.found { siteContexts[host] = existing }
                continue
            }
            guard !Task.isCancelled else { return }
            let document = await Self.fetchLLMSTxt(host: host)
            let record = stored[host] ?? SiteContext(host: host, found: false)
            if stored[host] == nil { context.insert(record) }
            record.found = document != nil
            record.title = document?.title ?? ""
            record.summary = document?.summary ?? ""
            record.sectionTitles = document?.sectionTitles ?? []
            record.fetched = .now
            if record.found { siteContexts[host] = record }
        }
        try? context.save()
    }

    @concurrent
    private static func fetchLLMSTxt(host: String) async -> LLMSTxtDocument? {
        guard let url = URL(string: "https://\(host)/llms.txt"),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return LLMSTxt.parse(String(decoding: data.prefix(200_000), as: UTF8.self))
    }

    /// A small boost, in code, for cards whose site's llms.txt sections overlap the lane.
    private func applySiteSignal(_ lane: LaneSpec) {
        func boost(_ post: PostRecord) -> Int {
            guard let host = post.domain, let site = siteContexts[host] else { return 0 }
            return Int((6 * LLMSTxt.laneOverlap(sectionTitles: site.sectionTitles, lane: lane)).rounded())
        }
        storyDeck = storyDeck.map { $0.withScore(min(100, $0.score + boost($0.post))) }.sorted { $0.score > $1.score }
        deck = deck.map { candidate in
            var updated = candidate.withScore(min(100, candidate.score + boost(candidate.bestPost)))
            updated.avatarURL = candidate.avatarURL
            return updated
        }.sorted { $0.score > $1.score }
    }

    func siteContext(for post: PostRecord) -> SiteContext? {
        post.domain.flatMap { siteContexts[$0] }
    }

    /// Adds a discovered feed as a lane in the active pack.
    func addSite(_ feed: DiscoveredFeed, name: String) {
        addLane(name: name, tags: [feed.url.absoluteString], theme: "Posts from \(feed.title)")
    }

    /// Similarity to what you liked: Vision feature prints of images for visual packs,
    /// the text-embedding centroid of liked items for the others.
    private func tasteSimilarity(writers: [AuthorCandidate], stories: [StoryCandidate],
                                 record: TasteRecord) async -> ([String: Double], [String: Double]) {
        if activePack.isVisual {
            let liked = record.likedPrints
            guard !liked.isEmpty else { return ([:], [:]) }
            var urls: [String: URL] = [:]
            for post in stories.map(\.post) + writers.map(\.bestPost) {
                if let image = post.imageURL.flatMap(URL.init(string:)) { urls[post.guid] = image }
            }
            let prints = await ImageTaste.prints(for: urls)
            let byGuid = prints.compactMapValues { ImageTaste.similarity($0, toLiked: liked) }
            return (Dictionary(uniqueKeysWithValues: writers.compactMap { w in byGuid[w.bestPost.guid].map { (w.authorKey, $0) } }), byGuid)
        }
        guard let centroid = record.taste.centroid else { return ([:], [:]) }
        let writerTexts = Dictionary(uniqueKeysWithValues: writers.map { ($0.authorKey, $0.sourceText) })
        let storyTexts = Dictionary(stories.map { ($0.id, "\($0.post.title). \($0.post.snippet)") }, uniquingKeysWith: { first, _ in first })
        return (await Embedder.similarities(writerTexts, toVector: centroid), await Embedder.similarities(storyTexts, toVector: centroid))
    }

    /// One swipe updates this pack's taste: tag weights, the liked-text centroid, and for visual packs a feature print.
    private func learn(tags: [String], text: String, imageURL: String?, liked: Bool) {
        let record = ScoutStore.taste(for: activePack, in: context)
        var taste = record.taste
        taste.record(tags: tags, liked: liked, embedding: liked ? Embedder.vector(text) : nil)
        record.taste = taste
        try? context.save()
        guard liked, activePack.isVisual, let url = imageURL.flatMap(URL.init(string:)) else { return }
        Task {
            if let print = await ImageTaste.featurePrint(for: url) {
                record.likedPrints = Array((record.likedPrints + [print]).suffix(ImageTaste.keep))
                try? context.save()
            }
        }
    }

    private func record(_ authors: FeedClient.Report) {
        for (source, items) in authors.items {
            if case .author(let handle) = source, !items.isEmpty { authorStats[handle] = stats(for: items) }
        }
    }

    /// Fetches a writer's own feed when their card reaches the top, in a child task the view cancels.
    func ensureStats(for candidate: AuthorCandidate) async {
        if candidate.authorKey.hasPrefix("hn:") {
            let user = String(candidate.authorKey.dropFirst(3))
            guard hnStats[candidate.authorKey] == nil, let stats = await HNCache.shared.stats(for: user) else { return }
            guard !Task.isCancelled else { return }
            hnStats[candidate.authorKey] = stats
            return
        }
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
        // Visual packs match on images (through taste), not text embeddings.
        suggestedPairs = TagCooccurrence.suggestions(records, existing: laneSpecs.map(\.tags))
        var lists: [[StoryCandidate]] = []
        for spec in rankingLanes {
            let semantic = activePack.isVisual ? [:] : await Embedder.similarities(texts, to: spec.theme)
            if Task.isCancelled { return [] }
            lists.append(Matching.stories(from: records, lane: spec, lanes: laneSpecs, semantic: semantic, excluding: excluded,
                                          now: now, window: window.seconds))
        }
        return Matching.mixed(lists, id: \.id, score: \.score)
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
        var lists: [[AuthorCandidate]] = []
        for spec in rankingLanes {
            let semantic = activePack.isVisual ? [:] : await Embedder.similarities(texts, to: spec.theme)
            if Task.isCancelled { return [] }
            lists.append(Matching.candidates(from: records, lane: spec, semantic: semantic, excluding: excluded,
                                             now: now, window: window.seconds))
        }
        return Matching.mixed(lists, id: \.authorKey, score: \.score)
    }

    static func record(_ post: StoredPost) -> PostRecord {
        PostRecord(guid: post.guid, title: post.title, link: post.link, snippet: post.snippet, authorKey: post.authorKey,
                   authorName: post.authorName, handle: post.handle, categories: post.categories,
                   foundUnder: post.foundUnder, published: post.published, readingMinutes: post.readingMinutes,
                   imageURL: post.imageURL, hnID: post.hnID, hnPoints: post.hnPoints, hnComments: post.hnComments)
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
                                lane: candidate.lane.isEmpty ? activeLane.name : candidate.lane, verdict: verdict, score: candidate.score,
                                bestPostGuid: post.guid, bestPostTitle: post.title, bestPostLink: post.link))
        if verdict == .issue, let issue = ScoutStore.currentIssue(context) {
            let entry = IssueEntry(position: (issue.entries.map(\.position).max() ?? -1) + 1, postGuid: post.guid,
                                   title: post.title, link: post.link, authorName: candidate.name, handle: candidate.handle)
            entry.issue = issue
            context.insert(entry)
        }
        try? context.save()
        learn(tags: candidate.topics, text: candidate.sourceText, imageURL: post.imageURL, liked: verdict != .pass)
        deck.removeAll { $0.authorKey == candidate.authorKey }
        prefetchWhy()
        if verdict != .pass { Task { await reindexSpotlight() } }
    }

    func decideStory(_ story: StoryCandidate, _ verdict: Verdict) {
        let post = story.post
        context.insert(StoryPick(guid: post.guid, title: post.title, link: post.link, authorKey: post.authorKey,
                                 authorName: post.authorName, handle: post.handle, tags: post.categories,
                                 lane: story.lane.isEmpty ? activeLane.name : story.lane, verdict: verdict, score: story.score))
        if verdict == .issue, let issue = ScoutStore.currentIssue(context),
           !issue.entries.contains(where: { $0.postGuid == post.guid }) {
            let entry = IssueEntry(position: (issue.entries.map(\.position).max() ?? -1) + 1, postGuid: post.guid,
                                   title: post.title, link: post.link, authorName: post.authorName, handle: post.handle)
            entry.issue = issue
            context.insert(entry)
        }
        try? context.save()
        learn(tags: post.categories, text: "\(post.title). \(post.snippet)", imageURL: post.imageURL, liked: verdict != .pass)
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
        learn(tags: candidate.topics, text: candidate.sourceText, imageURL: nil, liked: false)
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
        for story in storyDeck.prefix(3) { explain(story) }
        for candidate in deck.prefix(3) { explain(candidate) }
    }

    /// Asks for one story's "why" line, once; the Mac list calls this for the selected row.
    func explain(_ story: StoryCandidate) {
        guard ModelAvailability.current.isAvailable, !whyRequested.contains(story.id) else { return }
        whyRequested.insert(story.id)
        let lane = activeLane
        Task {
            if let line = try? await Writer.why(title: story.post.title, snippet: story.post.snippet, lane: lane,
                                                site: siteContext(for: story.post)) {
                storyWhyLines[story.id] = line
            }
        }
    }

    /// Asks for one writer's "why" line, once.
    func explain(_ candidate: AuthorCandidate) {
        guard ModelAvailability.current.isAvailable, !whyRequested.contains(candidate.authorKey) else { return }
        whyRequested.insert(candidate.authorKey)
        let lane = activeLane
        Task {
            if let line = try? await Writer.why(for: candidate, lane: lane, stats: authorStats[candidate.authorKey],
                                                hnStats: hnStats[candidate.authorKey], site: siteContext(for: candidate.bestPost)) {
                whyLines[candidate.authorKey] = line
            }
        }
    }

    /// Fetches one Medium tag's public feed so its posts, and the tags beside it, join the local catalog.
    /// Returns how many new posts were stored.
    @discardableResult
    func exploreTag(_ tag: String) async -> Int {
        let report = await fetch([.tag(tag)])
        let inserted = (try? Ingest.upsert(report, into: context)) ?? 0
        catalogVersion += 1
        return inserted
    }

    /// Fetches each candidate's Medium tag feed and reports how many posts it has now. Posts found are stored,
    /// so their tags join the catalog. A candidate whose feed is empty or missing is not a live tag.
    func checkTags(_ candidates: [String]) async -> [TopicTags.Checked] {
        let report = await fetch(candidates.map(FeedSource.tag))
        _ = try? Ingest.upsert(report, into: context)
        catalogVersion += 1
        return candidates.map { TopicTags.Checked(tag: $0, posts: report.items[.tag($0)]?.count ?? 0) }
    }

    /// Bumped when the tag catalog changes, so views re-read it.
    private(set) var catalogVersion = 0

    /// The article's Markdown: stored from a full-text feed, or fetched from the writer's own Medium feed
    /// (tag feeds carry only a snippet). Nil when no feed has the full text.
    func article(for guid: String) async -> String? {
        let id = guid
        guard let post = try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.guid == id })).first else { return nil }
        if let markdown = post.contentMarkdown { return markdown }
        guard let source = Self.fullTextSource(for: post) else { return nil }
        let report = await fetch([source])
        _ = try? Ingest.upsert(report, into: context)
        return post.contentMarkdown
    }

    /// Where a post's full text lives: the writer's Medium feed, the publication's Medium feed
    /// (medium.com/<publication>/…), or /feed on a publication's own domain.
    static func fullTextSource(for post: StoredPost) -> FeedSource? {
        if let handle = post.handle { return .author(handle) }
        guard post.hnID == nil, let url = URL(string: post.link), let host = url.host() else { return nil }
        if host == "medium.com" {
            let first = url.pathComponents.dropFirst().first ?? ""
            return first.isEmpty || first.hasPrefix("@") ? nil : .publication(first)
        }
        return URL(string: "https://\(host)/feed").map(FeedSource.feed)
    }

    /// Follows a writer by adding their own feed as a lane in the active pack. Returns false if already there.
    @discardableResult
    func followWriter(handle: String, name: String) -> Bool {
        let feed = "https://medium.com/feed/@\(handle)"
        guard !lanes.contains(where: { $0.tags.contains(feed) }) else { return false }
        addLane(name: "Following \(name)", tags: [feed], theme: "Posts by \(name)")
        return true
    }

    /// Mutes a tag in this pack's taste: its weight goes to the floor, so its cards rank lower. Code only.
    func muteTag(_ tag: String) {
        let record = ScoutStore.taste(for: activePack, in: context)
        var taste = record.taste
        taste.tagWeights[tag] = -1
        record.taste = taste
        try? context.save()
    }

    /// Writers in today's deck whose text is closest to this writer's, by on-device embeddings. Code only.
    func similarWriters(to authorKey: String, limit: Int = 3) async -> [(name: String, percent: Int)] {
        let key = authorKey
        let own = ((try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.authorKey == key }))) ?? [])
            .map { "\($0.title). \($0.snippet)" }.joined(separator: " ")
        guard let vector = Embedder.vector(own) else { return [] }
        let others = Dictionary(deck.filter { $0.authorKey != authorKey }.map { ($0.authorKey, $0.sourceText) },
                                uniquingKeysWith: { first, _ in first })
        let names = Dictionary(deck.map { ($0.authorKey, $0.name) }, uniquingKeysWith: { first, _ in first })
        let similarity = await Embedder.similarities(others, toVector: vector)
        return similarity.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { (names[$0.key] ?? $0.key, Int(($0.value * 100).rounded())) }
    }

    func draftNote(for decision: Decision) async -> String? {
        let guid = decision.bestPostGuid
        let snippet = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.guid == guid })).first?.snippet) ?? ""
        guard ModelAvailability.current.isAvailable else {
            return OutreachCheck.template(title: decision.bestPostTitle, snippet: snippet, lane: decision.lane)
        }
        return (try? await Writer.outreach(title: decision.bestPostTitle, snippet: snippet, lane: decision.lane))
            ?? OutreachCheck.template(title: decision.bestPostTitle, snippet: snippet, lane: decision.lane)
    }
}
