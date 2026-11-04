//
//  HTMLToMarkdown.swift
//  ScoutKit
//
//  Turns the article HTML in a feed's content:encoded into Markdown for Scout's native reader.
//  A small tag-stream converter, no web view: scripts, styles and iframes are dropped with their content,
//  unknown tags are removed, and text is escaped so it can't become Markdown syntax by accident.
//  Medium's <pre> blocks use <br> for line breaks and carry no language; the caller passes one.
//

import Foundation

public enum HTMLToMarkdown {

    public static func convert(_ html: String, codeLanguage: String = "") -> String {
        var converter = Converter(codeLanguage: codeLanguage)
        converter.run(html)
        return converter.result()
    }

    /// Member-only posts carry a preview in their feed; under this many words, the reader offers the rest on Medium.
    public static func isPreview(_ markdown: String, minimumWords: Int = 150) -> Bool {
        markdown.split(whereSeparator: \.isWhitespace).count < minimumWords
    }

    /// Swift when the post's tags say so; otherwise no language (plain).
    public static func codeLanguage(forTags tags: [String]) -> String {
        tags.contains { ["swift", "swiftui", "ios", "ios-development", "swift-programming"].contains($0.lowercased()) } ? "swift" : ""
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            if "\\`*_[]".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }
}

private struct Converter {
    let codeLanguage: String
    /// One buffer per open blockquote; the outermost is the document.
    private var buffers: [String] = [""]
    private var lists: [(ordered: Bool, count: Int)] = []
    private var links: [String] = []
    private var inPre = false
    private var preText = ""
    private var skipDepth = 0
    private var figureCaption = false
    private var inCode = false

    init(codeLanguage: String) {
        self.codeLanguage = codeLanguage
    }

    mutating func result() -> String {
        let text = buffers[0]
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private mutating func write(_ text: String) {
        buffers[buffers.count - 1] += text
    }

    /// Ends the current block with a blank line, once.
    private mutating func blockBreak() {
        let current = buffers[buffers.count - 1]
        if current.isEmpty || current.hasSuffix("\n\n") { return }
        write(current.hasSuffix("\n") ? "\n" : "\n\n")
    }

    private mutating func lineBreak() {
        let current = buffers[buffers.count - 1]
        if !current.isEmpty && !current.hasSuffix("\n") { write("\n") }
    }

    mutating func run(_ html: String) {
        var index = html.startIndex
        while index < html.endIndex {
            if html[index] == "<", let close = html[index...].firstIndex(of: ">") {
                handleTag(String(html[html.index(after: index)..<close]))
                index = html.index(after: close)
            } else {
                let next = html[index...].firstIndex(of: "<") ?? html.endIndex
                handleText(String(html[index..<next]))
                index = next
            }
        }
    }

    private mutating func handleText(_ raw: String) {
        guard skipDepth == 0 else { return }
        let text = HTMLText.decodeEntities(raw)
        if inPre { preText += text; return }
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !collapsed.trimmingCharacters(in: .whitespaces).isEmpty || (!collapsed.isEmpty && !buffers[buffers.count - 1].hasSuffix("\n")) else { return }
        let current = buffers[buffers.count - 1]
        let trimmed = current.hasSuffix("\n") || current.isEmpty ? String(collapsed.drop { $0 == " " }) : collapsed
        write(inCode ? trimmed : HTMLToMarkdown.escape(trimmed))
    }

    private mutating func handleTag(_ body: String) {
        let closing = body.hasPrefix("/")
        let name = body.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
        let attributes = String(body)

        if ["script", "style", "iframe", "noscript"].contains(name) {
            skipDepth += closing ? -1 : (body.hasSuffix("/") ? 0 : 1)
            skipDepth = max(0, skipDepth)
            return
        }
        guard skipDepth == 0 else { return }

        if inPre {
            switch (name, closing) {
            case ("br", _): preText += "\n"
            case ("pre", true):
                inPre = false
                let code = preText.trimmingCharacters(in: .newlines)
                blockBreak()
                write("```\(codeLanguage)\n\(code)\n```")
                blockBreak()
            default: break // inner <code>, <span>, <strong>: text only
            }
            return
        }

        switch (name, closing) {
        case ("p", false), ("div", false): blockBreak()
        case ("p", true), ("div", true): blockBreak()
        case ("h1", false), ("h2", false): blockBreak(); write("## ")
        case ("h3", false): blockBreak(); write("### ")
        case ("h4", false), ("h5", false), ("h6", false): blockBreak(); write("#### ")
        case ("h1", true), ("h2", true), ("h3", true), ("h4", true), ("h5", true), ("h6", true): blockBreak()
        case ("strong", _), ("b", _): write("**")
        case ("em", _), ("i", _): write("*")
        case ("code", _): write("`"); inCode = !closing
        case ("br", _): write("  \n")
        case ("pre", false): blockBreak(); inPre = true; preText = ""
        case ("a", false): links.append(attribute("href", in: attributes) ?? ""); write("[")
        case ("a", true): write("](\(links.popLast() ?? ""))")
        case ("ul", false), ("ol", false):
            if lists.isEmpty { blockBreak() } else { lineBreak() }
            lists.append((name == "ol", 0))
        case ("ul", true), ("ol", true):
            _ = lists.popLast()
            if lists.isEmpty { blockBreak() }
        case ("li", false):
            lineBreak()
            let depth = max(0, lists.count - 1)
            if !lists.isEmpty { lists[lists.count - 1].count += 1 }
            let marker = lists.last.map { $0.ordered ? "\($0.count). " : "- " } ?? "- "
            write(String(repeating: "  ", count: depth) + marker)
        case ("li", true): lineBreak()
        case ("blockquote", false): blockBreak(); buffers.append("")
        case ("blockquote", true):
            let quoted = buffers.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
            blockBreak()
            write(quoted)
            blockBreak()
        case ("img", _):
            guard let source = attribute("src", in: attributes), !source.isEmpty else { return }
            let alt = attribute("alt", in: attributes) ?? ""
            blockBreak()
            write("![\(HTMLToMarkdown.escape(alt))](\(source))")
            blockBreak()
        case ("figure", _): blockBreak()
        case ("figcaption", false): blockBreak(); write("*"); figureCaption = true
        case ("figcaption", true): if figureCaption { write("*"); figureCaption = false }; blockBreak()
        case ("hr", _): blockBreak(); write("---"); blockBreak()
        default: break
        }
    }

    private func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(name)\\s*=\\s*\"([^\"]*)\""),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return HTMLText.decodeEntities(String(tag[range]))
    }
}
