//
//  GenericWriting.swift
//  ScoutKit
//
//  Code-only signals of boilerplate prose in an article's Markdown: stock phrases, repeated sentence openings,
//  and how much of the article is code. They describe text patterns; none of them proves an article is bad
//  or machine-written, and the report shows the matches so an editor can check them.
//

import Foundation

public struct GenericWritingSignals: Sendable, Equatable, Codable {
    /// Stock phrases found, each once, in the order of `GenericWriting.stockPhrases`.
    public var stockPhrases: [String]
    /// Stock phrase hits per thousand words of prose.
    public var stockPerThousandWords: Double
    /// Share of prose sentences whose first two words open three or more sentences.
    public var repeatedOpeningShare: Double
    /// Share of non-empty lines that are inside code fences.
    public var codeLineShare: Double
    public var proseWords: Int
    /// Chat-assistant phrases found ("you're right", "that's on me"…), each once.
    public var assistantPhrases: [String] = []
    /// "Not X, but Y" / "X, not Y" / "— not" reframes per thousand words of prose.
    public var reframesPerThousandWords: Double = 0
    /// Em dashes per thousand words of prose.
    public var emDashesPerThousandWords: Double = 0
    /// Bold spans (**…**) per thousand words of prose.
    public var boldPerThousandWords: Double = 0
}

public enum GenericWriting {
    public static let stockPhrases = [
        "in today's fast-paced", "in this article, we will", "in this article, we'll", "let's dive in", "let's dive into",
        "dive deep into", "delve into", "in conclusion", "game-changer", "game changer", "unlock the power",
        "harness the power", "leverage the power", "it's important to note", "it is important to note",
        "whether you're a", "buckle up", "at the end of the day", "the world of", "ever-evolving", "seamlessly",
        "plays a crucial role", "a testament to", "without further ado", "happy coding",
    ]

    /// The chat-assistant register, as in the agent replies quoted in Jesse Vincent's "The Therapist Pattern"
    /// (blog.fsck.com, 20 Jul 2026): apology, self-correction and promises of a standing rule. Humans write
    /// these too; a hit is something to look at, not proof of how the text was written.
    public static let assistantPhrases = [
        "you're right", "you are right", "that's on me", "great question", "i hope this helps", "let me know if",
        "i apologize", "standing rule", "here's the thing", "to be clear,", "the short answer", "the real issue",
    ]

    static let reframePatterns = [
        #"\bnot (just|only|merely) [^.]{1,60}?,? but\b"#, #"\b(isn't|is not|wasn't|aren't) (just|only|about) "#,
        #", not [a-z]"#, #"\u{2014} not [a-z]"#,
    ]

    public static func signals(_ markdown: String) -> GenericWritingSignals {
        var inFence = false
        var prose: [Substring] = []
        var codeLines = 0, lines = 0
        for line in markdown.split(separator: "\n") {
            if line.hasPrefix("```") { inFence.toggle(); continue }
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            lines += 1
            if inFence { codeLines += 1 } else { prose.append(line) }
        }
        let text = prose.joined(separator: " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: \.isWhitespace).count

        var found: [String] = []
        var hits = 0
        for phrase in stockPhrases {
            let n = lower.components(separatedBy: phrase).count - 1
            if n > 0 { found.append(phrase); hits += n }
        }

        let sentences = lower.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.split(whereSeparator: { $0.isWhitespace || $0 == "#" || $0 == "*" || $0 == "-" }) }
            .filter { $0.count >= 4 }
        var openings: [String: Int] = [:]
        for s in sentences { openings["\(s[0]) \(s[1])", default: 0] += 1 }
        let repeated = sentences.filter { openings["\($0[0]) \($0[1])", default: 0] >= 3 }.count

        func perThousand(_ n: Int) -> Double { words == 0 ? 0 : Double(n) / Double(words) * 1000 }
        func matches(_ pattern: String) -> Int {
            (try? Regex(pattern)).map { lower.matches(of: $0).count } ?? 0
        }
        let assistant = assistantPhrases.filter { lower.contains($0) }
        let reframes = reframePatterns.reduce(0) { $0 + matches($1) }
        let emDashes = text.filter { $0 == "\u{2014}" }.count
        let bold = (try? Regex(#"\*\*[^*\n]+\*\*"#)).map { text.matches(of: $0).count } ?? 0

        return GenericWritingSignals(
            stockPhrases: found,
            stockPerThousandWords: perThousand(hits),
            repeatedOpeningShare: sentences.isEmpty ? 0 : Double(repeated) / Double(sentences.count),
            codeLineShare: lines == 0 ? 0 : Double(codeLines) / Double(lines),
            proseWords: words,
            assistantPhrases: assistant,
            reframesPerThousandWords: perThousand(reframes),
            emDashesPerThousandWords: perThousand(emDashes),
            boldPerThousandWords: perThousand(bold))
    }
}
