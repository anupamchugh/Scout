//  EditorDesk — an editor team over two publications, on this Mac.
//
//  swift run EditorDesk <pulse.json> <publication-slug> <report.md> [--per-writer 3]
//
//  Reader:     ScoutKit's StoryCritic fills a neutral @Generable rubric (clarity, depth, evidence, originality as
//              strong / adequate / weak, plus a quote and a reason) on device; CritiqueCheck verifies the quote.
//  Trajectory: code compares each writer's older and newer posts (length, code share, tags, gap between posts).
//  Editor:     code writes the report; the only model text in it is each article's quote and one-line reason.
//  No owner taste profile is used, and this rubric has not yet been measured against editorial decisions.

import Foundation
import FoundationModels
import ScoutKit

// MARK: Inputs

struct PostSignals: Codable { var guid: String; var title: String; var published: Date; var tags: [String]
                              var fullText: Bool; var words: Int; var codeBlocks: Int }
struct Profile: Codable { var key: String; var name: String; var posts: [PostSignals]; var activeIn90Days: Bool
                          var lastPost: Date? }
struct PulseFile: Codable { var writers: [Profile]; var requested: Int; var resolved: Int }

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: EditorDesk <pulse.json> <publication-slug> <report.md> [--per-writer N]"); exit(2) }
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let pulse = try decoder.decode(PulseFile.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let slug = args[2]
let perWriter = args.firstIndex(of: "--per-writer").flatMap { Int(args[$0 + 1]) } ?? 3

guard case .available = SystemLanguageModel.default.availability else {
    print("on-device model unavailable: \(SystemLanguageModel.default.availability)"); exit(2)
}

// MARK: Reader

struct Judged { var group: String; var writer: String; var title: String; var link: String; var published: Date
                var v: CritiqueVerdict }

func read(_ items: [FeedItem], group: String) async -> [Judged] {
    var out: [Judged] = []
    for (n, item) in items.enumerated() {
        let markdown = item.contentHTML.map { HTMLToMarkdown.convert($0) }
        let v = await StoryCritic.critique(title: item.title, markdown: markdown)
        print("[\(group) \(n + 1)/\(items.count)] \(v.status.rawValue) \(v.score.map { String(format: "%.2f", $0) } ?? "-") \(item.title.prefix(60)) \(v.problems.joined(separator: "; "))")
        out.append(Judged(group: group, writer: item.creator, title: item.title, link: item.canonicalLink.absoluteString,
                          published: item.published, v: v))
    }
    return out
}

let client = FeedClient(maxConcurrent: 4)
let pubItems = try await client.fetch(.publication(slug))
let active = pulse.writers.filter(\.activeIn90Days)
let authorReport = await client.fetchAll(active.map { FeedSource.author($0.key) })
let bpItems = active.flatMap { w in
    (authorReport.items[.author(w.key)] ?? []).sorted { $0.published > $1.published }.prefix(perWriter)
}

let judgedPub = await read(pubItems, group: slug)
let judgedBP = await read(Array(bpItems), group: "coffee-bytes-writers")

// MARK: Trajectory (code only)

struct Trajectory { var name: String; var posts: Int; var span: String; var wordsOld: Int?; var wordsNew: Int?
                    var codeOld: Double?; var codeNew: Double?; var tagsOld: [String]; var tagsNew: [String]
                    var medianGapDays: Double?; var active: Bool }

func median(_ v: [Int]) -> Int? { let s = v.sorted(); return s.isEmpty ? nil : s[s.count / 2] }
func topTags(_ posts: [PostSignals], _ n: Int = 3) -> [String] {
    var c: [String: Int] = [:]
    for p in posts { for t in Set(p.tags) { c[t, default: 0] += 1 } }
    return c.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(n).map(\.key)
}
let monthFmt = DateFormatter(); monthFmt.dateFormat = "MMM yyyy"
func trajectory(_ w: Profile) -> Trajectory {
    let posts = w.posts.sorted { $0.published < $1.published }
    let half = posts.count / 2
    let old = Array(posts.prefix(half)), new = Array(posts.suffix(posts.count - half))
    func code(_ p: [PostSignals]) -> Double? {
        let f = p.filter(\.fullText); return f.isEmpty ? nil : Double(f.filter { $0.codeBlocks > 0 }.count) / Double(f.count)
    }
    let gaps = zip(posts.dropFirst(), posts).map { $0.published.timeIntervalSince($1.published) / 86_400 }.sorted()
    return Trajectory(name: w.name, posts: posts.count,
                      span: posts.isEmpty ? "–" : "\(monthFmt.string(from: posts.first!.published)) – \(monthFmt.string(from: posts.last!.published))",
                      wordsOld: median(old.filter(\.fullText).map(\.words)), wordsNew: median(new.filter(\.fullText).map(\.words)),
                      codeOld: code(old), codeNew: code(new), tagsOld: topTags(old), tagsNew: topTags(new),
                      medianGapDays: gaps.isEmpty ? nil : gaps[gaps.count / 2], active: w.activeIn90Days)
}
let trajectories = active.map(trajectory)

// MARK: Editor (code writes the report)

func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
func f2(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "–" }
func pct(_ d: Double?) -> String { d.map { "\(Int(($0 * 100).rounded()))%" } ?? "–" }
func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }

