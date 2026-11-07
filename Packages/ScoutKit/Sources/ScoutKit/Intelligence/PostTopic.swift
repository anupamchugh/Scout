//
//  PostTopic.swift
//  ScoutKit
//
//  What a post is about, from its title alone, labelled by the on-device model into a closed @Generable enum. Used
//  where a publication offers only titles (sitemaps): the model chooses one case per title and code counts them. A
//  title-only label is a topic guess, never a quality judgement.
//

import Foundation
import FoundationModels

@Generable
public enum PostTopic: String, Sendable, Codable, CaseIterable {
    case aiAndLLMs = "AI and LLMs"
    case webAndFrontend = "Web and front end"
    case backendAndArchitecture = "Back end and architecture"
    case languagesAndPatterns = "Languages and patterns"
    case devopsAndCloud = "DevOps and cloud"
    case dataAndML = "Data and machine learning"
    case mobile = "Mobile"
    case securityAndPrivacy = "Security and privacy"
    case careerAndProductivity = "Career and productivity"
    case toolsAndWorkflow = "Tools and workflow"
    case other = "Other"
}

public enum PostTopicLabeler {
    public static let instructions = """
        You label the topic of a programming article from its title. Choose the single topic that best fits. \
        Pick AI and LLMs only when the title is about AI, models, agents or prompts.
        """

    /// One title, one topic; nil when the model is unavailable or fails.
    public static func label(_ title: String, model: SystemLanguageModel = .default) async -> PostTopic? {
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(model: model, instructions: instructions)
        return try? await session.respond(to: "Title: \(title)", generating: PostTopic.self,
                                          options: GenerationOptions(samplingMode: .greedy)).content
    }

    /// Counts by topic, most first, ties in declaration order; unlabelled titles are not counted.
    public static func counts(_ labels: [PostTopic?]) -> [(topic: PostTopic, count: Int)] {
        PostTopic.allCases.map { topic in (topic, labels.filter { $0 == topic }.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }
}
