//
//  SiriPublicationEvaluations.swift
//  ScoutUITests
//
//  Scripted Siri requests about programming publications (Siri Evaluations, iOS 27.3 beta). Prints what Siri
//  answered and which Scout intents it called. SiriEvaluations ships only for devices (iPhoneOS platform), not
//  the simulator, and only in Xcode-beta's SDK, so every other build skips this file. Run on an iPhone with
//  iOS 27.3, Developer Mode and UI Automation on (Settings > Developer).
//

#if canImport(SiriEvaluations)
import SiriEvaluations

import XCTest

/// Runs each request through Siri and prints the transcript: the reply and the intents Siri called.
final class SiriPublicationTranscripts: XCTestCase {
    func testSiriTranscriptsForPublicationRequests() async throws {
        guard #available(iOS 27.3, *) else { throw XCTSkip("Siri Evaluations needs iOS 27.3") }
        let requests = [
            "Check programming publications in Scout",
            "Search Scout for Level Up Coding",
            "In Scout, check Level Up Coding for slop",
        ]
        for request in requests {
            let subject = try await SiriService.run(scenario: SiriScenario { UserTurn(request) })
            for turn in subject.siriTranscript.turns {
                let calls = turn.intentInvocations.map { String(describing: $0.value) }
                let found = turn.foundEntities.map { String(describing: $0.value) }
                print("SIRI-TRANSCRIPT request=\"\(request)\" response=\"\(turn.response.value)\" intents=\(calls) entities=\(found)")
            }
        }
    }
}
#endif
