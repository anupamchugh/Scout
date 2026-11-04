//
//  IssueRenderer.swift
//  ScoutKit
//
//  Markdown, HTML and llms.txt built from the same plain model, by string building.
//  Titles, links, names, handles and order come from the data; only notes and the intro may be model-drafted.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public struct IssueContent: Sendable, Hashable {

    public init(number: Int, title: String, intro: String, entries: [Entry]) {

        self.number = number

        self.title = title

        self.intro = intro

        self.entries = entries

    }

    public struct Entry: Sendable, Hashable {

        public init(title: String, url: String, author: String, handle: String?, note: String) {
            self.title = title
            self.url = url
            self.author = author
            self.handle = handle
            self.note = note
        }

        public var title: String
        public var url: String
        public var author: String
        public var handle: String?
        public var note: String
    }

    public var number: Int
    public var title: String
    public var intro: String
    public var entries: [Entry]

    public var heading: String { "Issue \(number): \(title)" }
}

public enum IssueRenderer {

    public static func markdown(_ issue: IssueContent) -> String {
        var lines = ["## \(issue.heading)", ""]
        if !issue.intro.isEmpty { lines += [issue.intro, ""] }
        for entry in issue.entries {
            var line = "- [\(markdownEscape(entry.title))](\(entry.url)) by \(entry.author)"
            if let handle = entry.handle { line += " (@\(handle))" }
            if !entry.note.isEmpty { line += ": \(entry.note)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func html(_ issue: IssueContent) -> String {
        var html = "<h2>\(escape(issue.heading))</h2>\n"
        if !issue.intro.isEmpty { html += "<p>\(escape(issue.intro))</p>\n" }
        html += "<ul>\n"
        for entry in issue.entries {
            html += "<li><a href=\"\(escape(entry.url))\">\(escape(entry.title))</a> by \(escape(entry.author))"
            if let handle = entry.handle { html += " (@\(escape(handle)))" }
            if !entry.note.isEmpty { html += ": \(escape(entry.note))" }
            html += "</li>\n"
        }
        return html + "</ul>\n"
    }

    /// An llms.txt describing the issue: title, a `>` summary, then one link per entry.
    public static func llmsTxt(_ issue: IssueContent) -> String {
        var lines = ["# \(issue.heading)", ""]
        let summary = issue.intro.isEmpty ? "\(issue.entries.count) posts picked for \(issue.title)." : issue.intro
        lines += ["> \(summary.replacingOccurrences(of: "\n", with: " "))", "", "## Posts", ""]
        for entry in issue.entries {
            var line = "- [\(markdownEscape(entry.title))](\(entry.url))"
            let byline = entry.handle.map { "\(entry.author) (@\($0))" } ?? entry.author
            line += ": by \(byline)"
            if !entry.note.isEmpty { line += ". \(entry.note)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Brackets in a title would end the link text early.
    public static func markdownEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}

extension UTType {
    public static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// Shares an issue as Markdown, with HTML as a second representation (pastes into Substack and Medium with links).
public struct IssueExport: Transferable {
    public init(issue: IssueContent) { self.issue = issue }

    public let issue: IssueContent

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .markdown) { Data(IssueRenderer.markdown($0.issue).utf8) }
            .suggestedFileName { "issue-\($0.issue.number).md" }
        DataRepresentation(exportedContentType: .html) { Data(IssueRenderer.html($0.issue).utf8) }
            .suggestedFileName { "issue-\($0.issue.number).html" }
    }
}

public struct IssueLLMsExport: Transferable {

    public init(issue: IssueContent) { self.issue = issue }

    public let issue: IssueContent

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data(IssueRenderer.llmsTxt($0.issue).utf8) }
            .suggestedFileName { _ in "llms.txt" }
    }
}

/// The shortlist as Markdown or CSV.
public struct ShortlistRow: Sendable, Hashable {
    public init(name: String, handle: String?, lane: String, postTitle: String, postURL: String, note: String) {
        self.name = name
        self.handle = handle
        self.lane = lane
        self.postTitle = postTitle
        self.postURL = postURL
        self.note = note
    }

    public var name: String
    public var handle: String?
    public var lane: String
    public var postTitle: String
    public var postURL: String
    public var note: String
}

public enum ShortlistRenderer {
    public static func markdown(_ rows: [ShortlistRow]) -> String {
        var lines = ["# Shortlist", ""]
        for (lane, group) in Dictionary(grouping: rows, by: \.lane).sorted(by: { $0.key < $1.key }) {
            lines += ["## \(lane)", ""]
            for row in group {
                let who = row.handle.map { "\(row.name) (@\($0))" } ?? row.name
                lines.append("- \(who): [\(IssueRenderer.markdownEscape(row.postTitle))](\(row.postURL))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func csv(_ rows: [ShortlistRow]) -> String {
        let header = "name,handle,lane,post_title,post_url,note"
        let body = rows.map { row in
            [row.name, row.handle ?? "", row.lane, row.postTitle, row.postURL, row.note].map(csvField).joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n") + "\n"
    }

    public static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

public struct ShortlistMarkdownExport: Transferable {

    public init(rows: [ShortlistRow]) { self.rows = rows }

    public let rows: [ShortlistRow]
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .markdown) { Data(ShortlistRenderer.markdown($0.rows).utf8) }
            .suggestedFileName { _ in "shortlist.md" }
    }
}

public struct ShortlistCSVExport: Transferable {

    public init(rows: [ShortlistRow]) { self.rows = rows }

    public let rows: [ShortlistRow]
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data(ShortlistRenderer.csv($0.rows).utf8) }
            .suggestedFileName { _ in "shortlist.csv" }
    }
}
