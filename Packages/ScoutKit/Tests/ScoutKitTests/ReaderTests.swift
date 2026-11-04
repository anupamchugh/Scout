//
//  ReaderTests.swift
//  ScoutKitTests
//

import Foundation
import Testing
@testable import ScoutKit

struct HTMLToMarkdownTests {

    @Test func mediumPreWithBreaksBecomesFencedCode() {
        let html = #"<p>Try this:</p><pre>let task = Task {<br>  await load()<br>}<br>task.cancel()</pre><p>Done.</p>"#
        #expect(HTMLToMarkdown.convert(html, codeLanguage: "swift") == """
            Try this:

            ```swift
            let task = Task {
              await load()
            }
            task.cancel()
            ```

            Done.

            """)
    }

    @Test func preKeepsSymbolsAndDecodesEntities() {
        let html = "<pre>if a &lt; b &amp;&amp; c { print(\"*x*\") }</pre>"
        #expect(HTMLToMarkdown.convert(html) == "```\nif a < b && c { print(\"*x*\") }\n```\n")
    }

    @Test func headingsEmphasisLinksAndInlineCode() {
        let html = #"<h3>Why it happens</h3><p>Use <strong>structured</strong> <em>concurrency</em> and <code>withTaskGroup</code>, see <a href="https://swift.org/x">the docs</a>.</p>"#
        #expect(HTMLToMarkdown.convert(html) == """
            ### Why it happens

            Use **structured** *concurrency* and `withTaskGroup`, see [the docs](https://swift.org/x).

            """)
    }

    @Test func nestedLists() {
        let html = "<ul><li>Actors<ul><li>isolation</li><li>reentrancy</li></ul></li><li>Tasks</li></ul><ol><li>One</li><li>Two</li></ol>"
        #expect(HTMLToMarkdown.convert(html) == """
            - Actors
              - isolation
              - reentrancy
            - Tasks

            1. One
            2. Two

            """)
    }

    @Test func figureWithCaptionAndQuote() {
        let html = #"<figure><img alt="A diagram" src="https://cdn-images-1.medium.com/max/1024/1*x.png" /><figcaption>The task tree</figcaption></figure><blockquote>Cancellation is cooperative.</blockquote>"#
        #expect(HTMLToMarkdown.convert(html) == """
            ![A diagram](https://cdn-images-1.medium.com/max/1024/1*x.png)

            *The task tree*

            > Cancellation is cooperative.

            """)
    }

    @Test func dropsScriptsAndEscapesMarkdownInText() {
        let html = "<p>Rate *this* [now] <script>alert('x')</script>_ok_</p><iframe src=\"x\">embed</iframe>"
        #expect(HTMLToMarkdown.convert(html) == "Rate \\*this\\* \\[now\\] \\_ok\\_\n")
    }

    @Test func previewsAndLanguages() {
        #expect(HTMLToMarkdown.isPreview("Short preview of a member-only post."))
        #expect(HTMLToMarkdown.codeLanguage(forTags: ["SwiftUI", "design"]) == "swift")
        #expect(HTMLToMarkdown.codeLanguage(forTags: ["python"]) == "")
    }

    /// A real article from the dated salari-dev fixture converts cleanly.
    @Test func realMediumArticleConvertsCleanly() throws {
        let url = try #require(Bundle.module.url(forResource: "salari-dev-2026-11-05", withExtension: "xml", subdirectory: "Fixtures"))
        let items = try RSSParser.parse(Data(contentsOf: url))
        let item = try #require(items.first { $0.contentHTML?.contains("<pre>") == true } ?? items.first)
        let markdown = HTMLToMarkdown.convert(try #require(item.contentHTML), codeLanguage: "swift")
        #expect(!markdown.contains("<p>") && !markdown.contains("<pre") && !markdown.contains("<img"))
        #expect(markdown.contains("![") || markdown.contains("#"))
        #expect(!HTMLToMarkdown.isPreview(markdown))
        if item.contentHTML?.contains("<pre>") == true { #expect(markdown.contains("```swift")) }
    }
}

struct ReaderDocumentTests {

    @Test func articleBecomesBlocks() {
        let markdown = HTMLToMarkdown.convert(#"""
            <h3>Cancel it</h3><p>Use <strong>structured</strong> tasks, see <a href="https://swift.org">docs</a>.</p>
            <figure><img alt="Tree" src="https://x.dev/t.png" /><figcaption>The tree</figcaption></figure>
            <ul><li>Actors<ul><li>isolation</li></ul></li></ul><blockquote>Cooperative.</blockquote>
            <pre>task.cancel()<br>// done</pre>
            """#, codeLanguage: "swift")
        let blocks = ReaderDocument.blocks(markdown)
        #expect(blocks.count == 8)
        #expect(blocks[0] == .heading(level: 3, text: AttributedString("Cancel it")))
        guard case .paragraph(let paragraph) = blocks[1] else { Issue.record("no paragraph"); return }
        #expect(String(paragraph.characters) == "Use structured tasks, see docs.")
        #expect(paragraph.runs.contains { $0.link?.absoluteString == "https://swift.org" })
        #expect(blocks[2] == .image(URL(string: "https://x.dev/t.png")!, alt: "Tree"))
        #expect(blocks[4] == .item(depth: 0, marker: "•", text: AttributedString("Actors")))
        #expect(blocks[5] == .item(depth: 1, marker: "•", text: AttributedString("isolation")))
        #expect(blocks[6] == .quote(AttributedString("Cooperative.")))
        #expect(blocks[7] == .code(language: "swift", code: "task.cancel()\n// done"))
    }
}

struct SwiftTokenizerTests {

    @Test func tokenizesASnippet() {
        let tokens = SwiftTokenizer.tokens(#"@MainActor let task = Task { await load(3) } // "go""#)
        let kinds = tokens.filter { $0.kind != .plain }.map { "\($0.kind.rawValue):\($0.text)" }
        #expect(kinds == ["attribute:@MainActor", "keyword:let", "type:Task", "keyword:await", "number:3", #"comment:// "go""#])
        #expect(tokens.map(\.text).joined() == #"@MainActor let task = Task { await load(3) } // "go""#)
    }

    @Test func stringsAndBlockComments() {
        let tokens = SwiftTokenizer.tokens("let s = \"a \\\" b\" /* note */")
        #expect(tokens.contains { $0.kind == .string && $0.text == "\"a \\\" b\"" })
        #expect(tokens.contains { $0.kind == .comment && $0.text == "/* note */" })
    }
}
