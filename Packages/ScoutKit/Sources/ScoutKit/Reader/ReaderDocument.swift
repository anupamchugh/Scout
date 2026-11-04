//
//  ReaderDocument.swift
//  ScoutKit
//
//  The reader's layout as blocks, parsed from the Markdown subset HTMLToMarkdown writes (headings,
//  paragraphs, lists, quotes, images, fenced code, rules). Inline styles and links use Foundation's own
//  Markdown parser. No third-party code.
//

import Foundation

public enum ReaderBlock: Equatable, Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case item(depth: Int, marker: String, text: AttributedString)
    case quote(AttributedString)
    case image(URL, alt: String)
    case code(language: String, code: String)
    case rule
}

public enum ReaderDocument {

    public static func blocks(_ markdown: String) -> [ReaderBlock] {
        var blocks: [ReaderBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var paragraph: [String] = []
        var quote: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: "\n"))))
            paragraph = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(inline(quote.joined(separator: "\n"))))
            quote = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph(); flushQuote()
                let language = String(trimmed.dropFirst(3))
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language, code: code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph(); flushQuote()
            } else if let level = headingLevel(trimmed) {
                flushParagraph(); flushQuote()
                blocks.append(.heading(level: level, text: inline(String(trimmed.drop { $0 == "#" }.dropFirst()))))
            } else if trimmed == ">" || trimmed.hasPrefix("> ") {
                flushParagraph()
                quote.append(trimmed == ">" ? "" : String(trimmed.dropFirst(2)))
            } else if trimmed == "---" {
                flushParagraph(); flushQuote()
                blocks.append(.rule)
            } else if let image = image(trimmed) {
                flushParagraph(); flushQuote()
                blocks.append(image)
            } else if let item = listItem(line) {
                flushParagraph(); flushQuote()
                blocks.append(item)
            } else {
                flushQuote()
                paragraph.append(trimmed.hasSuffix("  ") ? String(trimmed.dropLast(2)) : trimmed)
            }
            index += 1
        }
        flushParagraph(); flushQuote()
        return blocks
    }

    public static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func image(_ line: String) -> ReaderBlock? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let middle = line.range(of: "]("),
              let url = URL(string: String(line[middle.upperBound..<line.index(before: line.endIndex)])) else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<middle.lowerBound]).replacingOccurrences(of: "\\", with: "")
        return .image(url, alt: alt)
    }

    private static func listItem(_ line: String) -> ReaderBlock? {
        let indent = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(indent)
        if rest.hasPrefix("- ") {
            return .item(depth: indent / 2, marker: "•", text: inline(String(rest.dropFirst(2))))
        }
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix(". ") {
            return .item(depth: indent / 2, marker: "\(digits).", text: inline(String(rest.dropFirst(digits.count + 2))))
        }
        return nil
    }
}

/// A small Swift tokenizer for highlighting code blocks: comments, strings, numbers, keywords, types and attributes.
public enum SwiftTokenizer {
    public enum Kind: String, Sendable, Equatable {
        case plain, keyword, type, string, number, comment, attribute
    }

    public struct Token: Sendable, Equatable {
        public let text: String
        public let kind: Kind
    }

    static let keywords: Set<String> = [
        "actor", "any", "as", "async", "await", "break", "case", "catch", "class", "consuming", "continue", "default",
        "defer", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard", "if",
        "import", "in", "init", "inout", "internal", "is", "let", "nil", "nonisolated", "open", "private", "protocol",
        "public", "repeat", "rethrows", "return", "self", "Self", "some", "static", "struct", "subscript", "super",
        "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while", "sending", "isolated",
    ]

    public static func tokens(_ code: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(code)
        var index = 0
        func take(_ count: Int, _ kind: Kind) {
            tokens.append(Token(text: String(characters[index..<min(index + count, characters.count)]), kind: kind))
            index += count
        }
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "/" && next == "/" {
                var end = index
                while end < characters.count && characters[end] != "\n" { end += 1 }
                take(end - index, .comment)
            } else if character == "/" && next == "*" {
                var end = index + 2
                while end + 1 < characters.count && !(characters[end] == "*" && characters[end + 1] == "/") { end += 1 }
                take(min(end + 2, characters.count) - index, .comment)
            } else if character == "\"" {
                var end = index + 1
                while end < characters.count && characters[end] != "\"" && characters[end] != "\n" {
                    end += characters[end] == "\\" ? 2 : 1
                }
                take(min(end + 1, characters.count) - index, .string)
            } else if character.isNumber {
                var end = index
                while end < characters.count && (characters[end].isNumber || characters[end] == "." || characters[end] == "_") { end += 1 }
                take(end - index, .number)
            } else if character == "@" || character.isLetter || character == "_" {
                var end = index + 1
                while end < characters.count && (characters[end].isLetter || characters[end].isNumber || characters[end] == "_") { end += 1 }
                let word = String(characters[index..<end])
                let kind: Kind = word.hasPrefix("@") ? .attribute : keywords.contains(word) ? .keyword
                    : word.first?.isUppercase == true ? .type : .plain
                take(end - index, kind)
            } else {
                take(1, .plain)
            }
        }
        // Merge neighbouring plain tokens so the renderer makes fewer runs.
        return tokens.reduce(into: []) { merged, token in
            if let last = merged.last, last.kind == .plain, token.kind == .plain {
                merged[merged.count - 1] = Token(text: last.text + token.text, kind: .plain)
            } else {
                merged.append(token)
            }
        }
    }
}
