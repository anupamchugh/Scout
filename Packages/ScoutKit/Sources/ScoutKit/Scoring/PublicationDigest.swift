//
//  PublicationDigest.swift
//  ScoutKit
//
//  The state of several publications as one Markdown digest: how often each posts, who writes it, and every
//  title with its shape, slop bucket and rubric score. Written entirely by code from computed sides; the only
//  model output inside is what the sides already carry (ratings and the checked quotes behind them).
//

import Foundation

public enum PublicationDigest {

    /// Hours between a side's first and last post in the feed.
    public static func spanHours(_ side: PublicationSide) -> Double? {
        guard let first = side.firstPost, let last = side.lastPost else { return nil }
        return last.timeIntervalSince(first) / 3600
    }

    /// How the feed's posts are spread in time, in words: a batch, a day, or posts per day.
    public static func cadence(_ side: PublicationSide) -> String {
        guard let hours = spanHours(side), side.stories.count > 1 else { return "\(side.stories.count) post" }
        let n = side.stories.count
        if hours < 1 { return "\(n) posts released within \(max(1, Int((hours * 60).rounded()))) minutes (one batch)" }
        if hours < 24 { return "\(n) posts within \(Int(hours.rounded())) hours" }
        let perDay = Double(n) / (hours / 24)
        return "\(n) posts over \(String(format: "%.1f", hours / 24)) days, about \(String(format: "%.1f", perDay)) a day"
    }

    /// Writers by number of posts in the feed, most first, ties by name.
    public static func writers(_ side: PublicationSide) -> [(writer: String, posts: Int)] {
        Dictionary(grouping: side.stories, by: \.writer).map { ($0.key, $0.value.count) }
            .sorted { $0.posts != $1.posts ? $0.posts > $1.posts : $0.writer < $1.writer }
    }

    static func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }
    static func f2(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "–" }
    static func pct(_ d: Double) -> String { "\(Int((d * 100).rounded()))%" }

    public static func markdown(_ sides: [PublicationSide], generated: Date, where place: String) -> String {
        let day = DateFormatter()
        day.dateFormat = "d MMM yyyy HH:mm"
        var md = ["# The state of programming publications", "",
                  "Generated \(day.string(from: generated)) \(place). Each feed's latest posts were read on device by Apple Intelligence with Scout's neutral `@Generable` rubric; a checker rejects reads whose quotes aren't in the article. Frequencies, writer counts, title shapes and slop buckets are computed in code. A feed holds about ten posts, so this is a snapshot.", ""]
        md += ["## At a glance", "",
               "| Publication | Latest post | Cadence in feed | Writers | Top writer | Judged | Score /3 | Formula titles | Good / bad slop |",
               "|---|---|---|---|---|---|---|---|---|"]
        for side in sides {
            let buckets = SlopBucket.buckets(for: side)
            let good = buckets.values.filter { $0 == .goodSlop }.count, bad = buckets.values.filter { $0 == .badSlop }.count
            let formula = side.stories.isEmpty ? 0 : Double(side.stories.filter {
                SlopBucket.formulaic($0.shape, templated: side.templated.flatMap(\.titles).contains($0.title))
            }.count) / Double(side.stories.count)
            let top = writers(side).first.map { "\(cell($0.writer)) (\($0.posts))" } ?? "–"
            let latest = side.lastPost.map { day.string(from: $0) } ?? "–"
            md.append("| \(side.choice.name)\(PublicationBriefing.isArchived(side, now: generated) ? " (archived)" : "") | \(latest) | \(cadence(side)) | \(side.writers) | \(top) | \(side.scored) of \(side.stories.count) | \(f2(side.score)) | \(pct(formula)) | \(good) / \(bad) |")
        }
        md.append("")
        for side in sides {
            let buckets = SlopBucket.buckets(for: side)
            md += ["## \(side.choice.name)", "", "**Cadence:** \(cadence(side)). **Writers:** " +
                   writers(side).map { "\(cell($0.writer)) ×\($0.posts)" }.joined(separator: ", ") + ".", ""]
            if !side.templated.isEmpty {
                md += ["**Repeated title templates:** " + side.templated.map { "\(cell($0.writer)) ×\($0.titles.count)" }.joined(separator: ", ") + ".", ""]
            }
            md += ["| Posted | Writer | Title | Shape | Bucket | Score |", "|---|---|---|---|---|---|"]
            for story in side.stories.sorted(by: { $0.published > $1.published }) {
                md.append("| \(day.string(from: story.published)) | \(cell(story.writer)) | [\(cell(story.title))](\(story.link)) | \(story.shape.rawValue) | \(buckets[story.id]?.rawValue ?? "") | \(f2(story.verdict.score)) |")
            }
            md.append("")
        }
        md += ["## Method and limits", "",
               "- Formula titles: listicle, how-to or “Topic: subtitle”, or a template the same writer reuses. Good slop = formula title over solid substance (score ≥ 2.5, specificity not weak); bad slop = formula title over thin substance.",
               "- Member-only posts carry a preview in feeds and are “Not judged”.",
               "- Cadence describes the posts in the feed, which publications often release in batches; it is not a monthly rate."]
        return md.joined(separator: "\n")
    }
}
