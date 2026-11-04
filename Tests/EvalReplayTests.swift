//
//  EvalReplayTests.swift
//  ScoutTests
//
//  Replays saved thumbs-down runs through the current instructions with a scripted model that answers
//  what the real model answered, and checks the guards still catch them. The JSONL export round-trips.
//

import Foundation
import FoundationModels
import ScoutKit
import SwiftData
import Testing
@testable import Scout

/// Thumbs-down runs as the Evaluations screen exports them.
private let savedRuns = """
{"date":"2026-11-05T10:00:00Z","desired":"Mention the cancellation post","input":"Why this writer?","instructionsVersion":"a1b2c3d4","latency":2.1,"output":"They have 12,000 followers and write about Swift.","pack":"engineering-editor","rating":-1,"reasons":["Made something up"],"rejection":null,"role":"ask","subjectID":"writer:w"}
{"date":"2026-11-05T10:01:00Z","desired":"","input":"Summarize this post","instructionsVersion":"a1b2c3d4","latency":1.4,"output":"Read the full post at https://example.com/post.","pack":"engineering-editor","rating":-1,"reasons":["Wrong"],"rejection":null,"role":"ask","subjectID":"writer:w"}
{"date":"2026-11-05T10:02:00Z","desired":"","input":"Why this writer?","instructionsVersion":"a1b2c3d4","latency":1.9,"output":"Their posts explain why a shared Task keeps running after cancellation.","pack":"engineering-editor","rating":-1,"reasons":["Too vague"],"rejection":null,"role":"ask","subjectID":"writer:w"}
"""

@MainActor
struct EvalReplayTests {

    @Test func exportRoundTrips() throws {
        let records = RunRecord.parse(jsonl: savedRuns)
        #expect(records.count == 3)
        #expect(RunRecord.parse(jsonl: RunRecord.jsonl(records)) == records)
        #expect(records[0].reasons == ["Made something up"])
    }

    @Test func runsAreSavedWithRatingsAndReasons() throws {
        let container = ScoutStore.make(inMemory: true)
        let context = container.mainContext
        let run = ModelRun(role: "ask", pack: "engineering-editor", instructionsVersion: "v1", input: "Why?",
                           subjectID: "writer:w", output: "Because.", rejection: nil, latency: 1)
        context.insert(run)
        run.rating = -1
        run.reasons = ["Missing info", "Too vague"]
        try context.save()
        let stored = try #require(try context.fetch(FetchDescriptor<ModelRun>()).first)
        #expect(stored.rating == -1)
        #expect(stored.reasons == ["Missing info", "Too vague"])
        #expect(RunRecord(stored).reasons == ["Missing info", "Too vague"])
    }

    /// The scripted model replies with each saved output; the Ask guard must still hide invented numbers and links.
    @Test func replayingThumbsDownThroughTheGuards() async throws {
        let container = ScoutStore.make(inMemory: true)
        Writer.container = container
        defer { Writer.languageModel = nil }
        let corpus = "You cancelled the caller. Why is the shared Task still running? A shared Task keeps running after cancellation."

        var results: [String?] = []
        for record in RunRecord.parse(jsonl: savedRuns) {
            Writer.languageModel = ScriptedLanguageModel(ModelScript.answering(record.output))
            let session = Writer.session(.asking, authorKey: "w")
            let (_, rejection) = try await Writer.ask(record.input, about: "Writer", post: "You cancelled the caller.",
                                                      snippet: "", stats: nil, corpus: corpus, session: session)
            results.append(rejection)
        }
        #expect(results[0] != nil, "an invented follower count must be hidden")
        #expect(results[1] != nil, "a link must be hidden")
        #expect(results[2] == nil, "a grounded answer passes the guard; its thumbs-down is about quality, for the instructions to fix")
    }
}
