//
//  ScoutIntents.swift
//  Scout
//
//  The intent trio follows SiriCardKit's rules (github.com/krispuckett/SiriCardKit, MIT; see
//  THIRD_PARTY_NOTICES.md): the main intent runs on the phrase and returns the snippet intent; the
//  snippet intent only reads; control intents make the changes and the system redraws the card.
//

import AppIntents
import Foundation
import ScoutKit
import SwiftData

/// What the card shows, saved by the main intent so the snippet intent can stay a pure read.
struct SiriDeckSnapshot: Codable, Sendable, Equatable {
    struct Row: Codable, Sendable, Equatable {
        var authorKey: String
        var name: String
        var handle: String?
        var score: Int
        var postTitle: String
        var postLink: String
        var postGuid: String
    }

    var lane: String
    var total: Int
    var rows: [Row]

    private static let key = "scout.siri.snapshot"

    static func load() -> SiriDeckSnapshot? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SiriDeckSnapshot.self, from: $0) }
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// Code builds the card: the top four writers, ordered by score.
    @MainActor
    static func make(lane: String, deck: [AuthorCandidate]) -> SiriDeckSnapshot {
        SiriDeckSnapshot(lane: lane, total: deck.count, rows: deck.prefix(4).map {
            Row(authorKey: $0.authorKey, name: $0.name, handle: $0.handle, score: $0.score,
                postTitle: $0.bestPost.title, postLink: $0.bestPost.link, postGuid: $0.bestPost.guid)
        })
    }
}

// MARK: Main intents

struct ScoutTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Scout Today's New Writers"
    static let description = IntentDescription("Find today's best-matching writers for a lane and show them on a card.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Lane", default: "Swift concurrency")
    var lane: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let model = ScoutModel(container: ScoutStore.container, usesDemoData: false)
        if model.lanes.contains(where: { $0.name.localizedCaseInsensitiveCompare(lane) == .orderedSame }) {
            model.activeLaneName = model.lanes.first { $0.name.localizedCaseInsensitiveCompare(lane) == .orderedSame }!.name
        }
        await model.loadDeck()
        let snapshot = SiriDeckSnapshot.make(lane: model.activeLaneName, deck: model.deck)
        snapshot.save()
        let spoken = snapshot.rows.first.map { "\(snapshot.total) writers for \(snapshot.lane). Top match: \($0.name)." }
            ?? "No new writers for \(snapshot.lane) right now."
        return .result(dialog: IntentDialog(full: "\(spoken)", supporting: "Today's writers."),
                       snippetIntent: DeckSnippetIntent())
    }
}

struct ShowShortlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Show My Shortlist"
    static let description = IntentDescription("Open the writers you shortlisted.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Navigator.shared.tab = .shortlist
        let shortlist = Verdict.shortlist.rawValue
        let count = (try? ScoutStore.container.mainContext.fetchCount(
            FetchDescriptor<Decision>(predicate: #Predicate { $0.verdictRaw == shortlist }))) ?? 0
        return .result(dialog: "\(count) writers on your shortlist.")
    }
}

// MARK: Snippet intent

struct DeckSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Scout Card"
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        // READ ONLY: the saved snapshot and which of its writers are already decided.
        let snapshot = SiriDeckSnapshot.load() ?? SiriDeckSnapshot(lane: "", total: 0, rows: [])
        let keys = snapshot.rows.map(\.authorKey)
        let decided = Set(((try? ScoutStore.container.mainContext.fetch(
            FetchDescriptor<Decision>(predicate: #Predicate { keys.contains($0.authorKey) }))) ?? [])
            .filter { $0.verdict == .shortlist }.map(\.authorKey))
        return .result(view: ScoutSiriCard(snapshot: snapshot, shortlisted: decided))
    }
}

// MARK: Control intents

struct OpenDeckIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Deck"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.tab = .today
        return .result()
    }
}

struct ShortlistAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Shortlist All"
    static var supportedModes: IntentModes { .background }
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SiriDeckSnapshot.load() else { return .result(dialog: "Nothing to shortlist.") }
        let context = ScoutStore.container.mainContext
        let decided = Set(((try? context.fetch(FetchDescriptor<Decision>())) ?? []).map(\.authorKey))
        var added = 0
        for row in snapshot.rows where !decided.contains(row.authorKey) {
            context.insert(Decision(authorKey: row.authorKey, authorName: row.name, handle: row.handle, lane: snapshot.lane,
                                    verdict: .shortlist, score: row.score, bestPostGuid: row.postGuid,
                                    bestPostTitle: row.postTitle, bestPostLink: row.postLink))
            added += 1
        }
        try? context.save()
        return .result(dialog: added == 1 ? "Shortlisted one writer." : "Shortlisted \(added) writers.")
    }
}

// MARK: Phrases

struct ScoutShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScoutTodayIntent(),
                    phrases: ["Scout today's new writers in \(.applicationName)",
                              "Find new writers in \(.applicationName)"],
                    shortTitle: "Today's Writers", systemImageName: "rectangle.stack")
        AppShortcut(intent: ShowShortlistIntent(),
                    phrases: ["Show my shortlist in \(.applicationName)", "Open my \(.applicationName) shortlist"],
                    shortTitle: "Shortlist", systemImageName: "checkmark.circle")
    }
}
