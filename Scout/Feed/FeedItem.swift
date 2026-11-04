//
//  FeedItem.swift
//  Scout
//

import Foundation

/// A Medium RSS feed. Each returns Medium's latest 10 stories.
enum FeedSource: Sendable, Hashable {
    case tag(String)
    case author(String)
    case publication(String)
    /// Any RSS or Atom feed: Hacker News, a blog, Substack, GitHub releases, a YouTube channel.
    case feed(URL)

    var url: URL {
        switch self {
        case .tag(let slug): URL(string: "https://medium.com/feed/tag/\(slug)")!
        case .author(let handle): URL(string: "https://medium.com/feed/@\(handle)")!
        case .publication(let slug): URL(string: "https://medium.com/feed/\(slug)")!
        case .feed(let url): url
        }
    }

    /// The key lanes use for this source: a Medium tag slug, or the feed URL for any other feed.
    var laneKey: String? {
        switch self {
        case .tag(let slug): slug
        case .feed(let url): url.absoluteString
        case .author, .publication: nil
        }
    }

    /// A lane key back to its feed: URLs are feeds, anything else is a Medium tag.
    init(laneKey: String) {
        if laneKey.hasPrefix("http"), let url = URL(string: laneKey) { self = .feed(url) } else { self = .tag(laneKey) }
    }

    /// How a lane key reads on screen: a tag as is, a feed by its host.
    static func displayName(_ laneKey: String) -> String {
        laneKey.hasPrefix("http") ? (URL(string: laneKey)?.host() ?? laneKey).replacingOccurrences(of: "www.", with: "") : laneKey
    }

    /// The watched tag this feed belongs to, if it is a tag feed.
    var tag: String? {
        if case .tag(let slug) = self { slug } else { nil }
    }

    var label: String {
        switch self {
        case .tag(let slug): "#\(slug)"
        case .author(let handle): "@\(handle)"
        case .publication(let slug): slug
        case .feed(let url): url.host() ?? url.absoluteString
        }
    }
}

/// One item from a Medium RSS feed, holding only what the feed states.
struct FeedItem: Sendable, Hashable {
    var guid: String
    var title: String
    var link: URL
    var creator: String
    var published: Date
    var categories: [String]
    var snippet: String
    /// Words in `content:encoded`. Tag feeds carry only a snippet, so this is nil there.
    var wordCount: Int?
    var imageURL: URL?

    /// The `@handle` in the post link. Posts on a publication's custom domain have none.
    var handle: String? {
        link.pathComponents.first { $0.hasPrefix("@") && $0.count > 1 }.map { String($0.dropFirst()) }
    }

    var authorKey: String { handle ?? "name:\(creator)" }

    /// The link without Medium's `?source=` tracking query.
    var canonicalLink: URL {
        var parts = URLComponents(url: link, resolvingAgainstBaseURL: false)
        parts?.query = nil
        return parts?.url ?? link
    }

    /// Reading time from the full text at Medium's 265 words a minute; nil without full text.
    var readingMinutes: Int? {
        wordCount.map { max(1, Int((Double($0) / 265).rounded(.up))) }
    }
}

struct FeedDocument: Sendable, Hashable {
    var channelImage: URL?
    var items: [FeedItem]
}
