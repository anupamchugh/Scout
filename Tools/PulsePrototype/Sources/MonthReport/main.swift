//  MonthReport — the last 30 days of each preset publication, from its sitemap, read on this Mac.
//
//  swift run MonthReport <report.md>
//
//  Counts come from sitemaps (code). Publications with per-day sitemaps give exact publish days; single-file sitemaps
//  give last-modified days (published or edited). Topics: the on-device model labels up to 150 most recent titles per
//  publication with the @Generable PostTopic enum; code counts.

import Foundation
import FoundationModels
import ScoutKit

guard CommandLine.arguments.count >= 2 else { print("usage: MonthReport <report.md>"); exit(2) }
guard case .available = SystemLanguageModel.default.availability else {
    print("on-device model unavailable: \(SystemLanguageModel.default.availability)"); exit(2)
}

enum Method: String { case daily = "publish day (per-day sitemap)", lastModified = "last modified (single sitemap)", none = "no sitemap access" }
struct Pub { var name: String; var host: String; var method: Method }
let pubs = [
    Pub(name: "Level Up Coding", host: "levelup.gitconnected.com", method: .daily),
    Pub(name: "Stackademic", host: "blog.stackademic.com", method: .daily),
    Pub(name: "ITNEXT", host: "itnext.io", method: .lastModified),
    Pub(name: "JavaScript in Plain English", host: "javascript.plainenglish.io", method: .lastModified),
    Pub(name: "Better Programming", host: "betterprogramming.pub", method: .lastModified),
    Pub(name: "Data Science Collective", host: "medium.com/data-science-collective", method: .none),
]
let sampleSize = 150
let now = Date.now
let cutoff = SitemapPosts.day(now.addingTimeInterval(-30 * 86_400))

func fetchSingle(_ host: String) async -> [SitemapPost] {
    guard let url = URL(string: "https://\(host)/sitemap/sitemap.xml") else { return [] }
    var request = URLRequest(url: url, timeoutInterval: 60)
    request.setValue("Scout/1.0", forHTTPHeaderField: "User-Agent")
    guard let (data, _) = try? await URLSession.shared.data(for: request), let xml = String(data: data, encoding: .utf8) else { return [] }
    return SitemapPosts.parseSingle(xml)
}

struct Result { var pub: Pub; var posts: [SitemapPost]; var topics: [PostTopic?]; var labelled: Int }
var results: [Result] = []
for pub in pubs {
    var posts: [SitemapPost] = []
    switch pub.method {
    case .daily: posts = await SitemapPosts.latest(host: pub.host, count: .max, newest: now, maxDays: 30)
    case .lastModified: posts = await fetchSingle(pub.host).filter { $0.day >= cutoff }.sorted { $0.day > $1.day }
    case .none: break
    }
    let sample = Array(posts.prefix(sampleSize))
    var topics: [PostTopic?] = []
    for (i, post) in sample.enumerated() {
        topics.append(await PostTopicLabeler.label(post.slugTitle))
        if i % 25 == 24 { print("[\(pub.name)] labelled \(i + 1)/\(sample.count)") }
    }
    print("DONE \(pub.name): \(posts.count) posts in 30 days, \(sample.count) labelled")
    results.append(Result(pub: pub, posts: posts, topics: topics, labelled: sample.count))
}

// Report
func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "–" : "\(Int((Double(n) / Double(d) * 100).rounded()))%" }
var md = ["# Programming publications: the last 30 days", "",
          "Generated \(now.formatted(date: .abbreviated, time: .shortened)) on this Mac, for \(cutoff) to today. Post counts come from each publication's public sitemap (code). Topics are labelled by Apple's on-device model into a fixed `@Generable` enum, from titles rebuilt from links, on up to \(sampleSize) most recent posts per publication; code counts. A topic is a guess from the title, not a quality score.", "",
          "## At a glance", "",
          "| Publication | Posts in 30 days | Per day | Busiest day | Dated by | Topics labelled | Top topic |", "|---|---|---|---|---|---|---|"]
for r in results {
    let byDay = Dictionary(grouping: r.posts, by: \.day).mapValues(\.count)
    let busiest = byDay.max { $0.value < $1.value }.map { "\($0.key) (\($0.value))" } ?? "–"
    let top = PostTopicLabeler.counts(r.topics).first.map { "\($0.topic.rawValue) \(pct($0.count, r.topics.compactMap { $0 }.count))" } ?? "–"
    let count = r.pub.method == .none ? "not available" : "\(r.posts.count)"
    let perDay = r.pub.method == .none ? "–" : String(format: "%.1f", Double(r.posts.count) / 30)
    md.append("| \(r.pub.name) | \(count) | \(perDay) | \(busiest) | \(r.pub.method.rawValue) | \(r.topics.compactMap { $0 }.count) of \(r.labelled) | \(top) |")
}
md += ["", "## Topics by publication (on-device labels)", ""]
let topicHeader = PostTopic.allCases.map(\.rawValue)
md.append("| Publication | " + topicHeader.joined(separator: " | ") + " |")
md.append("|---|" + String(repeating: "---|", count: topicHeader.count))
for r in results where r.labelled > 0 {
    let labelled = r.topics.compactMap { $0 }
    md.append("| \(r.pub.name) | " + PostTopic.allCases.map { t in pct(labelled.filter { $0 == t }.count, labelled.count) }.joined(separator: " | ") + " |")
}
md += ["", "## Compared with Hacker News and DEV (same 30 days)", "",
       "From `2026-11-08-30-day-report-card.md`: Hacker News had 1,300 stories with 100+ points and 281 submissions of any medium.com link; five of these six publications reached HN zero times in 90 days (Data Science Collective: 6). DEV's 300 top articles came from 139 writers, with AI the leading tag (153 of 300).", "",
       "## Limits", "",
       "- Single-file sitemaps date posts by last edit, so their counts include older posts edited in the window (Better Programming, archived since November 2023, shows edits only).",
       "- Data Science Collective lives on medium.com, whose sitemaps refuse automated reads; only its feed (10 posts) is available.",
       "- Titles rebuilt from links lose capitals and punctuation; topic labels use those titles.",
       "- Writers, tags and article text are not in sitemaps; quality scores come only from feed posts (see the publication digest)."]
try md.joined(separator: "\n").write(to: URL(fileURLWithPath: CommandLine.arguments[1]), atomically: true, encoding: .utf8)
print("REPORT \(CommandLine.arguments[1])")
