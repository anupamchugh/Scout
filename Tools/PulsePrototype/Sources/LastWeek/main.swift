//  LastWeek — one publication's last seven days: how much it posts, who writes it and how often, and what its titles,
//  subtitles and tags look like. Read on this Mac; every number is code, topics are on-device labels.
//
//  swift run LastWeek levelup.gitconnected.com gitconnected <report.md> [days]
//
//  Medium refuses post pages (403) and the publication feed holds ten posts, so writers, tags and text come from the
//  publication's per-tag feeds (medium.com/feed/<slug>/tagged/<tag>, ten posts each), followed from tag to tag. The
//  sitemap gives the full post count for the same days, and the report says what share of it the feeds reached.

import Foundation
import FoundationModels
import ScoutKit

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: LastWeek <host> <medium-slug> <report.md> [days]"); exit(2) }
let host = args[1], slug = args[2], out = args[3]
let days = args.count >= 5 ? Int(args[4]) ?? 7 : 7
let now = Date.now
let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
let windowDays = Set((0...days).map { SitemapPosts.day(now.addingTimeInterval(-Double($0) * 86_400)) })

// 1. Sitemap: every post in the window (link + day).
let sitemap = await SitemapPosts.latest(host: host, count: 5_000, newest: now, maxDays: days + 1)
    .filter { windowDays.contains($0.day) }
/// Medium's post id: the hex after the last hyphen of the link, which survives a title (slug) edit or a medium.com/@ link.
func postID(_ url: URL) -> String { String(url.lastPathComponent.split(separator: "-").last ?? "") }
let sitemapIDs = Set(sitemap.map { postID($0.url) })
print("sitemap: \(sitemap.count) posts over \(days) days")

// 2. Feeds: the publication feed, then its per-tag feeds, following tags the posts carry.
let client = FeedClient(maxConcurrent: 2)
let seeds = ["programming", "artificial-intelligence", "ai", "software-development", "software-engineering", "coding",
             "technology", "javascript", "python", "web-development", "llm", "machine-learning", "data-science",
             "react", "golang", "java", "csharp", "dotnet", "rust", "devops", "security", "agentic-ai", "ai-agents",
             "generative-ai-tools", "system-design-interview", "productivity", "typescript", "nextjs", "kubernetes"]
var queue = seeds, tried = Set<String>(), fetches = 0
let maxFetches = 160
var posts: [String: FeedItem] = [:]
@MainActor func keep(_ items: [FeedItem]) {
    for item in items where item.published >= cutoff { posts[postID(item.canonicalLink)] = item }
}
if let items = try? await client.fetch(.publication(slug)) { keep(items) }
while let tag = queue.first, fetches < maxFetches {
    queue.removeFirst()
    guard tried.insert(tag).inserted, let url = URL(string: "https://medium.com/feed/\(slug)/tagged/\(tag)") else { continue }
    fetches += 1
    if let items = try? await client.fetch(.feed(url)) {
        keep(items)
        for item in items where item.published >= cutoff {
            for t in item.categories where !tried.contains(t) && !queue.contains(t) { queue.append(t) }
        }
    }
    if fetches % 20 == 0 { print("tag feeds \(fetches), posts in window \(posts.count)") }
    try? await Task.sleep(for: .milliseconds(350))
}
let sample = posts.values.sorted { $0.published > $1.published }
let matched = sample.filter { sitemapIDs.contains(postID($0.canonicalLink)) }.count
let unmatched = sample.filter { !sitemapIDs.contains(postID($0.canonicalLink)) }
print("not in sitemap: " + unmatched.prefix(5).map { "\($0.published) \($0.canonicalLink.absoluteString)" }.joined(separator: " | "))
print("feeds: \(sample.count) posts in window from \(fetches) tag feeds (\(matched) match the sitemap)")

// 3. Topics on device, from every sitemap title in the window.
var topics: [PostTopic?] = []
if case .available = SystemLanguageModel.default.availability {
    for (i, post) in sitemap.enumerated() {
        topics.append(await PostTopicLabeler.label(post.slugTitle))
        if i % 25 == 24 { print("topics \(i + 1)/\(sitemap.count)") }
    }
}

