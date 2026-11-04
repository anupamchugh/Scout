//
//  IssueTests.swift
//  ScoutTests
//

import Foundation
import Testing
@testable import Scout

private let issue = IssueContent(number: 12, title: "Swift concurrency", intro: "Actors, task groups and a little SwiftUI.",
                                 entries: [
                                    .init(title: "Actors [without] the fear", url: "https://medium.com/@a/actors-1",
                                          author: "Writer A", handle: "a", note: "A calm tour of isolation."),
                                    .init(title: "Q&A: <Task> groups", url: "https://example.pub/groups?x=1&y=2",
                                          author: "Writer B", handle: nil, note: ""),
                                 ])

struct IssueTests {

    @Test func markdownMatchesSnapshot() {
        #expect(IssueRenderer.markdown(issue) == """
            ## Issue 12: Swift concurrency

            Actors, task groups and a little SwiftUI.

            - [Actors \\[without\\] the fear](https://medium.com/@a/actors-1) by Writer A (@a): A calm tour of isolation.
            - [Q&A: <Task> groups](https://example.pub/groups?x=1&y=2) by Writer B

            """)
    }

    @Test func htmlEscapesTitlesAndLinks() {
        let html = IssueRenderer.html(issue)
        #expect(html.contains("<a href=\"https://example.pub/groups?x=1&amp;y=2\">Q&amp;A: &lt;Task&gt; groups</a>"))
        #expect(html.hasPrefix("<h2>Issue 12: Swift concurrency</h2>"))
        #expect(!html.contains("<Task>"))
    }

    @Test func linksSurviveMarkdownRoundTrip() throws {
        let markdown = IssueRenderer.markdown(issue)
        let parsed = try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let links = parsed.runs.compactMap(\.link).map(\.absoluteString)
        #expect(links == ["https://medium.com/@a/actors-1", "https://example.pub/groups?x=1&y=2"])
    }

    @Test func llmsTxtMatchesSnapshot() {
        #expect(IssueRenderer.llmsTxt(issue) == """
            # Issue 12: Swift concurrency

            > Actors, task groups and a little SwiftUI.

            ## Posts

            - [Actors \\[without\\] the fear](https://medium.com/@a/actors-1): by Writer A (@a). A calm tour of isolation.
            - [Q&A: <Task> groups](https://example.pub/groups?x=1&y=2): by Writer B

            """)
    }

    @Test func shortlistCSVQuotesFields() {
        let rows = [ShortlistRow(name: "Writer, A", handle: "a", lane: "Swift", postTitle: "Say \"hi\"",
                                 postURL: "https://medium.com/@a/x", note: "Line one\nLine two")]
        #expect(ShortlistRenderer.csv(rows) == """
            name,handle,lane,post_title,post_url,note
            "Writer, A",a,Swift,"Say ""hi\"\"",https://medium.com/@a/x,"Line one
            Line two"

            """)
    }

    @Test func shortlistMarkdownGroupsByLane() {
        let rows = [ShortlistRow(name: "B", handle: nil, lane: "Zeta", postTitle: "T2", postURL: "u2", note: ""),
                    ShortlistRow(name: "A", handle: "a", lane: "Alpha", postTitle: "T1", postURL: "u1", note: "")]
        #expect(ShortlistRenderer.markdown(rows) == "# Shortlist\n\n## Alpha\n\n- A (@a): [T1](u1)\n\n## Zeta\n\n- B: [T2](u2)\n")
    }

    @Test func pitchFactsComeFromCode() {
        let facts = PitchFacts(text: "Hi\nWhy actors beat locks in Swift\nI'm @sample_writer, I write about concurrency.")
        #expect(facts.title == "Why actors beat locks in Swift")
        #expect(facts.handle == "sample_writer")
    }
}
