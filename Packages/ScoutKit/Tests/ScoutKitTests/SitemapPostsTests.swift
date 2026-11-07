//
//  SitemapPostsTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct SitemapPostsTests {
    @Test func parsesLocEntriesAndRebuildsTitles() {
        let xml = """
            <urlset><url><loc>https://levelup.gitconnected.com/mac-terminal-commands-i-use-every-day-built-in-c0131ea3da32</loc>\
            <lastmod>2026-11-06</lastmod></url><url><loc>https://levelup.gitconnected.com/your-mcp-setup-is-becoming-technical-debt-3917e39f9d9c</loc></url></urlset>
            """
        let posts = SitemapPosts.parse(xml, day: "2026-11-06")
        #expect(posts.count == 2)
        #expect(posts[0].slugTitle == "Mac terminal commands i use every day built in")
        #expect(posts[1].slugTitle == "Your mcp setup is becoming technical debt")
        #expect(posts.allSatisfy { $0.day == "2026-11-06" })
    }

    @Test func keepsSlugsWithoutAnIdSuffix() {
        #expect(SitemapPosts.title(fromSlug: "hello-world") == "Hello world")
    }

    @Test func topicCountsAreMostFirstAndSkipUnlabelled() {
        let counts = PostTopicLabeler.counts([.aiAndLLMs, .mobile, .aiAndLLMs, nil])
        #expect(counts.map(\.topic) == [.aiAndLLMs, .mobile])
        #expect(counts.map(\.count) == [2, 1])
    }
}
