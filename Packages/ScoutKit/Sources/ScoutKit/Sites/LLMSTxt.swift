//
//  LLMSTxt.swift
//  ScoutKit
//
//  A writer's site can describe itself in /llms.txt: a "# Title", a "> summary" line, then "## Section"
//  headings with "- [name](url): note" links. Scout shows the summary on cards, passes the summary and
//  section titles to the "why" line as the writer's own words, and uses section titles as a match signal.
//

import Foundation

public struct LLMSTxtDocument: Sendable, Equatable {
    public struct Link: Sendable, Equatable {
        public let name: String
        public let url: String
        public let note: String
    }

    public struct Section: Sendable, Equatable {
        public let title: String
        public let links: [Link]
    }

    public let title: String
    public let summary: String
    public let sections: [Section]

    public var sectionTitles: [String] { sections.map(\.title) }
}

public enum LLMSTxt {
    /// Nil when the text isn't an llms.txt (no "# " title), so an HTML error page served with 200 is ignored.
    public static func parse(_ text: String) -> LLMSTxtDocument? {
        var title: String?
        var summary = ""
        var sections: [LLMSTxtDocument.Section] = []
        var currentTitle: String?
        var links: [LLMSTxtDocument.Link] = []

        func close() {
            if let currentTitle { sections.append(.init(title: currentTitle, links: links)) }
            links = []
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") && title == nil {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix(">") && summary.isEmpty && currentTitle == nil {
                summary = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("## ") {
                close()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- ["), let link = link(line) {
                links.append(link)
            }
        }
        close()
        guard let title, !title.isEmpty, !text.lowercased().contains("<html") else { return nil }
        return LLMSTxtDocument(title: title, summary: summary, sections: sections)
    }

    private static func link(_ line: String) -> LLMSTxtDocument.Link? {
        guard let regex = try? NSRegularExpression(pattern: #"^- \[([^\]]+)\]\(([^)]+)\)(?::\s*(.*))?$"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let name = Range(match.range(at: 1), in: line), let url = Range(match.range(at: 2), in: line) else { return nil }
        let note = Range(match.range(at: 3), in: line).map { String(line[$0]) } ?? ""
        return .init(name: String(line[name]), url: String(line[url]), note: note)
    }

    /// Domains worth asking for /llms.txt: a writer's own site, not a platform many people post on.
    public static func isPersonalDomain(_ host: String) -> Bool {
        let platforms = ["medium.com", "news.ycombinator.com", "github.com", "youtube.com", "twitter.com", "x.com", "substack.com",
                         "linkedin.com", "reddit.com", "dev.to", "hashnode.com", "google.com", "apple.com"]
        let bare = host.lowercased().replacingOccurrences(of: "www.", with: "")
        return !platforms.contains { bare == $0 || bare.hasSuffix("." + $0) }
    }

    /// Share of the lane's words that appear in the site's section titles, 0...1: a small match signal, in code.
    public static func laneOverlap(sectionTitles: [String], lane: LaneSpec) -> Double {
        let laneWords = Set((lane.tags.joined(separator: " ") + " " + lane.theme).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 })
        let siteWords = Set(sectionTitles.joined(separator: " ").lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 })
        guard !laneWords.isEmpty, !siteWords.isEmpty else { return 0 }
        return min(1, Double(laneWords.intersection(siteWords).count) / 3)
    }
}
