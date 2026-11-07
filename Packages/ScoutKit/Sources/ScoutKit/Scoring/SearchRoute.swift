//
//  SearchRoute.swift
//  ScoutKit
//
//  Where a Siri search lands in Scout. Siri sends a plain search string ("check programming publications",
//  "is Level Up Coding slop", "compare ITNEXT and Stackademic"); code decides, from publication names and a
//  few words, whether it opens Compare with two publications or the writers-and-stories search.
//

import Foundation

public enum SearchRoute: Equatable, Sendable {
    case compare(PublicationChoice, PublicationChoice)
    case search(String)

    static let aliases: [(String, String)] = [
        ("level up coding", "gitconnected"), ("level up", "gitconnected"), ("levelup", "gitconnected"),
        ("gitconnected", "gitconnected"),
        ("better programming", "better-programming"), ("betterprogramming", "better-programming"),
        ("itnext", "itnext"), ("it next", "itnext"),
        ("javascript in plain english", "javascript-in-plain-english"), ("plain english", "javascript-in-plain-english"),
        ("stackademic", "stackademic"),
    ]

    static let publicationWords = ["publication", "slop", "compare", "versus", " vs "]

    /// Publications named in the text, in the order they first appear.
    static func named(in text: String) -> [PublicationChoice] {
        let lower = " \(text.lowercased()) "
        var hits: [(position: String.Index, key: String)] = []
        for (alias, key) in aliases {
            if let range = lower.range(of: alias), !hits.contains(where: { $0.key == key }) {
                hits.append((range.lowerBound, key))
            }
        }
        return hits.sorted { $0.position < $1.position }
            .compactMap { hit in PublicationChoice.presets.first { $0.key == hit.key } }
    }

    public static func route(_ term: String) -> SearchRoute {
        let text = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = named(in: text)
        let presets = PublicationChoice.presets
        let levelUp = presets[0], betterProgramming = presets[1]
        switch names.count {
        case 2...:
            return .compare(names[0], names[1])
        case 1:
            let other = names[0] == betterProgramming ? levelUp : betterProgramming
            return .compare(names[0], other)
        default:
            let lower = " \(text.lowercased()) "
            if publicationWords.contains(where: { lower.contains($0) }) { return .compare(levelUp, betterProgramming) }
            return .search(text)
        }
    }
}
