//
//  PackSkills.swift
//  Scout
//
//  One Foundation Models Skill per role pack: the pack's house style, loaded on demand. Code decides
//  which pack's skill a session is offered (only the active pack's); the model decides only whether it
//  needs the style guide for this answer, which costs no context until it does. Scores, IDs and facts
//  never come from a skill.
//

import FoundationModels
import FoundationModelsUtilities
import ScoutKit

enum PackSkills {
    /// Modes that write prose for the editor, where a style guide helps. Scouting's "why" line stays tool-light.
    static func offered(in mode: ScoutMode) -> Bool {
        switch mode {
        case .asking, .issueWriting, .blurber, .spotlight, .editor: true
        case .scouting, .pitchReading, .curator: false
        }
    }

    static func name(for pack: RolePack) -> String {
        switch pack.id {
        case RolePack.engineering.id: "engineering-editor-style"
        case RolePack.techWriter.id: "newsletter-style"
        case RolePack.illustrator.id: "illustrator-style"
        default: "pack-style"
        }
    }

    static func guide(for pack: RolePack) -> String {
        switch pack.id {
        case RolePack.engineering.id:
            """
            Engineering editor style:
            - Name the concrete technique from the writer's own post (an API, a pattern, a measurement they made).
            - Prefer "they show how" over praise words such as amazing, great or must-read.
            - One idea per sentence. Plain verbs. No marketing tone.
            """
        case RolePack.techWriter.id:
            """
            Newsletter style:
            - Write for a broad programming audience: say what the reader will be able to do after reading.
            - Warm and brief. Second person ("you") for readers, the writer's name or they/them for the writer.
            - No hype, no clickbait questions, no emoji.
            """
        case RolePack.illustrator.id:
            """
            Illustrator style:
            - Talk about the work: medium, composition, colour and subject, only as the feed's words describe them.
            - Never describe the artist as a person, their body or their appearance.
            - You cannot see images; never claim to.
            """
        default:
            "House style: plain, specific and brief. \(pack.outreachStyle)"
        }
    }

    static func description(for pack: RolePack) -> String {
        "House writing style for the \(pack.name) role. Activate before writing prose for the editor."
    }

    static func skill(for pack: RolePack) -> Skill {
        Skill(name: name(for: pack), description: description(for: pack), prompt: guide(for: pack))
    }
}