func strongShare(_ js: [Judged], _ key: KeyPath<StoryCritique, CritiqueRating>) -> String {
    let c = js.compactMap(\.v.critique)
    return c.isEmpty ? "–" : pct(Double(c.filter { $0[keyPath: key] == .strong }.count) / Double(c.count))
}
func summaryRow(_ name: String, _ js: [Judged]) -> String {
    let scored = js.filter { $0.v.status == .scored }
    let flagged = js.filter { $0.v.status == .flagged }.count
    let preview = js.filter { $0.v.status == .previewOnly }.count
    return "| \(name) | \(js.count) | \(scored.count) | \(flagged) | \(preview) | \(f2(mean(scored.compactMap(\.v.score)))) | \(strongShare(scored, \.clarity)) | \(strongShare(scored, \.depth)) | \(strongShare(scored, \.evidence)) | \(strongShare(scored, \.originality)) |"
}
func letter(_ r: CritiqueRating?) -> String { r.map { String($0.rawValue.prefix(1)).uppercased() } ?? "–" }
func storyTable(_ js: [Judged]) -> [String] {
    var rows = ["| Score | C·D·E·O | Writer | Story | Quote the reader chose | Reader's reason (on-device model) |",
                "|---|---|---|---|---|---|"]
    for x in js.sorted(by: { ($0.v.score ?? -1) > ($1.v.score ?? -1) }) {
        let c = x.v.critique
        let status = x.v.status == .scored ? f2(x.v.score) : x.v.status.rawValue
        let note = x.v.status == .scored ? (c?.reason ?? "") : x.v.problems.joined(separator: "; ")
        rows.append("| \(status) | \(letter(c?.clarity))·\(letter(c?.depth))·\(letter(c?.evidence))·\(letter(c?.originality)) | \(cell(x.writer)) | [\(cell(x.title))](\(x.link)) | \(cell(c.map { "“\($0.evidenceQuote)”" } ?? "")) | \(cell(note)) |")
    }
    return rows
}

let dayFmt = DateFormatter(); dayFmt.dateFormat = "d MMM yyyy"
var md: [String] = []
md.append("# Editor desk: \(slug) vs Coffee Bytes writers")
md.append("")
md.append("Generated \(dayFmt.string(from: .now)) on this Mac. Each article was read by ScoutKit's `StoryCritic` on Apple's on-device model with one neutral rubric for everyone: clarity, depth, evidence and originality, each strong (3), adequate (2) or weak (1). The model must first copy a sentence from the article; code checks that sentence is really there and flags the read if not. Scores, shares, counts and trajectories are computed in code. No personal taste profile is used.")
md.append("")
md.append("> **Read this first.** This rubric has not yet been measured against your editorial decisions. Scores describe the writing as one on-device model reads it; they are not a curation verdict.")
md.append("")
md.append("## Summary")
md.append("")
md.append("Score is the mean of the four ratings (1–3) over scored stories; the strong columns are the share of scored stories rated strong.")
md.append("")
md.append("| Group | Stories | Scored | Flagged | Preview only | Score | Clarity strong | Depth strong | Evidence strong | Originality strong |")
md.append("|---|---|---|---|---|---|---|---|---|---|")
md.append(summaryRow("\(slug) (publication feed)", judgedPub))
md.append(summaryRow("Coffee Bytes writers, active in last 90 days (own feeds, latest \(perWriter) each)", judgedBP))
md.append("")
md.append("## \(slug): stories")
md.append("")
md.append(contentsOf: storyTable(judgedPub))
md.append("")
md.append("## Coffee Bytes writers: recent stories")
md.append("")
md.append(contentsOf: storyTable(judgedBP))
md.append("")
md.append("## Writer trajectories (code)")
md.append("")
md.append("Older half vs newer half of each writer's latest feed posts (Medium author feeds carry about 10).")
md.append("")
md.append("| Writer | Posts | Span | Median words old → new | Code share old → new | Top tags old → new | Median days between posts |")
md.append("|---|---|---|---|---|---|---|")
for t in trajectories {
    md.append("| \(cell(t.name)) | \(t.posts) | \(t.span) | \(t.wordsOld.map(String.init) ?? "–") → \(t.wordsNew.map(String.init) ?? "–") | \(pct(t.codeOld)) → \(pct(t.codeNew)) | \(t.tagsOld.joined(separator: ", ")) → \(t.tagsNew.joined(separator: ", ")) | \(t.medianGapDays.map { String(format: "%.0f", $0) } ?? "–") |")
}
md.append("")
let years = Dictionary(grouping: pulse.writers.compactMap { $0.lastPost }, by: { Calendar.current.component(.year, from: $0) })
    .mapValues(\.count).sorted { $0.key < $1.key }
md.append("Of \(pulse.resolved) Coffee Bytes writers whose feeds resolved (\(pulse.requested) linked), \(active.count) posted in the last 90 days. Last post by year: \(years.map { "\($0.key): \($0.value)" }.joined(separator: ", ")).")
md.append("")
md.append("## Method and limits")
md.append("")
md.append("- \(slug) is a single publication feed: its latest ~10 posts, often from one day. It is not a trend.")
md.append("- Coffee Bytes writers are the 148 Medium handles linked from the owner's 31 Coffee Bytes issues (Jun 2022 onward), read through their own feeds. Most no longer post; only active writers are judged here.")
md.append("- \(slug) writers mostly have no Medium handle in their links (custom domain), so their trajectories are not available.")
md.append("- Member-only posts carry a preview in feeds; those are marked preview only, not scored.")
md.append("- Long articles are judged on their opening, trimmed to fit the on-device context window.")
md.append("- No story was fetched from a web page; Medium pages refuse automated reads, so only RSS text was used.")
md.append("- The two groups differ in time, topic and selection; differences in averages describe these samples only.")

try md.joined(separator: "\n").write(to: URL(fileURLWithPath: args[3]), atomically: true, encoding: .utf8)
print("REPORT \(args[3])")
print(summaryRow(slug, judgedPub))
print(summaryRow("coffee-bytes-writers", judgedBP))
