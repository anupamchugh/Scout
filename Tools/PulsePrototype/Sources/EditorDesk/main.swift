//  EditorDesk — an editor team over two publications, on this Mac.
//
//  swift run EditorDesk <pulse.json> <publication-slug> <report.md> [--per-writer 3]
//
//  Reader:     WritingCorpus's CurationJudge rates each article (theme fit, novelty, quality, one reason) on device.
//  Trajectory: code compares each writer's older and newer posts (length, code share, tags, gap between posts).
//  Editor:     code writes the report; the only model text in it is each article's one-line reason.
//  The judge's agreement with the owner's past decisions is printed in the report, because it is weak.

import CurationJudge
import Foundation
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

let corpusURL = URL(fileURLWithPath: NSString("~/Desktop/workspace/WritingCorpus/corpus").expandingTildeInPath)
let profile = try OwnerProfile.load(corpus: try CorpusIndex.load(directory: corpusURL))
let model = AppleCurationModel()
if let problem = model.availabilityProblem { print("on-device model unavailable: \(problem)"); exit(2) }
let judge = CurationJudge(model: model, profile: profile)

// MARK: Reader

struct Judged { var group: String; var writer: String; var title: String; var link: String; var published: Date
                var j: ItemJudgement }

func read(_ items: [FeedItem], group: String) async -> [Judged] {
    var out: [Judged] = []
    for (n, item) in items.enumerated() {
        let markdown = item.contentHTML.map { HTMLToMarkdown.convert($0) }
        let text = markdown.flatMap { HTMLToMarkdown.isPreview($0) ? nil : $0 }
        let corpusItem = CorpusItem(id: item.guid, kind: "post", title: item.title, url: item.canonicalLink.absoluteString,
                                    words: text.map { $0.split(whereSeparator: \.isWhitespace).count })
        let j = await judge.judge(item: corpusItem, text: text)
        print("[\(group) \(n + 1)/\(items.count)] \(j.status.rawValue) \(j.composite.map { String(format: "%.2f", $0) } ?? "-") \(item.title.prefix(60))")
        out.append(Judged(group: group, writer: item.creator, title: item.title, link: item.canonicalLink.absoluteString,
                          published: item.published, j: j))
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

func summaryRow(_ name: String, _ js: [Judged]) -> String {
    let scored = js.filter { $0.j.status == .scored }
    return "| \(name) | \(js.count) | \(scored.count) | \(f2(mean(scored.compactMap(\.j.composite)))) | \(f2(mean(scored.compactMap(\.j.quality)))) | \(f2(mean(scored.compactMap(\.j.novelty)))) | \(f2(mean(scored.compactMap(\.j.themeFit)))) |"
}
func storyTable(_ js: [Judged]) -> [String] {
    var rows = ["| Composite | Q | N | Fit | Writer | Story | Reader's reason (on-device model) |", "|---|---|---|---|---|---|---|"]
    for x in js.sorted(by: { ($0.j.composite ?? -1) > ($1.j.composite ?? -1) }) {
        let status = x.j.status == .scored ? f2(x.j.composite) : x.j.status.rawValue
        rows.append("| \(status) | \(f2(x.j.quality)) | \(f2(x.j.novelty)) | \(f2(x.j.themeFit)) | \(cell(x.writer)) | [\(cell(x.title))](\(x.link)) | \(cell(x.j.reason ?? x.j.detail ?? "")) |")
    }
    return rows
}

let dayFmt = DateFormatter(); dayFmt.dateFormat = "d MMM yyyy"
var md: [String] = []
md.append("# Editor desk: \(slug) vs Coffee Bytes writers")
md.append("")
md.append("Generated \(dayFmt.string(from: .now)) on this Mac. Scores come from WritingCorpus's CurationJudge on Apple's on-device model (1–5 scales; composite weights theme fit 0.40, quality 0.35, novelty 0.25, set in code). Every average, count and trajectory below is computed in code. The only model-written text is each story's one-line reason.")
md.append("")
md.append("> **Read this first.** On your 24 labelled Better Programming decisions the judge ranked an accepted piece above a passed one 62% of the time (AUC 0.62; 0.65 without examples, 0.47 with four examples; 50% is a coin flip). Treat scores as a hint, not a curation verdict. Source: `WritingCorpus/REPORT.md`, 4 Nov 2026.")
md.append("")
md.append("## Summary")
md.append("")
md.append("| Group | Stories | Scored | Composite | Quality | Novelty | Theme fit |")
md.append("|---|---|---|---|---|---|---|")
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
md.append("- Member-only posts carry a preview in feeds; those are marked unknown, not scored.")
md.append("- No story was fetched from a web page; Medium pages refuse automated reads, so only RSS text was used.")
md.append("- The two groups differ in time, topic and selection; differences in averages describe these samples only.")

try md.joined(separator: "\n").write(to: URL(fileURLWithPath: args[3]), atomically: true, encoding: .utf8)
print("REPORT \(args[3])")
print(summaryRow(slug, judgedPub))
print(summaryRow("coffee-bytes-writers", judgedBP))
