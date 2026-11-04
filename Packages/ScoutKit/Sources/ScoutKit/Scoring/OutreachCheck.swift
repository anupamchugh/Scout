//
//  OutreachCheck.swift
//  ScoutKit
//
//  An outreach note is at most two sentences, names the post's title, says one concrete thing in the
//  post's own words, makes no flattery claims and ends with a plain question. Code checks all of it.
//

import Foundation

public enum OutreachCheck {
    public enum Problem: String, Sendable, Equatable {
        case tooLong, missingTitle, nothingConcrete, flattery, noAsk, hasNumbersOrLinks
    }

    /// Praise words that say nothing about the post.
    static let flattery = ["amazing", "incredible", "brilliant", "powerful", "impressive", "outstanding", "exceptional",
                           "fantastic", "remarkable", "stellar", "strong technical", "great work", "insightful", "compelling"]

    public static func problems(_ note: String, title: String, snippet: String) -> [Problem] {
        var found: [Problem] = []
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if sentences(in: text).count > 2 { found.append(.tooLong) }
        if !TextGuard.normalized(text).contains(TextGuard.normalized(title)) { found.append(.missingTitle) }
        let withoutTitle = TextGuard.normalized(text).replacingOccurrences(of: TextGuard.normalized(title), with: " ")
        if !sharesPhrase(withoutTitle, with: snippet) { found.append(.nothingConcrete) }
        let lower = text.lowercased()
        if flattery.contains(where: { lower.contains($0) }) { found.append(.flattery) }
        if !text.hasSuffix("?") { found.append(.noAsk) }
        let digits = Set(text.filter(\.isNumber))
        if !digits.isSubset(of: Set((title + snippet).filter(\.isNumber))) || TextGuard.hasLink(text) {
            found.append(.hasNumbersOrLinks)
        }
        return found
    }

    public static func isGood(_ note: String, title: String, snippet: String) -> Bool {
        problems(note, title: title, snippet: snippet).isEmpty
    }

    /// A note built by code that meets every rule, used when the model's draft doesn't.
    public static func template(title: String, snippet: String, lane: String) -> String {
        let clause = snippet.split(whereSeparator: { ".!?;:".contains($0) }).first.map(String.init) ?? snippet
        let words = clause.split(separator: " ").prefix(9).joined(separator: " ")
        let phrase = words.isEmpty ? "" : " and the point about “\(words.prefix(1).lowercased() + words.dropFirst())”"
        return "I read “\(title)”\(phrase). Would you write a piece along those lines for \(lane)?"
    }

    static func sentences(in text: String) -> [String] {
        text.replacingOccurrences(of: "“[^”]*”", with: "QUOTE", options: .regularExpression)
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 }
    }

    /// True when the note repeats three consecutive words from the snippet.
    static func sharesPhrase(_ note: String, with snippet: String) -> Bool {
        let words = TextGuard.normalized(snippet).split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
        guard words.count >= 3 else { return false }
        let noteText = " " + note.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
        for i in 0...(words.count - 3) {
            let phrase = words[i..<(i + 3)].joined(separator: " ")
            if phrase.count > 8, noteText.contains(" \(phrase) ") { return true }
        }
        return false
    }
}

extension TextGuard {
    /// Free-form answers may use numbers only if they appear in the data the app gave the model; no links.
    public static func isGrounded(_ answer: String, in source: String) -> Bool {
        let numbers = { (text: String) -> Set<String> in
            let regex = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#)
            return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } })
        }
        return !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasLink(answer) && numbers(answer).isSubset(of: numbers(source))
    }
}
