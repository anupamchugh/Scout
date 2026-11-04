//
//  ScoutProfile.swift
//  Scout
//
//  One DynamicProfile for every model request. Its body switches on the active role pack and the mode,
//  so each branch carries its own instructions, tools and sampling. Code picks the branch; the model
//  never chooses its own role.
//

import Foundation
import FoundationModels
import Observation
import ScoutKit
import SwiftData

enum ScoutMode: String, Sendable, CaseIterable {
    /// The "why" line on a card.
    case scouting
    /// Issue intro, entry notes and outreach notes.
    case issueWriting
    /// Summarising an imported pitch.
    case pitchReading
    /// The Ask sheet: the editor's own questions about a writer or story.
    case asking

    /// Low temperature where the text must stay close to the feed; a little more room for prose.
    var options: GenerationOptions {
        switch self {
        case .scouting, .pitchReading: GenerationOptions(temperature: 0.3)
        case .asking: GenerationOptions(temperature: 0.4)
        case .issueWriting: GenerationOptions(temperature: 0.6)
        }
    }
}

/// Tool calls from every session, newest first, for the debug panel in Settings.
@MainActor
@Observable
final class ToolCallLog {
    static let shared = ToolCallLog()

    struct Entry: Identifiable {
        let id = UUID()
        let tool: String
        let mode: ScoutMode
        let pack: String
        let at: Date
    }

    private(set) var entries: [Entry] = []

    func record(tool: String, mode: ScoutMode, pack: String) {
        entries.insert(Entry(tool: tool, mode: mode, pack: pack, at: .now), at: 0)
        if entries.count > 50 { entries.removeLast(entries.count - 50) }
    }
}

struct ScoutProfile: LanguageModelSession.DynamicProfile {
    let pack: RolePack
    let mode: ScoutMode
    let container: ModelContainer
    /// The writer a scouting or asking request is about, for the recent-posts tool.
    var authorKey: String?
    /// The story an asking request is about, for the snippet tool.
    var storyGuid: String?

    static let historyLimit = 4

    var body: some LanguageModelSession.DynamicProfile {
        let packName = pack.name
        let mode = mode
        LanguageModelSession.Profile {
            Instructions(Writer.instructions)
            Instructions(Self.roleInstructions(pack: pack, mode: mode))
            if mode == .scouting && !pack.isVisual, let authorKey {
                RecentPostsTool(authorKey: authorKey, container: container)
            }
            if mode == .scouting && pack.isVisual {
                ImageNotesTool(container: container)
            }
            if mode == .asking {
                if let authorKey { RecentPostsTool(authorKey: authorKey, container: container) }
                if let storyGuid { StorySnippetTool(guid: storyGuid, container: container) }
                SearchSavedTool(container: container)
            }
        }
        .onToolCall { call in
            let name = call.toolName
            await MainActor.run { ToolCallLog.shared.record(tool: name, mode: mode, pack: packName) }
        }
        .historyTransform { Self.shortHistory($0) }
    }

    static func roleInstructions(pack: RolePack, mode: ScoutMode) -> String {
        switch (mode, pack.isVisual) {
        case (.scouting, false):
            "You are scouting writers for the \(pack.name) role. Judge only the topics and ideas in the feed text. You may call recentPosts to read the writer's other stored post titles."
        case (.scouting, true):
            "You are scouting artists for the \(pack.name) role. You cannot see images. Describe the work only through the words in the feed: titles, captions and image notes from imageNotes. Never describe the artist as a person or their appearance."
        case (.issueWriting, false):
            "You are drafting newsletter text for the \(pack.name) role. \(pack.outreachStyle)"
        case (.issueWriting, true):
            "You are drafting a moodboard caption for the \(pack.name) role. Speak about the works, not the people. \(pack.outreachStyle)"
        case (.pitchReading, _):
            "You are reading a pitch sent to the \(pack.name) role. Summarise only what the pitch proposes."
        case (.asking, _):
            "Answer the editor's question for the \(pack.name) role in at most three plain sentences, using only the feed text in the prompt and what recentPosts, storySnippet and searchSaved return. If that data can't answer the question, say what is missing instead of guessing."
        }
    }

    /// Instructions plus the last few entries, starting on a prompt so a question keeps its answer.
    static func shortHistory(_ entries: [Transcript.Entry]) -> [Transcript.Entry] {
        let instructions = entries.filter { if case .instructions = $0 { true } else { false } }
        var recent = Array(entries.filter { if case .instructions = $0 { false } else { true } }.suffix(historyLimit))
        while let first = recent.first, !{ if case .prompt = first { true } else { false } }() {
            recent.removeFirst()
        }
        return instructions + recent
    }
}

/// Reads a writer's stored posts from SwiftData so the model describes only what the app recorded.
struct RecentPostsTool: Tool {
    let name = "recentPosts"
    let description = "Lists this writer's stored posts, newest first, each with its title and tags."
    let authorKey: String
    let container: ModelContainer

    @Generable
    struct Arguments {
        @Guide(description: "Always true; the list covers this writer's stored posts")
        var all: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let key = authorKey
        let posts = try ModelContext(container).fetch(FetchDescriptor<StoredPost>(
            predicate: #Predicate { $0.authorKey == key }, sortBy: [SortDescriptor(\.published, order: .reverse)]))
        guard !posts.isEmpty else { return "No stored posts for this writer." }
        return posts.prefix(8).map { "<feed>\($0.title) (tags: \($0.categories.joined(separator: ", ")))</feed>" }
            .joined(separator: "\n")
    }
}

/// For visual packs: the words a feed attaches to an image (title and snippet), never the pixels.
struct ImageNotesTool: Tool {
    let name = "imageNotes"
    let description = "Returns the feed's own title and caption text for a stored post's image."
    let container: ModelContainer

    @Generable
    struct Arguments {
        @Guide(description: "The post title exactly as given in the prompt")
        var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title
        let post = try ModelContext(container).fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.title == title })).first
        guard let post else { return "No stored post with that title." }
        return "<feed>\(post.title). \(post.snippet)</feed>"
    }
}

/// The full feed text of the story an Ask request is about.
struct StorySnippetTool: Tool {
    let name = "storySnippet"
    let description = "Returns this story's title, tags and the text its feed carries."
    let guid: String
    let container: ModelContainer

    @Generable
    struct Arguments {
        @Guide(description: "Always true; returns the current story")
        var current: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let id = guid
        guard let post = try ModelContext(container).fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.guid == id })).first
        else { return "The story isn't stored." }
        return "<feed>\(post.title). Tags: \(post.categories.joined(separator: ", ")). \(post.snippet)</feed>"
    }
}

/// Searches stored posts and the shortlist by words in titles, writers and tags.
struct SearchSavedTool: Tool {
    let name = "searchSaved"
    let description = "Finds stored posts whose title, writer or tags contain a word, newest first, at most six."
    let container: ModelContainer

    @Generable
    struct Arguments {
        @Guide(description: "One word or short phrase to look for")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query.lowercased()
        let posts = try ModelContext(container).fetch(FetchDescriptor<StoredPost>(sortBy: [SortDescriptor(\.published, order: .reverse)]))
        let hits = posts.filter {
            $0.title.lowercased().contains(query) || $0.authorName.lowercased().contains(query)
                || $0.categories.contains { $0.lowercased().contains(query) }
        }.prefix(6)
        guard !hits.isEmpty else { return "Nothing stored matches \"\(arguments.query)\"." }
        return hits.map { "<feed>\($0.title), by \($0.authorName)</feed>" }.joined(separator: "\n")
    }
}
