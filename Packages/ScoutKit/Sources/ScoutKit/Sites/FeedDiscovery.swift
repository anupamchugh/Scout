//
//  FeedDiscovery.swift
//  ScoutKit
//
//  "Add a site": paste a URL, find its RSS or Atom feeds. Reads <link rel="alternate"> in the page head,
//  follows redirects (URLSession does), and falls back to common feed paths. Read-only, with timeouts.
//

import Foundation

public struct DiscoveredFeed: Sendable, Hashable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let title: String
}

public enum FeedDiscoveryError: Error, Equatable, Sendable {
    case notAWebAddress
    case unreachable(String)
    case noFeeds
}

public enum FeedDiscovery {

    /// Feed links declared in a page's HTML, resolved against `base`, in page order.
    public static func links(inHTML html: String, base: URL) -> [DiscoveredFeed] {
        guard let regex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive) else { return [] }
        var seen = Set<URL>()
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range, in: html) else { return nil }
            let tag = String(html[range])
            let rel = attribute("rel", tag)?.lowercased() ?? ""
            let type = attribute("type", tag)?.lowercased() ?? ""
            guard rel.contains("alternate"), type.contains("rss+xml") || type.contains("atom+xml"),
                  let href = attribute("href", tag), let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  seen.insert(url).inserted else { return nil }
            return DiscoveredFeed(url: url, title: attribute("title", tag).map(HTMLText.decodeEntities) ?? url.host() ?? href)
        }
    }

    /// True when the bytes are an RSS or Atom document.
    public static func isFeed(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        return head.contains("<rss") || head.contains("<feed") || head.contains("<rdf:rdf")
    }

    static let commonPaths = ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml", "/index.xml"]

    /// The feeds for a page or feed address.
    public static func find(_ input: String, session: URLSession = .shared) async throws -> [DiscoveredFeed] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil else {
            throw FeedDiscoveryError.notAWebAddress
        }
        let (data, finalURL) = try await get(url, session: session)
        if isFeed(data) {
            let title = (try? RSSParser.parseDocument(data)).map { _ in finalURL.host() ?? finalURL.absoluteString } ?? finalURL.absoluteString
            return [DiscoveredFeed(url: finalURL, title: title)]
        }
        let declared = links(inHTML: String(decoding: data, as: UTF8.self), base: finalURL)
        if !declared.isEmpty { return declared }
        for path in commonPaths {
            guard let candidate = URL(string: path, relativeTo: finalURL)?.absoluteURL,
                  let (body, resolved) = try? await get(candidate, session: session), isFeed(body) else { continue }
            return [DiscoveredFeed(url: resolved, title: resolved.host() ?? resolved.absoluteString)]
        }
        throw FeedDiscoveryError.noFeeds
    }

    private static func get(_ url: URL, session: URLSession) async throws -> (Data, URL) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/rss+xml, application/atom+xml, text/html;q=0.9", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FeedDiscoveryError.unreachable("The site answered \(http.statusCode).")
            }
            return (data, response.url ?? url)
        } catch let error as FeedDiscoveryError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw FeedDiscoveryError.unreachable("The site didn't answer within 15 seconds.")
        } catch {
            throw FeedDiscoveryError.unreachable("Couldn't reach the site.")
        }
    }

    private static func attribute(_ name: String, _ tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }
}
