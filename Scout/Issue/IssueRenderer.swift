//
//  IssueRenderer.swift
//  Scout
//
//  Markdown, HTML and llms.txt built from the same plain model, by string building.
//  Titles, links, names, handles and order come from the data; only notes and the intro may be model-drafted.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct IssueContent: Sendable, Hashable {
    struct Entry: Sendable, Hashable {
        var title: String
        var url: String
        var author: String
        var handle: String?
        var note: String
    }

    var number: Int
    var title: String
    var intro: String
    var entries: [Entry]

    var heading: String { "Issue \(number): \(title)" }
}

enum IssueRenderer {

    static func markdown(_ issue: IssueContent) -> String {
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

    static func html(_ issue: IssueContent) -> String {
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
    static func llmsTxt(_ issue: IssueContent) -> String {
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

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Brackets in a title would end the link text early.
    static func markdownEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// Shares an issue as Markdown, with HTML as a second representation (pastes into Substack and Medium with links).
struct IssueExport: Transferable {
    let issue: IssueContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .markdown) { Data(IssueRenderer.markdown($0.issue).utf8) }
            .suggestedFileName { "issue-\($0.issue.number).md" }
        DataRepresentation(exportedContentType: .html) { Data(IssueRenderer.html($0.issue).utf8) }
            .suggestedFileName { "issue-\($0.issue.number).html" }
    }
}

struct IssueLLMsExport: Transferable {
    let issue: IssueContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data(IssueRenderer.llmsTxt($0.issue).utf8) }
            .suggestedFileName { _ in "llms.txt" }
    }
}

/// The shortlist as Markdown or CSV.
struct ShortlistRow: Sendable, Hashable {
    var name: String
    var handle: String?
    var lane: String
    var postTitle: String
    var postURL: String
    var note: String
}

enum ShortlistRenderer {
    static func markdown(_ rows: [ShortlistRow]) -> String {
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

    static func csv(_ rows: [ShortlistRow]) -> String {
        let header = "name,handle,lane,post_title,post_url,note"
        let body = rows.map { row in
            [row.name, row.handle ?? "", row.lane, row.postTitle, row.postURL, row.note].map(csvField).joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n") + "\n"
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct ShortlistMarkdownExport: Transferable {
    let rows: [ShortlistRow]
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .markdown) { Data(ShortlistRenderer.markdown($0.rows).utf8) }
            .suggestedFileName { _ in "shortlist.md" }
    }
}

struct ShortlistCSVExport: Transferable {
    let rows: [ShortlistRow]
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data(ShortlistRenderer.csv($0.rows).utf8) }
            .suggestedFileName { _ in "shortlist.csv" }
    }
}
