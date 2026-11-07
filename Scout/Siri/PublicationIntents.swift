//
//  PublicationIntents.swift
//  Scout
//
//  Ask Siri about programming publications. "Check programming publications in Scout" scans the latest feeds
//  in code (titles, writers, stock phrases; seconds, no model). "Check Level Up Coding for slop in Scout" reads
//  one publication on device with the StoryCritique rubric and reports good and bad slop. Siri speaks text
//  that code writes from computed numbers (PublicationBriefing); the model never writes the numbers.
//

import AppIntents
import Foundation
import ScoutKit

enum ProgrammingPublication: String, AppEnum, CaseIterable {
    case levelUpCoding = "gitconnected"
    case betterProgramming = "better-programming"
    case itnext = "itnext"
    case javaScriptInPlainEnglish = "javascript-in-plain-english"
    case stackademic = "stackademic"
    case dataScienceCollective = "data-science-collective"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Publication"
    static let caseDisplayRepresentations: [ProgrammingPublication: DisplayRepresentation] = [
        .levelUpCoding: "Level Up Coding",
        .betterProgramming: "Better Programming",
        .itnext: "ITNEXT",
        .javaScriptInPlainEnglish: "JavaScript in Plain English",
        .stackademic: "Stackademic",
        .dataScienceCollective: "Data Science Collective",
    ]

    var choice: PublicationChoice {
        PublicationChoice.presets.first { $0.key == rawValue } ?? PublicationChoice(name: rawValue, key: rawValue)
    }
}

struct CheckPublicationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Programming Publications"
    static let description = IntentDescription(
        "Scan the latest posts of Level Up Coding, Better Programming, ITNEXT, JavaScript in Plain English, Stackademic and Data Science Collective for formula titles, one-writer queues and stock phrases.")
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await Self.briefing()
        return .result(dialog: IntentDialog(full: "\(text)", supporting: "Latest programming publications."))
    }

    /// Feeds in parallel; a feed that fails is named rather than dropped silently.
    static func briefing() async -> String {
        let choices = ProgrammingPublication.allCases.map(\.choice)
        var sides: [String: PublicationSide] = [:]
        var failed: [String] = []
        await withTaskGroup(of: (String, PublicationSide?).self) { group in
            for choice in choices {
                group.addTask { (choice.key, try? await PublicationBriefing.quickSide(choice)) }
            }
            for await (key, side) in group {
                if let side { sides[key] = side } else { failed.append(choices.first { $0.key == key }?.name ?? key) }
            }
        }
        var text = PublicationBriefing.overview(choices.compactMap { sides[$0.key] })
        if !failed.isEmpty { text += " I couldn’t read \(failed.joined(separator: ", ")) right now." }
        return text
    }
}

struct CheckPublicationSlopIntent: AppIntent {
    static let title: LocalizedStringResource = "Check a Publication for Slop"
    static let description = IntentDescription(
        "Read a publication's latest posts on device with Apple Intelligence and report solid writing, good slop and bad slop.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Publication", default: .levelUpCoding)
    var publication: ProgrammingPublication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await Self.report(publication)
        return .result(dialog: IntentDialog(full: "\(text)", supporting: "\(publication.choice.name), read on this device."))
    }

    static func report(_ publication: ProgrammingPublication) async throws -> String {
        PublicationBriefing.slopReport(try await PublicationComparison.side(publication.choice))
    }
}

/// Siri's system search ("search Scout for…", and requests Siri reads as a search, such as "check programming
/// publications in Scout"). Publication questions open Compare and run it; anything else opens Search.
@AppIntent(schema: .system.searchInApp)
struct SearchScoutIntent {
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.open(SearchRoute.route(criteria.term))
        return .result()
    }
}
