//
//  PitchFacts.swift
//  ScoutKit
//

import Foundation

/// What code reads from a pitch before the model sees it: the text, a title line and any @handle.
public struct PitchFacts: Sendable, Equatable {
    public var text: String
    public var title: String
    public var handle: String?

    /// The first line of five characters or more is the title; the first `@handle` names the writer.
    public init(text: String) {
        self.text = text
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        title = lines.first { $0.count >= 5 } ?? String(localized: "Untitled pitch")
        if let range = text.range(of: #"@[A-Za-z0-9_.-]{2,}"#, options: .regularExpression) {
            handle = String(text[range].dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }
}
