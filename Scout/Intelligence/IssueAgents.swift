//
//  IssueAgents.swift
//  Scout
//
//  The newsletter pipeline after you swipe: Curator → Blurber → Spotlight → Editor → Checker.
//  Swift runs the steps in a fixed order. Each agent is a ScoutProfile branch with one job; the Checker
//  (ScoutKit) is code and replaces anything that fails with plain data, flagged for the editor.
//

import Foundation
import FoundationModels
import Observation
import ScoutKit
import SwiftData

@Generable
struct BlurbDraft {
    @Guide(description: "One or two plain sentences on why readers should open this story, using only its feed text. No numbers, no links.")
    var text: String
}

@Generable
struct SpotlightDraft {
    @Guide(description: "Two plain sentences introducing the writer from their own posts only")
    var intro: String
    @Guide(description: "Three interview questions, each naming one of the writer's post titles exactly", .count(3))
    var questions: [String]
}

@Generable
struct IssueTopDraft {
    @Guide(description: "A short issue title of a few words, no numbers")
    var title: String
    @Guide(description: "An intro of at most sixty words drawn from the sections and blurbs. No numbers, no links.")
    var intro: String
}

@MainActor
@Observable
final class IssueAgents {
    enum Step: String, CaseIterable {
        case curator = "Curator · arranging sections"
        case blurber = "Blurber · one line per story"
        case spotlight = "Spotlight · featuring a writer"
        case editor = "Editor · title and intro"
        case checker = "Checker · verifying against your data"

        var title: LocalizedStringResource {
            switch self {
            case .curator: "Curator · arranging sections"
            case .blurber: "Blurber · one line per story"
            case .spotlight: "Spotlight · featuring a writer"
            case .editor: "Editor · title and intro"
            case .checker: "Checker · verifying against your data"
            }
        }
    }

    private(set) var current: Step?
    private(set) var finished: Set<Step> = []
    private(set) var message: String?
    /// Kept so follow-ups ("Shorter", "More technical") continue the same Editor conversation.
    private var editorSession: LanguageModelSession?

    var isRunning: Bool { current != nil }

