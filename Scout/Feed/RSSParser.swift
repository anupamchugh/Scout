//
//  RSSParser.swift
//  Scout
//

import Foundation

enum RSSParserError: Error, Equatable {
    case malformed(String)
}

/// Parses Medium's RSS 2.0 feeds with `XMLParser`.
final class RSSParser: NSObject, XMLParserDelegate {

    static func parse(_ data: Data) throws -> [FeedItem] {
        try parseDocument(data).items
    }

    /// Items plus the channel's image, which on an author feed is the writer's avatar.
    static func parseDocument(_ data: Data) throws -> FeedDocument {
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

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "image" && !inItem {
            inChannelImage = true
        }
        if elementName == "item" {
            inItem = true
            fields = [:]
            categories = []
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
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
        case "item":
            inItem = false
            if let item = makeItem() { items.append(item) }
        case "category":
            if !value.isEmpty { categories.append(value) }
        default:
            fields[elementName] = value
        }
        text = ""
    }

    private func makeItem() -> FeedItem? {
        guard let title = fields["title"].map(HTMLText.decodeEntities), !title.isEmpty,
              let link = fields["link"].flatMap(URL.init(string:)),
              let guid = fields["guid"], !guid.isEmpty,
              let published = fields["pubDate"].flatMap(dateFormatter.date(from:))
        else { return nil }

        let description = fields["description"] ?? ""
        let content = fields["content:encoded"]
        let snippet = HTMLText.snippet(description: description, content: content)
        let image = HTMLText.firstImage(in: content ?? description)

        return FeedItem(
            guid: guid,
            title: title,
            link: link,
            creator: fields["dc:creator"] ?? "",
            published: published,
            categories: categories,
            snippet: snippet,
            wordCount: content.map { HTMLText.wordCount(HTMLText.plainText($0)) },
            imageURL: image
        )
    }
}

/// Small helpers for the HTML Medium puts inside feed items.
enum HTMLText {

    /// Medium's tag feeds put a one-line teaser in `<p class="medium-feed-snippet">`.
    /// Author and publication feeds have full text instead; use its first heading or paragraph.
    static func snippet(description: String, content: String?) -> String {
        if let teaser = firstMatch(#"<p class="medium-feed-snippet">(.*?)</p>"#, in: description) {
            return plainText(teaser)
        }
        let html = content ?? description
        for pattern in [#"<h4>(.*?)</h4>"#, #"<p>(.*?)</p>"#] {
            if let match = firstMatch(pattern, in: html) {
                let text = plainText(match)
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    static func firstImage(in html: String) -> URL? {
        firstMatch(#"<img[^>]*src="([^"]+)""#, in: html).flatMap(URL.init(string:))
    }

    static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(stripped)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    static func decodeEntities(_ text: String) -> String {
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
