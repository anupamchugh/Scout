//
//  RSSParser.swift
//  ScoutKit
//

import Foundation

public enum RSSParserError: Error, Equatable {
    case malformed(String)
}

/// Parses RSS 2.0 (Medium, Hacker News, blogs, Substack) and Atom (GitHub releases, YouTube) with one `XMLParser`.
public final class RSSParser: NSObject, XMLParserDelegate {

    public static func parse(_ data: Data) throws -> [FeedItem] {
        try parseDocument(data).items
    }

    /// Items plus the channel's image, which on an author feed is the writer's avatar.
    public static func parseDocument(_ data: Data) throws -> FeedDocument {
        let delegate = RSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw RSSParserError.malformed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return FeedDocument(channelImage: delegate.channelImage, items: delegate.items)
    }

    private var items: [FeedItem] = []
    private var channelImage: URL?
    private var inChannelImage = false
    private var fields: [String: String] = [:]
    private var categories: [String] = []
    private var text = ""
    private var inItem = false

    /// RFC 822 dates, with a zone name ("GMT", Medium) or an offset ("+0000", Hacker News).
    private let rfc822: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z"].map {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = $0
        return formatter
    }

    private func date(_ fields: [String: String]) -> Date? {
        if let text = fields["pubDate"] {
            return rfc822.lazy.compactMap { $0.date(from: text) }.first
        }
        guard let text = fields["published"] ?? fields["updated"] else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "image" && !inItem {
            inChannelImage = true
        }
        if elementName == "item" || elementName == "entry" {
            inItem = true
            fields = [:]
            categories = []
        }
        if inItem {
            // Atom keeps its link, categories and thumbnails in attributes.
            switch elementName {
            case "link" where attributeDict["href"] != nil:
                let rel = attributeDict["rel"] ?? "alternate"
                if rel == "alternate" && fields["link"] == nil { fields["link"] = attributeDict["href"] }
            case "category":
                if let term = attributeDict["term"], !term.isEmpty { categories.append(term) }
            case "media:thumbnail", "media:content":
                if fields["media"] == nil, let url = attributeDict["url"] { fields["media"] = url }
            case "enclosure":
                if fields["media"] == nil, attributeDict["type"]?.hasPrefix("image") == true, let url = attributeDict["url"] {
                    fields["media"] = url
                }
            default:
                break
            }
        }
        text = ""
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if inChannelImage {
            if elementName == "url" { channelImage = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if elementName == "image" { inChannelImage = false }
            text = ""
            return
        }
        guard inItem else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "item", "entry":
            inItem = false
            if let item = makeItem() { items.append(item) }
        case "category":
            if !value.isEmpty { categories.append(value) }
        case "name":
            if fields["dc:creator"] == nil, !value.isEmpty { fields["dc:creator"] = value }
        default:
            // An attribute-only element (Atom's <link href>) must not wipe the value read from its attributes.
            if !value.isEmpty || fields[elementName] == nil { fields[elementName] = value }
        }
        text = ""
    }

    private func makeItem() -> FeedItem? {
        guard let title = fields["title"].map(HTMLText.decodeEntities), !title.isEmpty,
              let link = fields["link"].flatMap(URL.init(string:)),
              let published = date(fields)
        else { return nil }
        // Hacker News items have no guid; their comments URL is unique.
        let guid = [fields["guid"], fields["id"], fields["comments"], fields["link"]].compactMap { $0 }.first { !$0.isEmpty }!

        let description = fields["description"] ?? fields["summary"] ?? ""
        let content = fields["content:encoded"] ?? fields["content"]
        let snippet = HTMLText.snippet(description: description, content: content)
        let image = fields["media"].flatMap(URL.init(string:)) ?? HTMLText.firstImage(in: content ?? description)

        return FeedItem(
            guid: guid,
            title: title,
            link: link,
            creator: fields["dc:creator"] ?? "",
            published: published,
            categories: categories,
            snippet: snippet,
            wordCount: content.map { HTMLText.wordCount(HTMLText.plainText($0)) },
            imageURL: image,
            contentHTML: content
        )
    }
}

/// Small helpers for the HTML Medium puts inside feed items.
public enum HTMLText {

    /// Medium's tag feeds put a one-line teaser in `<p class="medium-feed-snippet">`.
    /// Author and publication feeds have full text instead; use its first heading or paragraph.
    public static func snippet(description: String, content: String?) -> String {
        if let teaser = firstMatch(#"<p class="medium-feed-snippet">(.*?)</p>"#, in: description) {
            return plainText(teaser)
        }
        let html = content ?? description
        for pattern in [#"<h4>(.*?)</h4>"#, #"<p[^>]*>(.*?)</p>"#] {
            if let match = firstMatch(pattern, in: html) {
                let text = plainText(match)
                if !text.isEmpty { return text }
            }
        }
        let text = plainText(html)
        return text == "Comments" ? "" : String(text.prefix(280))
    }

    public static func firstImage(in html: String) -> URL? {
        firstMatch(#"<img[^>]*src="([^"]+)""#, in: html).flatMap(URL.init(string:))
    }

    public static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(stripped)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = text[...]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let tail = rest[amp...]
            if let semi = tail.prefix(10).firstIndex(of: ";"),
               let decoded = entity(String(tail[tail.index(after: amp)..<semi])) {
                result += decoded
                rest = tail[tail.index(after: semi)...]
            } else {
                result += "&"
                rest = tail.dropFirst()
            }
        }
        return result + rest
    }

    private static func entity(_ name: String) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        default:
            let scalar: UInt32?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                scalar = UInt32(name.dropFirst(2), radix: 16)
            } else if name.hasPrefix("#") {
                scalar = UInt32(name.dropFirst())
            } else {
                scalar = nil
            }
            return scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
