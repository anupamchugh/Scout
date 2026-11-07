//  CompareAll — every preset publication, read on device with the Compare tab's engine.
//
//  swift run CompareAll <report.md> [digest.md]
//
//  Numbers, buckets and readability are computed in code (ScoutKit). The only model text in the report is
//  each story's quoted sentences and one-line reason, from the @Generable StoryCritique rubric.

import Foundation
import FoundationModels
import ScoutKit

guard CommandLine.arguments.count >= 2 else { print("usage: CompareAll <report.md>"); exit(2) }
guard case .available = SystemLanguageModel.default.availability else {
    print("on-device model unavailable: \(SystemLanguageModel.default.availability)"); exit(2)
}

let client = FeedClient(maxConcurrent: 2)
var sides: [PublicationSide] = []
for choice in PublicationChoice.presets {
    do {
        let side = try await PublicationComparison.side(choice, client: client) { done, total in
            if done < total { print("[\(choice.name)] \(done + 1)/\(total)") }
        }
        sides.append(side)
        print("DONE \(choice.name): score \(side.score.map { String(format: "%.2f", $0) } ?? "–"), judged \(side.scored)/\(side.stories.count)")
    } catch {
        print("FAILED \(choice.name): \(error)")
    }
    try? await Task.sleep(for: .seconds(2))
}

func f2(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "–" }
func f0(_ d: Double?) -> String { d.map { String(format: "%.0f", $0) } ?? "–" }
func pct(_ d: Double?) -> String { d.map { "\(Int(($0 * 100).rounded()))%" } ?? "–" }
func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }
func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
let day = DateFormatter(); day.dateFormat = "d MMM yyyy"
func dates(_ s: PublicationSide) -> String {
    guard let a = s.firstPost, let b = s.lastPost else { return "–" }
    let x = day.string(from: a), y = day.string(from: b)
    return x == y ? x : "\(x) – \(y)"
}

var md: [String] = []
md.append("# All publications, read on device")
md.append("")
md.append("Generated \(day.string(from: .now)) on this Mac with ScoutKit's `PublicationComparison`, the engine behind Scout's Compare tab. Each publication's current feed (about ten posts) was read by Apple's on-device model with one neutral `@Generable` rubric; the checker rejects any read whose quotes are not in the article. Every number, bucket and readability score is computed in code.")
md.append("")
md.append("> These are small, recent samples. Member-only posts carry only a preview and are not judged. The rubric is not yet measured against an editor's decisions. Patterns, not verdicts.")
md.append("")
md.append("## Writing and packaging")
md.append("")
md.append("| Publication | Posts (dates) | Writers | Judged | Score /3 | Depth strong | Specific strong | Colon titles | Templated | Top writer | Stock /1k | Reframes /1k | Flesch | Words/sentence |")
md.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for s in sides {
    let r = s.stories.compactMap { $0.signals?.readability }
    md.append("| \(s.choice.name) | \(s.stories.count) (\(dates(s))) | \(s.writers) | \(s.scored) | \(f2(s.score)) | \(pct(s.depthStrong)) | \(pct(s.specificStrong)) | \(pct(s.colonTitles)) | \(pct(s.templatedShare)) | \(pct(s.topWriterShare)) | \(f2(s.stockPerThousand)) | \(f2(s.reframesPerThousand)) | \(f0(mean(r.map(\.fleschReadingEase)))) | \(f0(mean(r.map(\.wordsPerSentence)))) |")
}
md.append("")
md.append("Flesch reading ease: higher reads easier; 60–70 is plain English, 30–50 is typical technical writing.")
md.append("")
md.append("## Good slop vs bad slop")
md.append("")
md.append("Packaging × substance, decided in code. **Formula** = listicle, how-to or colon-subtitle title, or a title template the writer reuses. **Solid** = rubric score ≥ 2.5 of 3 and specificity not weak. **Good slop** = formula, solid. **Bad slop** = formula, thin.")
md.append("")
md.append("| Publication | Plain and solid | Good slop | Bad slop | Plain but thin | Not judged |")
md.append("|---|---|---|---|---|---|")
var bucketsBySide: [String: [String: SlopBucket]] = [:]
for s in sides {
    let b = SlopBucket.buckets(for: s)
    bucketsBySide[s.choice.key] = b
    func n(_ k: SlopBucket) -> Int { b.values.filter { $0 == k }.count }
    md.append("| \(s.choice.name) | \(n(.plainSolid)) | \(n(.goodSlop)) | \(n(.badSlop)) | \(n(.plainThin)) | \(n(.unknown)) |")
}
md.append("")
for s in sides {
    let b = bucketsBySide[s.choice.key] ?? [:]
    let judged = s.stories.filter { b[$0.id] != .unknown }
    guard !judged.isEmpty else { continue }
    md.append("### \(s.choice.name)")
    md.append("")
    md.append("| Bucket | Score | Writer | Story | Most generic sentence (reader's pick, checked) | Reader's reason |")
    md.append("|---|---|---|---|---|---|")
    for st in judged.sorted(by: { ($0.verdict.score ?? 0) > ($1.verdict.score ?? 0) }) {
        let c = st.verdict.critique
        md.append("| \(b[st.id]?.rawValue ?? "") | \(f2(st.verdict.score)) | \(cell(st.writer)) | [\(cell(st.title))](\(st.link)) | \(cell(c.map { $0.genericSentence.isEmpty ? "–" : "“\($0.genericSentence)”" } ?? "")) | \(cell(c?.reason ?? "")) |")
    }
    let flagged = s.stories.filter { $0.verdict.status == .flagged }
    if !flagged.isEmpty {
        md.append("")
        md.append("Flagged by the checker (not scored): \(flagged.map { "\(cell($0.title)) — \($0.verdict.problems.joined(separator: "; "))" }.joined(separator: " · ")).")
    }
    md.append("")
}
md.append("## Method and limits")
md.append("")
md.append("- One feed fetch per publication on the date above; Medium feeds hold about ten posts, so this is a snapshot.")
md.append("- Better Programming stopped publishing in November 2023; its side is its last ten posts.")
md.append("- Readability counts syllables with a simple rule, so Flesch scores are approximate; code blocks are excluded.")
md.append("- “Slop” here names packaging and genericity patterns only. Whether a story is worth curating stays the editor's call.")

try md.joined(separator: "\n").write(to: URL(fileURLWithPath: CommandLine.arguments[1]), atomically: true, encoding: .utf8)
print("REPORT \(CommandLine.arguments[1])")
// Optional second path: the titles, writers and cadence digest from the same reads.
if CommandLine.arguments.count >= 3 {
    try PublicationDigest.markdown(sides, generated: .now, where: "on this Mac")
        .write(to: URL(fileURLWithPath: CommandLine.arguments[2]), atomically: true, encoding: .utf8)
    print("DIGEST \(CommandLine.arguments[2])")
}
