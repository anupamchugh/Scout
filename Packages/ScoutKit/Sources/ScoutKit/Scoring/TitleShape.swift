//
//  TitleShape.swift
//  ScoutKit
//
//  The shape of a headline, and whether a writer reuses one template, classified in code. The enum is
//  @Generable so a model answer can be constrained to it, but a 7 Nov 2026 trial labelled most plain titles
//  "listicle", so reports use the code classifier only. A shape is a pattern, not a judgement of the article.
//

import Foundation
import FoundationModels

@Generable
public enum TitleShape: String, Sendable, Codable, CaseIterable {
    /// Starts with a number: "7 Ways to…".
    case listicle
    /// "How to…", "step by step", "a guide to…".
    case howTo
    /// Ends in a question mark.
    case question
    /// "Part 1", "Part2".
    case seriesPart
    /// "Topic: subtitle".
    case colonSubtitle
    case plain

    /// The first rule that matches, in declaration order.
    public static func classify(_ title: String) -> TitleShape {
        let lower = title.lowercased()
        func has(_ pattern: String) -> Bool { lower.range(of: pattern, options: .regularExpression) != nil }
        if has(#"^\d+\s"#) { return .listicle }
        if has(#"\bhow to\b|\bstep by step\b|\bguide to\b"#) { return .howTo }
        if title.trimmingCharacters(in: .whitespaces).hasSuffix("?") { return .question }
        if has(#"\bpart ?\d+"#) { return .seriesPart }
        if title.contains(":") { return .colonSubtitle }
        return .plain
    }
}

/// Structural markers a headline template is made of, independent of its topic words.
public enum TitleMarker: String, Sendable, Codable, CaseIterable, Comparable {
    case leadingNumber, colon, fromTo, yearInBrackets, yearInTitle, seriesPart, question

    public static func < (a: TitleMarker, b: TitleMarker) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    public static func markers(_ title: String) -> [TitleMarker] {
        let lower = title.lowercased()
        func has(_ pattern: String) -> Bool { lower.range(of: pattern, options: .regularExpression) != nil }
        var found: [TitleMarker] = []
        if has(#"^\d+\s"#) { found.append(.leadingNumber) }
        if title.contains(":") { found.append(.colon) }
        if has(#"\bfrom\b.+\bto\b"#) { found.append(.fromTo) }
        if has(#"\((19|20)\d\d\)"#) { found.append(.yearInBrackets) } else if has(#"\b(19|20)\d\d\b"#) { found.append(.yearInTitle) }
        if has(#"\bpart ?\d+"#) { found.append(.seriesPart) }
        if title.trimmingCharacters(in: .whitespaces).hasSuffix("?") { found.append(.question) }
        return found
    }
}

public struct RepeatedTemplate: Sendable, Equatable {
    public var writer: String
    public var markers: [TitleMarker]
    public var titles: [String]
}

public enum TitleTemplates {
    /// Titles by the same writer that share the same set of two or more markers, two or more times.
    public static func repeated(_ titles: [(writer: String, title: String)]) -> [RepeatedTemplate] {
        var groups: [String: [String: [String]]] = [:]
        for (writer, title) in titles {
            let markers = TitleMarker.markers(title)
            guard markers.count >= 2 else { continue }
            groups[writer, default: [:]][markers.map(\.rawValue).joined(separator: "+"), default: []].append(title)
        }
        return groups.flatMap { writer, byKey in
            byKey.compactMap { key, list -> RepeatedTemplate? in
                guard list.count >= 2 else { return nil }
                let markers = key.split(separator: "+").compactMap { TitleMarker(rawValue: String($0)) }
                return RepeatedTemplate(writer: writer, markers: markers.sorted(), titles: list)
            }
        }
        .sorted { $0.titles.count != $1.titles.count ? $0.titles.count > $1.titles.count : $0.writer < $1.writer }
    }
}
