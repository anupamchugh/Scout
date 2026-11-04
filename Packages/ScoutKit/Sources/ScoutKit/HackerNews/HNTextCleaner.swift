//
//  HNTextCleaner.swift
//  ScoutKit
//
//  Copied from anupamchugh/Feedloom, Packages/FeedloomSources/Sources/FeedloomSources/HNTextCleaner.swift,
//  commit 64e548c (the code began in Distill). Unchanged apart from this header.
//
// ABOUTME: Turns the small HTML subset Hacker News uses in story and comment text into plain text for model input and display.
// Ported from Distill's HNTextCleaner with the same contract; it no longer goes through NSAttributedString's WebKit importer,
// which must run on the main thread and is slow, so it is a plain string pass that is safe anywhere and testable.

import Foundation

public enum HNTextCleaner {
    public static func plainText(fromHTML html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        var output = ""
        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]
            if character == "<", let close = html[index...].firstIndex(of: ">"), isTag(html[html.index(after: index)..<close]) {
                if isBlock(html[html.index(after: index)..<close]) { output.append(" ") } // inline tags (<a>, <i>) add no gap
                index = html.index(after: close)
            } else if character == "&", let end = html[index...].prefix(12).firstIndex(of: ";"),
                      let decoded = decode(String(html[html.index(after: index)..<end])) {
                output.append(decoded)
                index = html.index(after: end)
            } else {
                output.append(character)
                index = html.index(after: index)
            }
        }
        return output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Only the tags Hacker News emits count: `<p>`, `</i>`, `<br/>`, `<a href="…">`. A known name followed by a space needs
    /// an attribute (`=`), so `a<b and c>d`, `x<y` and `1 < 2` stay text.
    private static func isTag(_ body: Substring) -> Bool {
        let rest = body.drop { $0 == "/" }
        let name = rest.prefix { $0.isLetter || $0.isNumber }
        guard knownTags.contains(name.lowercased()) else { return false }
        let tail = rest.dropFirst(name.count)
        let bare = tail.drop { $0.isWhitespace }
        return tail.isEmpty || tail.first == "/" || (tail.first?.isWhitespace == true && (tail.contains("=") || bare.isEmpty || bare == "/"))
    }

    private static let knownTags: Set<String> = ["p", "br", "pre", "code", "i", "em", "b", "strong", "u", "a", "li", "ul", "ol", "div", "blockquote", "span"]

    private static let blockTags: Set<String> = ["p", "br", "pre", "li", "ul", "ol", "div", "blockquote"]

    private static func isBlock(_ body: Substring) -> Bool {
        let name = body.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }
        return blockTags.contains(name.lowercased())
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "hellip": "\u{2026}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}"
    ]

    private static func decode(_ entity: String) -> String? {
        if entity.hasPrefix("#") {
            let digits = entity.dropFirst()
            let value: UInt32?
            if digits.first == "x" || digits.first == "X" { value = UInt32(digits.dropFirst(), radix: 16) } else { value = UInt32(digits) }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[entity]
    }
}
