//
//  RSSParserTests.swift
//  ScoutKitTests
//
//  Fixtures follow the shape of Medium's live feeds (checked 2026-11-04); titles and people are made up.
//

import Foundation
import Testing
@testable import ScoutKit

private let tagFeed = """
<?xml version="1.0" encoding="UTF-8"?><rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
<channel><title><![CDATA[Swiftui on Medium]]></title>
<item>
  <title><![CDATA[Sharing logic, keeping the UI native]]></title>
  <description><![CDATA[<div class="medium-feed-item"><p class="medium-feed-image"><a href="https://medium.com/@sample-writer/x"><img src="https://cdn-images-1.medium.com/max/2600/1*abc.png" width="2800"></a></p><p class="medium-feed-snippet">MVI with a pure reducer, and how SwiftUI talks to shared ViewModels &#x2019;today&#x2019; &amp; more.</p><p class="medium-feed-link"><a href="https://medium.com/@sample-writer/x">Continue reading on Medium »</a></p></div>]]></description>
  <link>https://medium.com/@sample-writer/sharing-logic-e6be2e28c9bc?source=rss------swiftui-5</link>
  <guid isPermaLink="false">https://medium.com/p/e6be2e28c9bc</guid>
  <category><![CDATA[swiftui]]></category>
  <category><![CDATA[kotlin-multiplatform]]></category>
  <dc:creator><![CDATA[Sample Writer]]></dc:creator>
  <pubDate>Wed, 04 Nov 2026 13:51:52 GMT</pubDate>
</item>
<item>
  <title><![CDATA[Missing a date is skipped]]></title>
  <link>https://medium.com/@someone/x</link>
  <guid isPermaLink="false">https://medium.com/p/nodate</guid>
</item>
</channel></rss>
"""

private let publicationFeed = """
<?xml version="1.0" encoding="UTF-8"?><rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/" version="2.0">
<channel><title>Sample Pub</title>
<item>
  <title><![CDATA[The build system is where the time goes]]></title>
  <link>https://samplepub.example/the-build-system-e3ccfab15b4c?source=rss----d0b105d10f0a---4</link>
  <guid isPermaLink="false">https://medium.com/p/e3ccfab15b4c</guid>
  <category><![CDATA[gradle]]></category>
  <dc:creator><![CDATA[Another Writer]]></dc:creator>
  <pubDate>Tue, 03 Nov 2026 19:12:05 GMT</pubDate>
  <content:encoded><![CDATA[<h4>Getting three build tools to cooperate took longer.</h4><figure><img alt="" src="https://cdn-images-1.medium.com/max/1024/1*tp.png" /></figure><p>\(Array(repeating: "word", count: 600).joined(separator: " "))</p>]]></content:encoded>
</item>
</channel></rss>
"""

struct RSSParserTests {

    @Test func parsesTagFeedItem() throws {
        let items = try RSSParser.parse(Data(tagFeed.utf8))
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.title == "Sharing logic, keeping the UI native")
        #expect(item.creator == "Sample Writer")
        #expect(item.handle == "sample-writer")
        #expect(item.authorKey == "sample-writer")
        #expect(item.guid == "https://medium.com/p/e6be2e28c9bc")
        #expect(item.categories == ["swiftui", "kotlin-multiplatform"])
        #expect(item.snippet == "MVI with a pure reducer, and how SwiftUI talks to shared ViewModels \u{2019}today\u{2019} & more.")
        #expect(item.canonicalLink.absoluteString == "https://medium.com/@sample-writer/sharing-logic-e6be2e28c9bc")
        #expect(item.imageURL?.absoluteString == "https://cdn-images-1.medium.com/max/2600/1*abc.png")
        #expect(item.wordCount == nil)
        #expect(item.readingMinutes == nil)
        #expect(item.published == Date(timeIntervalSince1970: 1_793_800_312))
    }

    @Test func publicationItemsUseFullTextForSnippetAndReadingTime() throws {
        let item = try #require(try RSSParser.parse(Data(publicationFeed.utf8)).first)
        #expect(item.handle == nil)
        #expect(item.authorKey == "name:Another Writer")
        #expect(item.snippet == "Getting three build tools to cooperate took longer.")
        #expect(item.wordCount == 608)
        #expect(item.readingMinutes == 3)
    }

    @Test func readsAuthorFeedChannelImage() throws {
        let feed = """
        <?xml version="1.0"?><rss version="2.0"><channel><title>Stories by A</title>
        <image><url>https://cdn-images-1.medium.com/fit/c/150/150/1*avatar.jpeg</url><title>Stories by A</title><link>https://medium.com/@a</link></image>
        </channel></rss>
        """
        let document = try RSSParser.parseDocument(Data(feed.utf8))
        #expect(document.channelImage?.absoluteString == "https://cdn-images-1.medium.com/fit/c/150/150/1*avatar.jpeg")
        #expect(document.items.isEmpty)
    }

    @Test func malformedXMLThrows() {
        #expect(throws: RSSParserError.self) { try RSSParser.parse(Data("<rss><channel><item>".utf8)) }
    }

    @Test func decodesEntities() {
        #expect(HTMLText.decodeEntities("a &amp; b &#x2019;c&#8217; &lt;d&gt; &bogus; &") == "a & b \u{2019}c\u{2019} <d> &bogus; &")
    }

    @Test func feedURLs() {
        #expect(FeedSource.tag("swiftui").url.absoluteString == "https://medium.com/feed/tag/swiftui")
        #expect(FeedSource.author("bosankus").url.absoluteString == "https://medium.com/feed/@bosankus")
        #expect(FeedSource.publication("better-programming").url.absoluteString == "https://medium.com/feed/better-programming")
    }
}
