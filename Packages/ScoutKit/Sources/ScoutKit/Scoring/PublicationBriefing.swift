//
//  PublicationBriefing.swift
//  ScoutKit
//
//  What Siri says about publications, written by code from computed sides. Two depths: a quick scan of
//  several feeds (titles, writers and prose signals, no model, a few seconds) and a full on-device read of
//  one publication (the StoryCritique rubric and good/bad slop buckets, a minute or two).
//

import Foundation

public enum PublicationBriefing {

    /// A side with titles, writers and prose signals but no model reads.
    public static func quickSide(_ choice: PublicationChoice, client: FeedClient = FeedClient()) async throws -> PublicationSide {
        let items = try await client.fetch(choice.source)
        let stories = await PublicationComparison.read(items, critic: { _, _ in
            CritiqueVerdict(status: .failed, critique: nil, problems: ["quick scan: not read by the model"])
        })
        return PublicationComparison.summarize(choice, stories: stories)
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) percent" }

    static func day(_ date: Date?) -> String {
        date.map { $0.formatted(.dateTime.day().month(.wide).year()) } ?? "an unknown date"
    }

    public static func isArchived(_ side: PublicationSide, now: Date = .now) -> Bool {
        side.lastPost.map { now.timeIntervalSince($0) > 90 * 86_400 } ?? false
    }

    /// One or two sentences per publication: freshness, formula titles, concentration, stock phrases.
    public static func overview(_ sides: [PublicationSide], now: Date = .now) -> String {
        sides.map { side in
            var parts: [String] = []
            if isArchived(side, now: now) {
                parts.append("\(side.choice.name) is archived; its latest post is from \(day(side.lastPost)).")
            } else {
                parts.append("\(side.choice.name): \(side.stories.count) recent posts by \(side.writers) writers.")
            }
            var flags: [String] = []
            if side.colonTitles >= 0.5 { flags.append("\(percent(side.colonTitles)) formula titles") }
            if !side.templated.isEmpty, let t = side.templated.first {
                flags.append("\(t.writer) reuses one title template \(t.titles.count) times")
            }
            let topPosts = Int((side.topWriterShare * Double(side.stories.count)).rounded())
            if side.topWriterShare >= 0.3, topPosts >= 2, let top = side.topWriter {
                flags.append("\(top) wrote \(percent(side.topWriterShare)) of them")
            }
            if let stock = side.stockPerThousand, stock >= 0.5 { flags.append("stock phrases show up often") }
            parts.append(flags.isEmpty ? "No strong slop patterns in the titles." : "Watch for: \(flags.joined(separator: "; ")).")
            return parts.joined(separator: " ")
        }
        .joined(separator: " ")
    }

    /// A full read of one publication, with the stories in the bad-slop bucket named.
    public static func slopReport(_ side: PublicationSide, now: Date = .now) -> String {
        let buckets = SlopBucket.buckets(for: side)
        func n(_ b: SlopBucket) -> Int { buckets.values.filter { $0 == b }.count }
        let judged = side.stories.count - n(.unknown)
        var text = "\(side.choice.name)"
        text += isArchived(side, now: now) ? ", archived since \(day(side.lastPost)). " : ". "
        guard judged > 0 else {
            return text + "None of its \(side.stories.count) latest posts had full text in the feed, so none were judged."
        }
        text += "I read \(judged) of its \(side.stories.count) latest posts on this device"
        if let score = side.score { text += "; writing score \(score.formatted(.number.precision(.fractionLength(1)))) out of 3" }
        text += ". \(n(.plainSolid) + n(.goodSlop)) solid, \(n(.badSlop)) bad slop, \(n(.goodSlop)) good slop. "
        let bad = side.stories.filter { buckets[$0.id] == .badSlop }.prefix(2).map { "“\($0.title)” by \($0.writer)" }
        if !bad.isEmpty { text += "Bad slop: \(bad.joined(separator: " and ")). " }
        if let top = side.topStory { text += "Best read: “\(top.title)” by \(top.writer)." }
        if side.previewOnly > 0 { text += " \(side.previewOnly) member-only posts were not judged." }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
