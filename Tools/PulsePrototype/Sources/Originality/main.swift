//  Originality — how often each publication repeats an idea in its titles over the last 30 days.
//
//  swift run Originality <report.md>
//
//  Titles come from sitemaps (rebuilt from links). Vectors come from Natural Language's English sentence embedding;
//  nearest-neighbour similarity, the near-duplicate threshold and every count are code. No text generation.

import Foundation
import ScoutKit

guard CommandLine.arguments.count >= 2 else { print("usage: Originality <report.md>"); exit(2) }
let cutoff = SitemapPosts.day(Date.now.addingTimeInterval(-30 * 86_400))
let pubs: [(name: String, host: String, daily: Bool)] = [
    ("Level Up Coding", "levelup.gitconnected.com", true), ("Stackademic", "blog.stackademic.com", true),
    ("ITNEXT", "itnext.io", false), ("JavaScript in Plain English", "javascript.plainenglish.io", false),
]
var md = ["# Title originality: the last 30 days", "",
          "Generated \(Date.now.formatted(date: .abbreviated, time: .shortened)) on this Mac. Each title (rebuilt from its link) is embedded with Natural Language's English sentence embedding; code finds its nearest other title in the same publication and counts a title whose nearest neighbour is at or above cosine \(TitleOriginality.defaultThreshold) as repeating an idea or a headline template (calibrated on real pairs). This measures repeated ideas in titles, not the writing.", "",
          "| Publication | Titles | Mean nearest similarity | Titles repeating an idea or template | Not embedded |", "|---|---|---|---|---|"]
var sections: [String] = []
for pub in pubs {
    let posts = pub.daily
        ? await SitemapPosts.latest(host: pub.host, count: .max, maxDays: 30)
        : await SitemapPosts.single(host: pub.host).filter { $0.day >= cutoff }
    let r = TitleOriginality.report(titles: posts.map(\.slugTitle))
    func f(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "–" }
    func p(_ d: Double?) -> String { d.map { "\(Int(($0 * 100).rounded()))%" } ?? "–" }
    md.append("| \(pub.name) | \(r.titles) | \(f(r.meanNearest)) | \(p(r.nearDuplicateShare)) | \(r.unembedded) |")
    sections += ["", "## \(pub.name): closest title pairs", "", "| Similarity | Title | Title |", "|---|---|---|"]
    sections += r.closestPairs.map { "| \(String(format: "%.3f", $0.similarity)) | \($0.first) | \($0.second) |" }
    print("DONE \(pub.name): \(r.titles) titles, near-duplicates \(p(r.nearDuplicateShare)), mean nearest \(f(r.meanNearest))")
}
md += sections
md += ["", "## Limits", "",
       "- Titles rebuilt from links lose capitals and punctuation; series parts (\"part 1\", \"part 2\") count as near-duplicates by design.",
       "- ITNEXT and JavaScript in Plain English are dated by last edit (published or edited in the window).",
       "- Data Science Collective's medium.com sitemap refuses automated reads; Better Programming has no new posts."]
try md.joined(separator: "\n").write(to: URL(fileURLWithPath: CommandLine.arguments[1]), atomically: true, encoding: .utf8)
print("REPORT \(CommandLine.arguments[1])")
