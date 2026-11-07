//
//  PublicationToolIntents.swift
//  Scout
//
//  Siri AI Developer Preview (iOS / macOS 27.3, beta): the same publication checks as tools Siri can call from a
//  natural-language request ("is Level Up Coding mostly slop lately?"), per Apple's "Bringing custom actions and
//  content to Siri". They exist only in SDKs whose AppIntents has `@AppIntent(.tool)` (module 301.2 and later),
//  so Xcode 27.2 builds skip this file and the phrase-based intents in PublicationIntents.swift keep working.
//

#if canImport(AppIntents, _version: 301.2)
import AppIntents
import Foundation
import ScoutKit

@available(iOS 27.3, macOS 27.3, *)
@AppIntent(.tool)
struct ScanProgrammingPublicationsTool: AppIntent {
    static let title: LocalizedStringResource = "Scan Programming Publications"
    static let description = IntentDescription(LocalizedStringResource(
        "Scans the latest feed posts of Level Up Coding, Better Programming, ITNEXT, JavaScript in Plain English, Stackademic and Data Science Collective, and reports formula titles, one-writer queues, stock phrases and archived publications. Counts are computed by the app; it does not judge article quality."))
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await CheckPublicationsIntent.briefing())")
    }
}

@available(iOS 27.3, macOS 27.3, *)
@AppIntent(.tool)
struct ReadPublicationForSlopTool: AppIntent {
    static let title: LocalizedStringResource = "Read a Publication for Slop"
    static let description = IntentDescription(LocalizedStringResource(
        "Reads a programming publication's latest posts on device with Apple Intelligence and reports how many are solid writing, good slop (formula title, solid substance) and bad slop (formula title, thin substance), naming the best read and any bad slop. Member-only posts without full text are not judged."))
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Publication", description: LocalizedStringResource("The programming publication to read"),
               default: .levelUpCoding)
    var publication: ProgrammingPublication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await CheckPublicationSlopIntent.report(publication))")
    }
}
#endif