// Code: everything below.
func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "–" : "\(Int((Double(a) / Double(b) * 100).rounded()))%" }
func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }
func median(_ v: [Int]) -> Int? { v.isEmpty ? nil : v.sorted()[v.count / 2] }
let utcDay = DateFormatter(); utcDay.timeZone = .init(identifier: "UTC"); utcDay.dateFormat = "yyyy-MM-dd"
let utcHour = DateFormatter(); utcHour.timeZone = .init(identifier: "UTC"); utcHour.dateFormat = "HH"

let perDay = Dictionary(grouping: sitemap, by: \.day).mapValues(\.count).sorted { $0.key > $1.key }

// Writers (within the feed sample: lower bounds).
let byWriter = Dictionary(grouping: sample, by: \.creator)
let writerRows = byWriter.map { name, items -> (name: String, posts: Int, days: Int, maxDay: Int, titles: [String]) in
    let perDay = Dictionary(grouping: items) { utcDay.string(from: $0.published) }.mapValues(\.count)
    return (name, items.count, perDay.count, perDay.values.max() ?? 0, items.map(\.title))
}.sorted { ($0.posts, $1.name) > ($1.posts, $0.name) }
let topFive = writerRows.prefix(5).reduce(0) { $0 + $1.posts }
let oneOff = writerRows.filter { $0.posts == 1 }.count

// Release batches: posts within ten minutes of the previous one belong to one batch.
let times = sample.map(\.published).sorted()
var batches: [[Date]] = []
for t in times {
    if let last = batches.last?.last, t.timeIntervalSince(last) <= 600 { batches[batches.count - 1].append(t) } else { batches.append([t]) }
}
let hours = Dictionary(grouping: sample) { utcHour.string(from: $0.published) }.mapValues(\.count).sorted { $0.key < $1.key }

// Titles, subtitles, tags, length.
let shapes = Dictionary(grouping: sample) { TitleShape.classify($0.title) }.mapValues(\.count)
let templates = TitleTemplates.repeated(sample.map { ($0.creator, $0.title) })
let titleWords = sample.map { $0.title.split(separator: " ").count }
let originality = TitleOriginality.report(titles: sitemap.map(\.slugTitle))
struct Read { var item: FeedItem; var markdown: String?; var audit: MetadataAudit; var subtitle: String? }
let reads = sample.map { item -> Read in
    let md = item.contentHTML.map { HTMLToMarkdown.convert($0) }
    let full = md.flatMap { HTMLToMarkdown.isPreview($0) ? nil : $0 }
    let sub = full.flatMap(MetadataAudit.subtitle(fromMarkdown:))
    return Read(item: item, markdown: full, audit: MetadataAudit.audit(title: item.title, tags: item.categories, subtitle: sub, articleText: full), subtitle: sub)
}
let fullText = reads.filter { $0.markdown != nil }
let tagCounts = Dictionary(sample.flatMap(\.categories).map { ($0, 1) }, uniquingKeysWith: +).sorted { ($0.value, $1.key) > ($1.value, $0.key) }
let words: [Int] = fullText.compactMap { read in read.markdown.map { text in text.split(whereSeparator: { $0.isWhitespace }).count } }

// Report.
var md: [String] = [
    "# \(host): the last \(days) days", "",
    "Generated \(now.formatted(date: .abbreviated, time: .shortened)) on this Mac for \(SitemapPosts.day(cutoff)) to \(SitemapPosts.day(now)) (UTC days). The post count comes from the publication's public sitemap. Writers, publish times, tags, subtitles and text come from its per-tag RSS feeds, followed from tag to tag (\(fetches) feeds), because Medium refuses post pages and the main feed holds ten posts. Every number is computed in code; topics are on-device labels of titles.", "",
    "## Output", "",
    "- **At least \(sitemap.count + unmatched.count) posts**, about \((sitemap.count + unmatched.count) / max(days, 1)) a day: \(sitemap.count) in the sitemap plus \(unmatched.count) the feeds show but the sitemap does not list yet (it lags). Sitemap by day: " + perDay.map { "\($0.key) \($0.value)" }.joined(separator: " · "),
    "- **\(sample.count) reached through feeds** (\(pct(sample.count, sitemap.count + unmatched.count)) of all posts seen). Writer, title, subtitle and tag figures below describe this sample, so writer counts are lower bounds.", "",
    "## Writers", "",
    "- **\(writerRows.count) writers** in the sample. The top 5 wrote \(pct(topFive, sample.count)) of it; \(oneOff) writers (\(pct(oneOff, writerRows.count))) appear once.", "",
    "| Writer | Posts | Days posting | Most in one day | Titles |", "|---|---|---|---|---|"]
