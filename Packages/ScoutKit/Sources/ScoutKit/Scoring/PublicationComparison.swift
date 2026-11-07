//
//  PublicationComparison.swift
//  ScoutKit
//
//  Compares two publications' current feeds. Each readable article is read on device by `StoryCritic`
//  (a @Generable rubric, quote checked by code); title shapes, templates and prose signals are counted in
//  code; every number on a side comes from `summarize`, which is pure. A feed holds about ten recent posts,
//  so a side describes those posts and their dates, never the publication's history.
//

import Foundation

/// A publication the editor can pick: a Medium publication slug or any RSS/Atom feed URL.
public struct PublicationChoice: Sendable, Hashable, Identifiable, Codable {
    public var name: String
    public var key: String
    public var id: String { key }

    public init(name: String, key: String) {
        self.name = name
        self.key = key
    }

    public var source: FeedSource {
        if key.hasPrefix("http"), let url = URL(string: key) { return .feed(url) }
        return .publication(key)
    }

    /// Accepts a slug ("gitconnected"), a medium.com publication link, or a feed URL.
    public static func parse(_ input: String) -> PublicationChoice? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let host = url.host(), url.scheme?.hasPrefix("http") == true {
            let parts = url.pathComponents.filter { $0 != "/" }
            if host.hasSuffix("medium.com") {
                let slug = parts.first == "feed" ? parts.dropFirst().first : parts.first
                if let slug, !slug.hasPrefix("@") { return PublicationChoice(name: slug, key: slug) }
            }
            return PublicationChoice(name: host, key: url.absoluteString)
        }
        guard text.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else { return nil }
        return PublicationChoice(name: text, key: text)
    }

    public static let presets = [
        PublicationChoice(name: "Level Up Coding", key: "gitconnected"),
        PublicationChoice(name: "Better Programming", key: "better-programming"),
        PublicationChoice(name: "ITNEXT", key: "itnext"),
        PublicationChoice(name: "JavaScript in Plain English", key: "javascript-in-plain-english"),
        PublicationChoice(name: "Stackademic", key: "stackademic"),
    ]
}

/// One article as the comparison saw it.
public struct ComparedStory: Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var writer: String
    public var link: String
    public var published: Date
    public var shape: TitleShape
    public var verdict: CritiqueVerdict
    public var signals: GenericWritingSignals?

    public init(id: String, title: String, writer: String, link: String, published: Date, shape: TitleShape,
                verdict: CritiqueVerdict, signals: GenericWritingSignals?) {
        self.id = id; self.title = title; self.writer = writer; self.link = link; self.published = published
        self.shape = shape; self.verdict = verdict; self.signals = signals
    }
}

/// Everything shown for one publication, computed in code from its stories.
public struct PublicationSide: Sendable, Equatable {
    public var choice: PublicationChoice
    public var stories: [ComparedStory]
    public var firstPost: Date?
    public var lastPost: Date?
    public var writers: Int
    public var topWriter: String?
    public var topWriterShare: Double
    public var readable: Int
    public var scored: Int
    public var flagged: Int
    public var previewOnly: Int
    public var score: Double?
    public var depthStrong: Double?
    public var evidenceStrong: Double?
    public var specificStrong: Double?
    public var colonTitles: Double
    public var listicleTitles: Double
    public var templated: [RepeatedTemplate]
    public var templatedShare: Double
    public var stockPerThousand: Double?
    public var reframesPerThousand: Double?
    public var assistantStories: Int

    /// The best-scored story, for the side's headline example.
    public var topStory: ComparedStory? {
        stories.filter { $0.verdict.status == .scored }.max { ($0.verdict.score ?? 0) < ($1.verdict.score ?? 0) }
    }
}

public enum PublicationComparison {

    static func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

    /// Pure: every number on a side.
    public static func summarize(_ choice: PublicationChoice, stories: [ComparedStory]) -> PublicationSide {
        let n = Double(max(stories.count, 1))
        let byWriter = Dictionary(grouping: stories, by: \.writer).mapValues(\.count)
        let top = byWriter.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
        let critiques = stories.filter { $0.verdict.status == .scored }.compactMap(\.verdict.critique)
        func strong(_ key: KeyPath<StoryCritique, CritiqueRating>) -> Double? {
            critiques.isEmpty ? nil : Double(critiques.filter { $0[keyPath: key] == .strong }.count) / Double(critiques.count)
        }
        let templates = TitleTemplates.repeated(stories.map { ($0.writer, $0.title) })
        let signals = stories.compactMap(\.signals)
        return PublicationSide(
            choice: choice, stories: stories,
            firstPost: stories.map(\.published).min(), lastPost: stories.map(\.published).max(),
            writers: byWriter.count, topWriter: top?.key, topWriterShare: Double(top?.value ?? 0) / n,
            readable: signals.count,
            scored: critiques.count,
            flagged: stories.filter { $0.verdict.status == .flagged }.count,
            previewOnly: stories.filter { $0.verdict.status == .previewOnly }.count,
            score: mean(critiques.map(\.score)),
            depthStrong: strong(\.depth), evidenceStrong: strong(\.evidence), specificStrong: strong(\.specificity),
            colonTitles: Double(stories.filter { $0.shape == .colonSubtitle }.count) / n,
            listicleTitles: Double(stories.filter { $0.shape == .listicle }.count) / n,
            templated: templates,
            templatedShare: Double(templates.reduce(0) { $0 + $1.titles.count }) / n,
            stockPerThousand: mean(signals.map(\.stockPerThousandWords)),
            reframesPerThousand: mean(signals.map(\.reframesPerThousandWords)),
            assistantStories: signals.filter { !$0.assistantPhrases.isEmpty }.count)
    }

    /// Reads each item; `critic` is the on-device reader (injectable for tests).
    public static func read(
        _ items: [FeedItem],
        critic: @Sendable (String, String?) async -> CritiqueVerdict = { await StoryCritic.critique(title: $0, markdown: $1) },
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> [ComparedStory] {
        var out: [ComparedStory] = []
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            await progress(index, items.count)
            let markdown = item.contentHTML.map { HTMLToMarkdown.convert($0) }
            let readable = markdown.flatMap { HTMLToMarkdown.isPreview($0) ? nil : $0 }
            let verdict = await critic(item.title, markdown)
            out.append(ComparedStory(id: item.guid, title: item.title, writer: item.creator,
                                     link: item.canonicalLink.absoluteString, published: item.published,
                                     shape: TitleShape.classify(item.title), verdict: verdict,
                                     signals: readable.map(GenericWriting.signals)))
        }
        await progress(items.count, items.count)
        return out
    }

    /// Fetches one publication's feed and reads it.
    public static func side(
        _ choice: PublicationChoice, client: FeedClient = FeedClient(),
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> PublicationSide {
        let items = try await client.fetch(choice.source)
        return summarize(choice, stories: await read(items, progress: progress))
    }
}
