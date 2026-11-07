//
//  TagFit.swift
//  ScoutKit
//
//  Which of a post's own tags its text supports, decided by the on-device model and checked by code. The schema is
//  built per post with DynamicGenerationSchema: the model may only name tags from that post's list (anyOf), and for
//  the first tag it supports it must copy a sentence from the article. Code checks the sentence is really there;
//  tags the model leaves out are reported as unsupported.
//

import Foundation
import FoundationModels

public struct TagFitVerdict: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable { case checked, flagged, failed }
    public var status: Status
    public var supported: [String]
    public var unsupported: [String]
    public var evidence: String?
    public var problem: String?
}

public enum TagFit {

    /// Code's decision on a model answer: the evidence must be in the article and every supported tag must be the post's.
    public static func verdict(tags: [String], supported: [String], evidence: String, articleText: String) -> TagFitVerdict {
        let known = supported.filter { tags.contains($0) }
        let unique = known.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let quote = CritiqueCheck.normalized(evidence)
        let found = quote.split(separator: " ").count >= 4 && CritiqueCheck.normalized(articleText).contains(quote)
        return TagFitVerdict(status: found ? .checked : .flagged, supported: unique,
                             unsupported: tags.filter { !unique.contains($0) },
                             evidence: evidence, problem: found ? nil : "evidence sentence not found in the article")
    }

    public static func check(title: String, tags: [String], markdown: String,
                             model: SystemLanguageModel = .default) async -> TagFitVerdict {
        let material = await StoryCritic.material(markdown, tokenBudget: 2_400) { text in
            (try? await model.tokenCount(for: text)) ?? text.count / 4
        }
        let schema = DynamicGenerationSchema(name: "TagFit", properties: [
            .init(name: "evidence", description: "One sentence copied exactly from the article that shows its main subject",
                  schema: DynamicGenerationSchema(type: String.self, guides: [])),
            .init(name: "supportedTags", description: "Only the tags this article is actually about",
                  schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self, guides: [.anyOf(tags)]),
                                                  minimumElements: 0, maximumElements: tags.count)),
        ])
        let session = LanguageModelSession(model: model, instructions: """
            You check whether an article's tags describe it. First copy one sentence from the article exactly. Then list \
            only the tags the article is actually about. Leave out tags that are merely popular or only loosely related.
            """)
        do {
            let response = try await session.respond(
                to: "Title: \(title)\nTags: \(tags.joined(separator: ", "))\n\n<article>\n\(material)\n</article>",
                schema: try GenerationSchema(root: schema, dependencies: []),
                options: GenerationOptions(samplingMode: .greedy))
            let evidence = try response.content.value(String.self, forProperty: "evidence")
            let supported = try response.content.value([String].self, forProperty: "supportedTags")
            return verdict(tags: tags, supported: supported, evidence: evidence, articleText: material)
        } catch {
            return TagFitVerdict(status: .failed, supported: [], unsupported: [], evidence: nil,
                                 problem: error.localizedDescription)
        }
    }
}
