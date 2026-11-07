//  PulsePrototype — compare writers' own Medium feeds with a publication's average post.
//
//  swift run PulsePrototype <handles.json> <publication-slug> <out.json> [--write]
//
//  Code computes every number. With --write, the on-device model picks one evidence post per writer from a
//  DynamicGenerationSchema whose anyOf values are that writer's post IDs, and writes one sentence; a checker
//  rejects sentences with digits or links and evidence that is not the writer's own post.

import Foundation
import FoundationModels
import ScoutKit

// MARK: Content signals, from Markdown (code only)

struct PostSignals: Codable {
    var guid: String
    var title: String
    var link: String
    var published: Date
    var tags: [String]
    var fullText: Bool
    var words: Int
    var headings: Int
    var codeBlocks: Int
    var images: Int
    var links: Int
}

func signals(_ item: FeedItem) -> PostSignals {
    let markdown = item.contentHTML.map { HTMLToMarkdown.convert($0) } ?? ""
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    let full = !markdown.isEmpty && !HTMLToMarkdown.isPreview(markdown)
    func count(_ pattern: String) -> Int {
        (try? Regex(pattern)).map { markdown.matches(of: $0).count } ?? 0
    }
    return PostSignals(
        guid: item.guid, title: item.title, link: item.canonicalLink.absoluteString, published: item.published,
        tags: item.categories, fullText: full,
        words: full ? markdown.split(whereSeparator: \.isWhitespace).count : 0,
        headings: headingCount(lines),
        codeBlocks: lines.filter { $0.hasPrefix("```") }.count / 2,
        images: count(#"!\[[^\]]*\]\("#),
        links: count(#"(?<!!)\[[^\]]+\]\(https?://"#))
}

/// Markdown headings outside code fences (a `#` comment inside code is not a heading).
func headingCount(_ lines: [Substring]) -> Int {
    var inFence = false
    var count = 0
    for line in lines {
        if line.hasPrefix("```") { inFence.toggle() } else if !inFence && line.hasPrefix("#") { count += 1 }
    }
    return count
}

struct Profile: Codable {
    var key: String
    var name: String
    var posts: [PostSignals]
    var postsPerWeek: Double
    var lastPost: Date?
    var activeIn90Days: Bool
    var medianWords: Int?
    var shareWithCode: Double?
    var meanHeadings: Double?
    var meanImages: Double?
    var topTags: [String]
}

func median(_ values: [Int]) -> Int? {
    let s = values.sorted()
    guard !s.isEmpty else { return nil }
    return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
}

func profile(key: String, name: String, items: [FeedItem], now: Date) -> Profile {
    let posts = items.map(signals)
    let full = posts.filter(\.fullText)
    let st = stats(for: items)
    let last = items.map(\.published).max()
    func mean(_ f: (PostSignals) -> Int) -> Double? {
        full.isEmpty ? nil : Double(full.map(f).reduce(0, +)) / Double(full.count)
    }
    return Profile(
        key: key, name: name, posts: posts, postsPerWeek: st.postsPerWeek, lastPost: last,
        activeIn90Days: last.map { now.timeIntervalSince($0) < 90 * 86_400 } ?? false,
        medianWords: median(full.map(\.words)),
        shareWithCode: full.isEmpty ? nil : Double(full.filter { $0.codeBlocks > 0 }.count) / Double(full.count),
        meanHeadings: mean(\.headings), meanImages: mean(\.images),
        topTags: st.topTags.map(\.tag))
}

// MARK: Model step (words only)

struct Note: Codable {
    var key: String
    var evidenceGuid: String?
    var evidenceTitle: String?
    var sentence: String?
    var flagged: String?
}

func writeNotes(for profiles: [Profile], baseline: Profile) async -> [Note] {
    guard case .available = SystemLanguageModel.default.availability else {
        print("MODEL unavailable: \(SystemLanguageModel.default.availability)")
        return []
    }
    var notes: [Note] = []
    for p in profiles {
        let recent = Array(p.posts.sorted { $0.published > $1.published }.prefix(8))
        guard !recent.isEmpty else { continue }
        let schema = DynamicGenerationSchema(name: "WriterNote", properties: [
            .init(name: "evidenceGuid", schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(recent.map(\.guid))])),
            .init(name: "sentence", schema: DynamicGenerationSchema(type: String.self, guides: [])),
        ])
        let facts = """
            Writer facts, computed by the app: \(p.activeIn90Days ? "posted in the last ninety days" : "no posts in the last ninety days"); \
            usual length \(p.medianWords.map { "\($0) words" } ?? "unknown") against the publication's \(baseline.medianWords.map { "\($0)" } ?? "unknown"); \
            \(p.shareWithCode.map { $0 >= 0.5 ? "most posts include code" : "most posts have no code" } ?? "code unknown"); \
            top tags \(p.topTags.joined(separator: ", ")).
            Publication facts, computed by the app: \
            \(baseline.shareWithCode.map { $0 >= 0.5 ? "most posts include code" : "most posts have no code" } ?? "code unknown"); \
            top tags \(baseline.topTags.joined(separator: ", ")).
            """
        let list = recent.map { "<post>id: \($0.guid); title: \($0.title); tags: \($0.tags.joined(separator: ", "))</post>" }
            .joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You help an editor compare a writer with a publication's typical post. Choose the one post that best \
            shows what this writer covers, then write one plain sentence comparing the writer's topics or use of \
            code with the publication facts. Say nothing about the publication beyond its listed facts. \
            No numbers, no links, no praise words.
            """)
        do {
            let response = try await session.respond(
                to: "\(facts)\n\(list)",
                schema: try GenerationSchema(root: schema, dependencies: []),
                options: GenerationOptions(samplingMode: .greedy))
            let guid = try response.content.value(String.self, forProperty: "evidenceGuid")
            let sentence = try response.content.value(String.self, forProperty: "sentence")
            // Checker: the evidence must be this writer's post; the sentence may not carry digits or links.
            var flag: String?
            let post = p.posts.first { $0.guid == guid }
            if post == nil { flag = "evidence is not this writer's post" }
            else if sentence.contains(where: \.isNumber) { flag = "sentence contains a number" }
            else if sentence.contains("http") { flag = "sentence contains a link" }
            notes.append(Note(key: p.key, evidenceGuid: guid, evidenceTitle: post?.title,
                              sentence: flag == nil ? sentence : nil, flagged: flag))
        } catch {
            notes.append(Note(key: p.key, flagged: "model error: \(error.localizedDescription)"))
        }
    }
    return notes
}

// MARK: Run

struct Output: Codable {
    var generated: Date
    var publication: String
    var baseline: Profile
    var baselineWriters: Int
    var requested: Int
    var resolved: Int
    var failed: [String]
    var writers: [Profile]
    var notes: [Note]
}

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: PulsePrototype <handles.json> <publication-slug> <out.json> [--write]")
    exit(2)
}
let handles = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let slug = args[2]
let now = Date.now
let client = FeedClient(maxConcurrent: 6)

let pubItems = try await client.fetch(.publication(slug))
let baseline = profile(key: slug, name: slug, items: pubItems, now: now)
let report = await client.fetchAll(handles.map { FeedSource.author($0) })

var writers: [Profile] = []
var failed: [String] = []
for handle in handles {
    let source = FeedSource.author(handle)
    if let items = report.items[source], !items.isEmpty {
        writers.append(profile(key: handle, name: items[0].creator, items: items, now: now))
    } else {
        failed.append(handle)
    }
}
writers.sort { ($0.lastPost ?? .distantPast) > ($1.lastPost ?? .distantPast) }

let active = writers.filter(\.activeIn90Days)
let notes = args.contains("--write") ? await writeNotes(for: Array(active.prefix(6)), baseline: baseline) : []

let out = Output(generated: now, publication: slug, baseline: baseline,
                 baselineWriters: Set(pubItems.map(\.authorKey)).count, requested: handles.count,
                 resolved: writers.count, failed: failed, writers: writers, notes: notes)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(out).write(to: URL(fileURLWithPath: args[3]))

func fmt(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "–" }
print("BASELINE \(slug): \(pubItems.count) posts, median words \(baseline.medianWords.map(String.init) ?? "–"), code share \(fmt(baseline.shareWithCode)), headings \(fmt(baseline.meanHeadings)), images \(fmt(baseline.meanImages))")
print("WRITERS requested \(handles.count), resolved \(writers.count), failed \(failed.count), active in 90 days \(active.count)")
let allFull = writers.flatMap(\.posts).filter(\.fullText)
print("WRITERS' POSTS \(writers.flatMap(\.posts).count), with full text \(allFull.count), median words \(median(allFull.map(\.words)).map(String.init) ?? "–"), code share \(fmt(allFull.isEmpty ? nil : Double(allFull.filter { $0.codeBlocks > 0 }.count) / Double(allFull.count)))")
for n in notes { print("NOTE \(n.key): \(n.sentence ?? "—") [\(n.evidenceTitle ?? "—")] \(n.flagged ?? "")") }
