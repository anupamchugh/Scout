//
//  SitemapPosts.swift
//  ScoutKit
//
//  A publication's recent posts from its public sitemap. Medium publications list every post in one sitemap file
//  per day (`/sitemap/posts/<year>/posts-<date>.xml`), so the last 50 posts are reachable even though the RSS feed
//  holds ten. A sitemap gives each post's link and day only: no writer, tags or text. Titles are rebuilt from the
//  link's slug, which loses capitals and punctuation.
//

import Foundation

public struct SitemapPost: Sendable, Hashable, Codable {
    public var url: URL
    public var day: String
    public var slugTitle: String
}

public enum SitemapPosts {

    /// `<loc>` entries of one day's sitemap.
    public static func parse(_ xml: String, day: String) -> [SitemapPost] {
        guard let regex = try? Regex(#"<loc>([^<]+)</loc>"#) else { return [] }
        return xml.matches(of: regex).compactMap { match -> SitemapPost? in
            guard let text = match.output[1].substring, let url = URL(string: String(text)) else { return nil }
            return SitemapPost(url: url, day: day, slugTitle: title(fromSlug: url.lastPathComponent))
        }
    }

    /// A single-file sitemap (custom-domain publications such as itnext.io): post entries only, dated by `<lastmod>`,
    /// which is the last edit, not the publish day. Tag pages and links without a Medium post id are skipped.
    public static func parseSingle(_ xml: String) -> [SitemapPost] {
        guard let regex = try? Regex(#"<url><loc>([^<]+)</loc><lastmod>([0-9-]{10})"#) else { return [] }
        return xml.matches(of: regex).compactMap { match -> SitemapPost? in
            guard let loc = match.output[1].substring, let day = match.output[2].substring,
                  let url = URL(string: String(loc)), !url.path.hasPrefix("/tagged"),
                  let id = url.lastPathComponent.split(separator: "-").last, id.count >= 8, id.allSatisfy(\.isHexDigit)
            else { return nil }
            return SitemapPost(url: url, day: String(day), slugTitle: title(fromSlug: url.lastPathComponent))
        }
    }

    /// "mac-terminal-commands-i-use-every-day-built-in-c0131ea3da32" → "Mac terminal commands i use every day built in".
    public static func title(fromSlug slug: String) -> String {
        var parts = slug.split(separator: "-").map(String.init)
        if let last = parts.last, last.count >= 8, last.allSatisfy(\.isHexDigit) { parts.removeLast() }
        let text = parts.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// A custom-domain publication's single sitemap (`/sitemap/sitemap.xml`), parsed with `parseSingle`.
    public static func single(host: String, session: URLSession = .shared) async -> [SitemapPost] {
        guard let url = URL(string: "https://\(host)/sitemap/sitemap.xml") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Scout/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8) else { return [] }
        return unique(parseSingle(xml))
    }

    /// One entry per post link, keeping the first (newest day) — a post can appear in more than one day's sitemap.
    public static func unique(_ posts: [SitemapPost]) -> [SitemapPost] {
        var seen = Set<URL>()
        return posts.filter { seen.insert($0.url).inserted }
    }

    /// A date as a sitemap day ("2026-11-06", UTC).
    public static func day(_ date: Date) -> String { dayString(date) }

    static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// The newest `count` posts, walking back one day at a time from `newest` for at most `maxDays` days.
    public static func latest(host: String, count: Int = 50, newest: Date = .now, maxDays: Int = 40,
                              session: URLSession = .shared) async -> [SitemapPost] {
        var posts: [SitemapPost] = []
        for offset in 0..<maxDays where posts.count < count {
            let day = dayString(newest.addingTimeInterval(-Double(offset) * 86_400))
            guard let url = URL(string: "https://\(host)/sitemap/posts/\(day.prefix(4))/posts-\(day).xml") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Scout/1.0", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8) else { continue }
            posts += parse(xml, day: day)
        }
        return Array(unique(posts).prefix(count))
    }
}
