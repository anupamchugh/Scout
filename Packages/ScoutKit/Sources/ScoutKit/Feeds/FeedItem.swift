//
//  FeedItem.swift
//  ScoutKit
//

import Foundation

/// A Medium RSS feed. Each returns Medium's latest 10 stories.
public enum FeedSource: Sendable, Hashable {
    case tag(String)
    case author(String)
    case publication(String)
    /// Any RSS or Atom feed: Hacker News, a blog, Substack, GitHub releases, a YouTube channel.
    case feed(URL)

    public var url: URL {
        switch self {
        case .tag(let slug): URL(string: "https://medium.com/feed/tag/\(slug)")!
        case .author(let handle): URL(string: "https://medium.com/feed/@\(handle)")!
        case .publication(let slug): URL(string: "https://medium.com/feed/\(slug)")!
        case .feed(let url): url
        }
    }

    /// The key lanes use for this source: a Medium tag slug, or the feed URL for any other feed.
    public var laneKey: String? {
        switch self {
        case .tag(let slug): slug
        case .feed(let url): url.absoluteString
        case .author, .publication: nil
        }
    }

    /// A lane key back to its feed: URLs are feeds, anything else is a Medium tag.
    public init(laneKey: String) {
        if laneKey.hasPrefix("http"), let url = URL(string: laneKey) { self = .feed(url) } else { self = .tag(laneKey) }
    }

    /// How a lane key reads on screen: a tag as is, a feed by its host.
    public static func displayName(_ laneKey: String) -> String {
        laneKey.hasPrefix("http") ? (URL(string: laneKey)?.host() ?? laneKey).replacingOccurrences(of: "www.", with: "") : laneKey
    }

    /// The watched tag this feed belongs to, if it is a tag feed.
    public var tag: String? {
        if case .tag(let slug) = self { slug } else { nil }
    }

    public var label: String {
        switch self {
        case .tag(let slug): "#\(slug)"
        case .author(let handle): "@\(handle)"
        case .publication(let slug): slug
        case .feed(let url): url.host() ?? url.absoluteString
        }
    }
}

/// One item from a Medium RSS feed, holding only what the feed states.
public struct FeedItem: Sendable, Hashable {
    public init(guid: String, title: String, link: URL, creator: String, published: Date, categories: [String],
                snippet: String, wordCount: Int? = nil, imageURL: URL? = nil) {
        self.guid = guid
        self.title = title
        self.link = link
        self.creator = creator
        self.published = published
        self.categories = categories
        self.snippet = snippet
        self.wordCount = wordCount
        self.imageURL = imageURL
    }

    public var guid: String
    public var title: String
    public var link: URL
    public var creator: String
    public var published: Date
    public var categories: [String]
    public var snippet: String
    /// Words in `content:encoded`. Tag feeds carry only a snippet, so this is nil there.
    public var wordCount: Int?
    public var imageURL: URL?

    /// The `@handle` in the post link. Posts on a publication's custom domain have none.
    public var handle: String? {
        link.pathComponents.first { $0.hasPrefix("@") && $0.count > 1 }.map { String($0.dropFirst()) }
    }

    public var authorKey: String { handle ?? "name:\(creator)" }

    /// The link without Medium's `?source=` tracking query.
    public var canonicalLink: URL {
        var parts = URLComponents(url: link, resolvingAgainstBaseURL: false)
        parts?.query = nil
        return parts?.url ?? link
    }

    /// Reading time from the full text at Medium's 265 words a minute; nil without full text.
    public var readingMinutes: Int? {
        wordCount.map { max(1, Int((Double($0) / 265).rounded(.up))) }
    }
}

public struct FeedDocument: Sendable, Hashable {

    public init(channelImage: URL?, items: [FeedItem]) {

        self.channelImage = channelImage

        self.items = items

    }

    public var channelImage: URL?
    public var items: [FeedItem]
}
