//
//  RolePack.swift
//  ScoutKit
//
//  A role pack says what to read, how to rank it and what to make, for one kind of scout.
//  It is plain data: shareable as a .scoutpack JSON file and importable.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public struct RolePack: Codable, Identifiable, Hashable, Sendable {
    public enum CardField: String, Codable, Sendable, CaseIterable {
        case avatar, bestPost, stats, tags, why, image
    }

    public enum Signal: String, Codable, Sendable, CaseIterable {
        /// On-device text embeddings against the lane theme.
        case semantic
        case tagOverlap
        case postsPerWeek
        case recency
        /// Vision feature-print distance to images you swiped right on.
        case imageSimilarity
    }

    public enum Output: String, Codable, Sendable {
        case newsletterMarkdown
        case markdownAndHTML
        case moodboard
    }

    public struct PackLane: Codable, Hashable, Sendable {
        public var name: String
        /// Medium tag slugs, or full feed URLs for any other RSS or Atom feed.
        public var sources: [String]
        public var theme: String
    }

    public var id: String
    public var name: String
    /// What the pack covers, including what it can't (platforms without public feeds).
    public var summary: String
    public var lanes: [PackLane]
    public var cardFields: [CardField]
    public var signals: [Signal]
    public var output: Output
    /// How outreach notes should sound, passed to the model as an instruction.
    public var outreachStyle: String

    public var isVisual: Bool { signals.contains(.imageSimilarity) }
}

extension RolePack {
    public static let engineering = RolePack(
        id: "engineering-editor",
        name: "Engineering editor",
        summary: "Medium tag feeds, Hacker News and GitHub releases. Ranks by topic overlap, posts per week and recency. Makes a Markdown newsletter.",
        lanes: [
            PackLane(name: "Swift and SwiftUI", sources: ["swift", "swiftui", "swift-programming"],
                     theme: "Swift language features and SwiftUI views, layout and state"),
            PackLane(name: "Swift concurrency", sources: ["concurrency", "swift-concurrency", "async-await"],
                     theme: "Swift concurrency, async await, actors, task groups and data-race safety"),
            PackLane(name: "iOS architecture", sources: ["ios-development", "ios", "software-architecture", "mobile-app-development"],
                     theme: "iOS app architecture, state ownership, modularisation and testing"),
            PackLane(name: "AI and LLMs", sources: ["artificial-intelligence", "llm", "large-language-models", "machine-learning"],
                     theme: "Language models, AI tools for developers and on-device machine learning"),
            PackLane(name: "Apple Foundation Models", sources: ["apple-intelligence", "foundation-models"],
                     theme: "Apple's on-device Foundation Models framework: guided generation, tools and Apple Intelligence features"),
            PackLane(name: "Level Up Coding", sources: ["https://medium.com/feed/gitconnected"],
                     theme: "Practical programming: software architecture, AI engineering and language craft"),
            PackLane(name: "Careers and interviews", sources: ["careers", "ios-interview-question", "job-interview", "interview"],
                     theme: "Engineering careers, interviews and growing as a developer"),
            PackLane(name: "Coffee Bytes", sources: ["software-engineering", "programming", "web-development"],
                     theme: "Practical software engineering, developer tools and lessons from shipping code"),
            PackLane(name: "Hacker News", sources: ["https://news.ycombinator.com/rss"],
                     theme: "What programmers are reading and discussing today"),
            PackLane(name: "Show HN builders", sources: ["https://news.ycombinator.com/showrss"],
                     theme: "Builders showing projects they made: tools, apps and libraries"),
            PackLane(name: "Swift releases", sources: ["https://github.com/swiftlang/swift/releases.atom"],
                     theme: "Swift toolchain releases and snapshots"),
            PackLane(name: "Apple developer news", sources: ["https://developer.apple.com/news/rss/news.rss"],
                     theme: "Apple platform announcements, betas and App Store changes for developers"),
        ],
        cardFields: [.avatar, .bestPost, .stats, .tags, .why],
        signals: [.semantic, .tagOverlap, .postsPerWeek, .recency],
        output: .newsletterMarkdown,
        outreachStyle: "Direct and technical. Name the specific idea from their post you'd like them to expand on.")