    /// The stories in the issue as the agents see them, from stored posts and the lanes they were picked in.
    static func cards(for issue: IssueDraft, in context: ModelContext) -> [StoryCard] {
        let picks = (try? context.fetch(FetchDescriptor<StoryPick>())) ?? []
        let decisions = (try? context.fetch(FetchDescriptor<Decision>())) ?? []
        return issue.orderedEntries.map { entry in
            let guid = entry.postGuid
            let post = try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.guid == guid })).first
            let lane = picks.first { $0.guid == guid }?.lane ?? decisions.first { $0.bestPostGuid == guid }?.lane ?? "Picks"
            return StoryCard(id: guid, title: entry.title, subtitle: post?.snippet ?? "", tags: post?.categories ?? [],
                             author: entry.authorName, handle: entry.handle, link: entry.link, lane: lane)
        }
    }

    func run(_ issue: IssueDraft, in context: ModelContext, pack: RolePack) async {
        guard ModelAvailability.current.isAvailable else {
            message = String(localized: "Apple Intelligence isn't available, so the agents can't draft. Your picks and notes are unchanged.")
            return
        }
        message = nil
        finished = []
        let cards = Self.cards(for: issue, in: context)
        guard !cards.isEmpty else { message = String(localized: "Swipe a few stories up first."); return }
        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })

        // 1. Curator: sections and order, choosing only from these IDs.
        current = .curator
        let lineup = IssueChecker.repairLineup(await curate(cards, context: context), cards: cards)
        finish(.curator)

        // 2. Blurber: one session per story, at most two at a time.
        current = .blurber
        let blurbs = await blurb(cards, context: context)
        finish(.blurber)

        // 3. Spotlight: the highest-scoring shortlisted writer with stored posts.
        current = .spotlight
        let spotlight = await feature(context: context)
        finish(.spotlight)

        // 4. Editor: title and intro from the sections and blurbs.
        current = .editor
        let top = await edit(lineup: lineup, blurbs: blurbs, byID: byID, issue: issue, context: context, followUp: nil)
        finish(.editor)

        // 5. Checker: code verifies everything and writes the issue.
        current = .checker
        var flags: [String] = []
        var position = 0
        let entries = Dictionary(uniqueKeysWithValues: issue.entries.map { ($0.postGuid, $0) })
        for section in lineup {
            for id in section.storyIDs {
                guard let entry = entries[id], let card = byID[id] else { continue }
                let checked = IssueChecker.blurb(blurbs[id], card: card)
                entry.position = position
                entry.section = section.lane
                entry.note = checked.text
                entry.flag = checked.flag
                position += 1
            }
        }
        let title = IssueChecker.title(top?.title, fallback: issue.title, editorLine: issue.editorLine)
        let intro = IssueChecker.intro(top?.intro, editorLine: issue.editorLine)
        issue.title = title.text
        if !intro.text.isEmpty { issue.intro = intro.text }
        flags += [title.flag, intro.flag].compactMap { $0 }
        if let (digest, draft) = spotlight {
            let checked = IssueChecker.spotlight(intro: draft.intro, questions: draft.questions, digest: digest)
            issue.spotlightName = checked.block?.name
            issue.spotlightHandle = checked.block?.handle
            issue.spotlightIntro = checked.block?.intro ?? ""
            issue.spotlightQuestions = checked.block?.questions ?? []
            if let flag = checked.flag { flags.append(flag) }
        }
        let content = issue.content
        flags += IssueChecker.mismatches(content.entries, cards: cards)
        issue.agentFlags = flags
        try? context.save()
        finish(.checker)
        current = nil
    }

    /// "Shorter", "More technical", "Plainer": the same Editor session, one more turn, checked again.
    func followUp(_ instruction: String, issue: IssueDraft, in context: ModelContext) async {
        guard let editorSession, !editorSession.isResponding else { return }
        current = .editor
        defer { current = nil }
        let started = Date.now
        let draft = try? await editorSession.respond(to: "\(instruction). Keep the same sections.", generating: IssueTopDraft.self,
                                                     options: ScoutMode.editor.options).content
        let intro = IssueChecker.intro(draft?.intro, editorLine: issue.editorLine)
        record("editor", input: instruction, output: draft.map { "\($0.title)\n\($0.intro)" } ?? "", rejection: intro.flag,
               started: started, subject: "issue", context: context)
        if !intro.text.isEmpty { issue.intro = intro.text }
        if let flag = intro.flag { issue.agentFlags.append(flag) }
        try? context.save()
    }

    private func finish(_ step: Step) {
        finished.insert(step)
    }

    // MARK: Agents

    private func curate(_ cards: [StoryCard], context: ModelContext) async -> [LineupSection] {
        let started = Date.now
        let ids = cards.map(\.id)
        let lanes = Array(Set(cards.map(\.lane))).sorted()
        do {
            // The story IDs and lanes are constrained to the ones given: the Curator can't invent either.
            let section = DynamicGenerationSchema(name: "Section", properties: [
                .init(name: "lane", schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(lanes)])),
                .init(name: "storyIDs", schema: DynamicGenerationSchema(
                    arrayOf: DynamicGenerationSchema(type: String.self, guides: [.anyOf(ids)]),
                    minimumElements: 1, maximumElements: ids.count)),
            ])
            let root = DynamicGenerationSchema(name: "Lineup", properties: [
                .init(name: "sections", schema: DynamicGenerationSchema(arrayOf: section, minimumElements: 1, maximumElements: 4)),
            ])
            let schema = try GenerationSchema(root: root, dependencies: [])
            let response = try await Writer.session(.curator).respond(schema: schema, options: ScoutMode.curator.options) {
                "Arrange these stories into sections."
                for card in cards { card }
            }
            let sections = try response.content.value([GeneratedContent].self, forProperty: "sections").map {
                LineupSection(lane: try $0.value(String.self, forProperty: "lane"),
                              storyIDs: try $0.value([String].self, forProperty: "storyIDs"))
            }
            record("curator", input: ids.joined(separator: ","), output: sections.map { "\($0.lane): \($0.storyIDs.joined(separator: ","))" }
                .joined(separator: "\n"), rejection: nil, started: started, subject: "issue", context: context)
            return sections
        } catch {
            record("curator", input: ids.joined(separator: ","), output: "", rejection: "error: \(error)", started: started,
                   subject: "issue", context: context)
            return []
        }
    }

    /// One Blurber session per story, two at a time.
    private func blurb(_ cards: [StoryCard], context: ModelContext) async -> [String: String] {
        var results: [String: String] = [:]
        var index = 0
        while index < cards.count {
            let first = cards[index]
            let second = index + 1 < cards.count ? cards[index + 1] : nil
            let started = Date.now
            async let firstText = Self.writeBlurb(first)
            async let secondText = Self.writeBlurb(second)
            let done = [(first, await firstText), (second, await secondText)]
            for case let (card?, text) in done {
                results[card.id] = text
                record("blurber", input: card.title, output: text ?? "", rejection: IssueChecker.blurb(text, card: card).flag,
                       started: started, subject: "story:\(card.id)", context: context)
            }
            index += 2
        }
        return results
    }

    private static func writeBlurb(_ card: StoryCard?) async -> String? {
        guard let card else { return nil }
        return try? await Writer.session(.blurber, storyGuid: card.id)
            .respond(generating: BlurbDraft.self, options: ScoutMode.blurber.options) {
                "Why should readers open this story?"
                card
            }.content.text
    }

    private func feature(context: ModelContext) async -> (AuthorDigest, SpotlightDraft)? {
        let shortlist = Verdict.shortlist.rawValue
        let decisions = (try? context.fetch(FetchDescriptor<Decision>(predicate: #Predicate { $0.verdictRaw == shortlist },
                                                                      sortBy: [SortDescriptor(\.score, order: .reverse)]))) ?? []
        // Only real people: a Medium handle or a Hacker News user, never a site filed as an author.
        for decision in decisions where decision.handle != nil || decision.authorKey.hasPrefix("hn:") {
            let key = decision.authorKey
            let posts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.authorKey == key },
                                                                        sortBy: [SortDescriptor(\.published, order: .reverse)]))) ?? []
            guard posts.count >= 2 else { continue }
            let digest = AuthorDigest(authorKey: key, name: decision.authorName, handle: decision.handle,
                                      posts: posts.prefix(6).map { .init(title: $0.title, snippet: $0.snippet) })
            let started = Date.now
            do {
                let draft = try await Writer.session(.spotlight, authorKey: key)
                    .respond(generating: SpotlightDraft.self, options: ScoutMode.spotlight.options) {
                        "Introduce this writer and write three interview questions."
                        digest
                    }.content
                let check = IssueChecker.spotlight(intro: draft.intro, questions: draft.questions, digest: digest)
                record("spotlight", input: decision.authorName, output: ([draft.intro] + draft.questions).joined(separator: "\n"),
                       rejection: check.flag, started: started, subject: "writer:\(key)", context: context)
                return (digest, draft)
            } catch {
                record("spotlight", input: decision.authorName, output: "", rejection: "error: \(error)", started: started,
                       subject: "writer:\(key)", context: context)
                return nil
            }
        }
        return nil
    }

    private func edit(lineup: [LineupSection], blurbs: [String: String], byID: [String: StoryCard], issue: IssueDraft,
                      context: ModelContext, followUp: String?) async -> IssueTopDraft? {
        let outline = lineup.map { section in
            "\(section.lane): " + section.storyIDs.compactMap { id in byID[id].map { "\($0.title) — \(blurbs[id] ?? $0.subtitle)" } }
                .joined(separator: "; ")
        }.joined(separator: "\n")
        let session = Writer.session(.editor)
        editorSession = session
        let started = Date.now
        let input = [issue.title, issue.editorLine].compactMap { $0 }.joined(separator: " · ")
        do {
            let draft = try await Self.draftTop(issueTitle: issue.title, outline: outline, editorLine: issue.editorLine, session: session)
            record("editor", input: input, output: "\(draft.title)\n\(draft.intro)",
                   rejection: IssueChecker.intro(draft.intro, editorLine: issue.editorLine).flag,
                   started: started, subject: "issue", context: context)
            return draft
        } catch {
            record("editor", input: input, output: "", rejection: "error: \(error)", started: started, subject: "issue", context: context)
            return nil
        }
    }

    /// The Editor's prompt. The editor's line sets the angle and tone only; facts still come from the feed outline.
    static func draftTop(issueTitle: String, outline: String, editorLine: String?,
                         session: LanguageModelSession) async throws -> IssueTopDraft {
        let line = editorLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try await session.respond(generating: IssueTopDraft.self, options: ScoutMode.editor.options) {
            "Title and introduce this issue of \(issueTitle)."
            if !line.isEmpty {
                "The editor's angle for this issue: \"\(line)\". Follow its angle and tone; you may use its words. Take every fact from the feed below, not from the angle."
            }
            "<feed>\(outline)</feed>"
        }.content
    }

    private func record(_ role: String, input: String, output: String, rejection: String?, started: Date, subject: String,
                        context: ModelContext) {
        let mode = ScoutMode(rawValue: role) ?? .issueWriting
        context.insert(ModelRun(role: role, pack: Writer.pack.id, instructionsVersion: Writer.instructionsVersion(mode),
                                input: input, subjectID: subject, output: output, rejection: rejection,
                                latency: Date.now.timeIntervalSince(started)))
    }
}

extension IssueDraft {
    /// The issue as plain values for rendering and export; titles, links and authors come from stored data.
    var content: IssueContent {
        let spotlight = spotlightName.map {
            SpotlightBlock(name: $0, handle: spotlightHandle, intro: spotlightIntro, questions: spotlightQuestions)
        }
        return IssueContent(number: number, title: title, intro: intro, entries: orderedEntries.map {
            .init(title: $0.title, url: $0.link, author: $0.authorName, handle: $0.handle, note: $0.note, section: $0.section)
        }, spotlight: spotlight?.questions.isEmpty == false ? spotlight : nil)
    }
}
