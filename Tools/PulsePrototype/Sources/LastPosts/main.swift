//  LastPosts — a publication's recent output, read on this Mac.
//
//  swift run LastPosts levelup.gitconnected.com gitconnected <report.md> [count]
//
//  1. Sitemap: the last N posts (link + day). Code counts posts per day; the on-device model labels each title with a
//     @Generable PostTopic, and code counts the topics.
//  2. Feed: the ~10 posts with full metadata get StoryCritique, MetadataAudit and the TagFit check.
//  3. Writers: each feed writer's own Medium feed, when a handle guessed from the name returns that exact name.

import Foundation
import FoundationModels
import ScoutKit

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: LastPosts <host> <medium-slug> <report.md> [count]"); exit(2) }
let host = args[1], slug = args[2], out = args[3]
let count = args.count >= 5 ? Int(args[4]) ?? 50 : 50
guard case .available = SystemLanguageModel.default.availability else {
    print("on-device model unavailable: \(SystemLanguageModel.default.availability)"); exit(2)
}

// 1. Sitemap + topics
let posts = await SitemapPosts.latest(host: host, count: count)
var topics: [PostTopic?] = []
for (i, post) in posts.enumerated() {
    topics.append(await PostTopicLabeler.label(post.slugTitle))
    if i % 10 == 9 { print("labelled \(i + 1)/\(posts.count)") }
}
let perDay = Dictionary(grouping: posts, by: \.day).mapValues(\.count).sorted { $0.key > $1.key }

// 2. Feed side with tag check
let choice = PublicationChoice.presets.first { $0.key == slug } ?? PublicationChoice(name: host, key: slug)
let side = try await PublicationComparison.side(choice, checkTags: true)
print("feed read: \(side.scored) of \(side.stories.count) judged")

// 3. Writers' own feeds (verified handle guesses)
func handleGuesses(_ name: String) -> [String] {
    let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
    let parts = folded.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    guard !parts.isEmpty else { return [] }
    var seen: [String] = []
    for g in [parts.joined(), parts.joined(separator: "."), parts.joined(separator: "_"), parts.joined(separator: "-")]
    where !seen.contains(g) { seen.append(g) }
    return seen
}
struct WriterFeed { var name: String; var handle: String?; var stats: AuthorStats?; var latest: Date?; var titles: [String] }
var writers: [WriterFeed] = []
let client = FeedClient(maxConcurrent: 2)
for name in Set(side.stories.map(\.writer)).sorted() {
    var found = WriterFeed(name: name, handle: nil, stats: nil, latest: nil, titles: [])
    for guess in handleGuesses(name) {
        if let items = try? await client.fetch(.author(guess)), items.contains(where: { $0.creator == name }) {
            found = WriterFeed(name: name, handle: guess, stats: stats(for: items), latest: items.map(\.published).max(),
                               titles: items.prefix(3).map(\.title))
            break
        }
        try? await Task.sleep(for: .milliseconds(400))
    }
    writers.append(found)
}

// Report
func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/") }
let topicCounts = PostTopicLabeler.counts(topics)
var md = ["# \(choice.name): the last \(posts.count) posts", "",
          "Generated \(Date.now.formatted(date: .abbreviated, time: .shortened)) on this Mac. Post links and days come from the publication's public sitemap; topics are labelled by Apple's on-device model into a fixed `@Generable` enum (title only, so a topic guess, not a quality judgement); counts are code. The ~10 posts in the RSS feed also get the full on-device read, the metadata audit and the tag-fit check.", "",
          "## Output", "",
          "\(posts.count) posts from \(posts.last?.day ?? "–") to \(posts.first?.day ?? "–"): " + perDay.map { "\($0.key): \($0.value)" }.joined(separator: " · "), "",
          "## Topics (on-device labels, \(topics.compactMap { $0 }.count) of \(posts.count) titles)", "",
          "| Topic | Posts | Share |", "|---|---|---|"]
for t in topicCounts { md.append("| \(t.topic.rawValue) | \(t.count) | \(Int((Double(t.count) / Double(max(posts.count, 1)) * 100).rounded()))% |") }
md += ["", "## The last \(posts.count) titles", "", "| Day | Title (from link) | Topic |", "|---|---|---|"]
for (post, topic) in zip(posts, topics) { md.append("| \(post.day) | [\(cell(post.slugTitle))](\(post.url.absoluteString)) | \(topic?.rawValue ?? "–") |") }
md += ["", "## The feed's \(side.stories.count) posts: metadata, tags and reading", "",
       "| Title | Writer | Tags | Trending tags not mentioned | Subtitle | Tags the text supports (on-device, checked) | Score |",
       "|---|---|---|---|---|---|---|"]
for s in side.stories {
    let fit: String
    switch s.tagFit?.status {
    case .checked?: fit = "\(s.tagFit!.supported.count) of \(s.tags.count): \(s.tagFit!.supported.joined(separator: ", "))"
    case .flagged?: fit = "flagged: \(s.tagFit!.problem ?? "")"
    case .failed?: fit = "model failed"
    case nil: fit = "no full text"
    }
    let sub = s.metadata.hasSubtitle ? (s.metadata.genericSubtitle ? "generic: \(cell(s.subtitle ?? ""))" : cell(s.subtitle ?? "")) : "–"
    md.append("| \(cell(s.title)) | \(cell(s.writer)) | \(s.tags.count) | \(s.metadata.trendingTagsUnmentioned.joined(separator: ", ").isEmpty ? "–" : s.metadata.trendingTagsUnmentioned.joined(separator: ", ")) | \(sub) | \(fit) | \(s.verdict.score.map { String(format: "%.2f", $0) } ?? "–") |")
}
md += ["", "## Writers' own feeds", "", "| Writer | Handle | Posts a week | Usual length | Latest post | Recent titles |", "|---|---|---|---|---|---|"]
for w in writers {
    if let st = w.stats, let h = w.handle {
        md.append("| \(cell(w.name)) | @\(h) | \(String(format: "%.1f", st.postsPerWeek)) | \(st.typicalWords.map { "\($0) words" } ?? "–") | \(w.latest?.formatted(date: .abbreviated, time: .omitted) ?? "–") | \(w.titles.map(cell).joined(separator: " · ")) |")
    } else {
        md.append("| \(cell(w.name)) | not found | – | – | – | Medium blocks profile lookups; no guessed handle returned this name |")
    }
}
md += ["", "## Limits", "",
       "- Sitemap titles are rebuilt from links (no capitals or punctuation), so title shapes such as colons can't be measured for all \(posts.count).",
       "- Writers, tags and text exist only for the feed's posts; member-only posts have no text.",
       "- Writer handles are guesses kept only when the feed's author name matches exactly."]
try md.joined(separator: "\n").write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
print("REPORT \(out)")
print("topics: " + topicCounts.map { "\($0.topic.rawValue) \($0.count)" }.joined(separator: ", "))
print("writers found: \(writers.filter { $0.handle != nil }.count) of \(writers.count)")