    public static let techWriter = RolePack(
        id: "tech-writer",
        name: "Tech writer / newsletter",
        summary: "Medium publication and author feeds plus Substack newsletters. Makes Markdown and HTML for Substack or Medium.",
        lanes: [
            PackLane(name: "Better Programming", sources: ["https://medium.com/feed/better-programming"],
                     theme: "Advice for programmers: craft, careers and tools"),
            PackLane(name: "Engineering newsletters", sources: ["https://newsletter.pragmaticengineer.com/feed"],
                     theme: "How engineering teams work, hire and ship"),
            PackLane(name: "Writing about code", sources: ["programming", "technology", "software-development"],
                     theme: "Clear explanations of programming ideas for a broad audience"),
        ],
        cardFields: [.avatar, .bestPost, .stats, .tags, .why],
        signals: [.semantic, .tagOverlap, .postsPerWeek, .recency],
        output: .markdownAndHTML,
        outreachStyle: "Warm and brief. Mention what their writing does well for readers, then the invitation.")

    public static let illustrator = RolePack(
        id: "illustrator",
        name: "Illustrator / painter",
        summary: "Art blogs with open RSS (Colossal, Muddy Colors, Hyperallergic). Add YouTube channels by channel ID, Substack or Are.na feeds. Ranks by how close images are to ones you liked. Instagram and Behance have no public feeds, so Scout can't read them.",
        lanes: [
            PackLane(name: "Contemporary art", sources: ["https://www.thisiscolossal.com/feed/", "https://hyperallergic.com/feed/"],
                     theme: "Contemporary art, sculpture, painting and installation"),
            PackLane(name: "Illustration", sources: ["https://www.muddycolors.com/feed/"],
                     theme: "Illustration, concept art and painting technique"),
        ],
        cardFields: [.image, .bestPost, .tags, .why],
        signals: [.imageSimilarity, .tagOverlap, .recency],
        output: .moodboard,
        outreachStyle: "Respectful and specific about the work itself. Never comment on the artist as a person.")

    public static let builtIns: [RolePack] = [.engineering, .techWriter, .illustrator]
}

extension UTType {
    public static let scoutPack = UTType(exportedAs: "com.anupamchugh.scout.pack", conformingTo: .json)
}

extension RolePack: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .scoutPack)
            .suggestedFileName { "\($0.id).scoutpack" }
    }
}

public enum PackStore {
    private static let activeKey = "scout.activePack"
    private static let importedKey = "scout.importedPacks"

    /// Nil until the person picks a pack at onboarding.
    public static var activeID: String? {
        get { UserDefaults.standard.string(forKey: activeKey) }
        set { UserDefaults.standard.set(newValue, forKey: activeKey) }
    }

    public static var imported: [RolePack] {
        get {
            UserDefaults.standard.data(forKey: importedKey).flatMap { try? JSONDecoder().decode([RolePack].self, from: $0) } ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: importedKey) }
    }

    public static var all: [RolePack] { RolePack.builtIns + imported.filter { pack in !RolePack.builtIns.contains { $0.id == pack.id } } }

    public static func pack(id: String?) -> RolePack {
        all.first { $0.id == id } ?? .engineering
    }

    /// Reads a .scoutpack file; an imported pack with a built-in's id replaces nothing and is renamed.
    public static func importPack(from url: URL) throws -> RolePack {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        var pack = try JSONDecoder().decode(RolePack.self, from: Data(contentsOf: url))
        if RolePack.builtIns.contains(where: { $0.id == pack.id }) { pack.id += "-imported" }
        imported = imported.filter { $0.id != pack.id } + [pack]
        return pack
    }
}