for w in writerRows.prefix(15) {
    md.append("| \(cell(w.name)) | \(w.posts) | \(w.days) | \(w.maxDay) | \(w.titles.prefix(3).map(cell).joined(separator: " · ")) |")
}
md += ["", "## When posts go out", "",
       "- **\(batches.count) release batches** (posts within ten minutes of each other); median batch \(median(batches.map(\.count)) ?? 0) posts, largest \(batches.map(\.count).max() ?? 0).",
       "- Hour (UTC): " + hours.map { "\($0.key)h \($0.value)" }.joined(separator: " · "), "",
       "## Titles", "",
       "| Shape | Posts | Share |", "|---|---|---|"]
for shape in TitleShape.allCases where (shapes[shape] ?? 0) > 0 {
    md.append("| \(shape.rawValue) | \(shapes[shape]!) | \(pct(shapes[shape]!, sample.count)) |")
}
let templatedTitles = Set(templates.flatMap(\.titles))
let formula = sample.filter { SlopBucket.formulaic(TitleShape.classify($0.title), templated: templatedTitles.contains($0.title)) }.count
md += ["", "- **Formula titles** (listicle, how-to, colon subtitle or a reused template): \(pct(formula, sample.count)). Median title length \(median(titleWords) ?? 0) words.",
       "- **Writers reusing one title template:** " + (templates.isEmpty ? "none" : templates.map { "\(cell($0.writer)) ×\($0.titles.count) (\($0.markers.map(\.rawValue).joined(separator: "+")))" }.joined(separator: " · ")),
       "- **Repeated ideas across all \(sitemap.count) sitemap titles:** \(originality.nearDuplicateShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "–") have a near-twin (cosine ≥ \(originality.threshold)); mean nearest similarity \(originality.meanNearest.map { String(format: "%.2f", $0) } ?? "–")."]
for p in originality.closestPairs.prefix(5) { md.append("  - \(String(format: "%.2f", p.similarity)): \(cell(p.first)) / \(cell(p.second))") }
let withSub = fullText.filter { $0.audit.hasSubtitle }
let genericSub = withSub.filter { $0.audit.genericSubtitle }
let genericExamples: [String] = genericSub.prefix(3).map { read in "“" + cell(read.subtitle ?? "") + "”" }
let subtitleLine: String = "- **Subtitle present:** \(withSub.count) of \(fullText.count) full-text posts; **generic** (\"This article explains…\"): \(genericSub.count)"
    + (genericExamples.isEmpty ? "." : ": " + genericExamples.joined(separator: " · "))
md += ["", "## Subtitles, text and tags", "",
       "- **Full text in the feed:** \(fullText.count) of \(sample.count) (\(pct(fullText.count, sample.count))); the rest are member-only previews.",
       subtitleLine,
       "- **Length:** median \(median(words).map { "\($0) words" } ?? "–") of full text.",
       "- **Tags:** \(pct(sample.filter { $0.categories.count >= MetadataAudit.tagLimit }.count, sample.count)) use all five; \(fullText.filter { !$0.audit.trendingTagsUnmentioned.isEmpty }.count) full-text posts carry a trending tag their title and text never mention.",
       "- Most used: " + tagCounts.prefix(15).map { "\($0.key) \($0.value)" }.joined(separator: " · ")]
let topicCounts = PostTopicLabeler.counts(topics)
md += ["", "## Topics (on-device, \(topics.compactMap { $0 }.count) of \(sitemap.count) sitemap titles)", "", "| Topic | Posts | Share |", "|---|---|---|"]
for t in topicCounts { md.append("| \(t.topic.rawValue) | \(t.count) | \(pct(t.count, topics.compactMap { $0 }.count)) |") }
md += ["", "## Limits", "",
       "- Feeds reach only part of the week; tags with fewer than ten recent posts are reached fully, busy tags only for their latest ten.",
       "- Sitemap titles are rebuilt from links, so title shapes use the feed sample, and topics and repeated ideas use the sitemap.",
       "- Publish times are the feed's; days are UTC."]
try md.joined(separator: "\n").write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
print("REPORT \(out)")
