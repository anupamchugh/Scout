//
//  EditorialRankingEvaluation.swift
//  ScoutKitTests
//
//  Does Scout's code ranking agree with the editor? The 25 Better Programming submissions the owner
//  accepted (14) or passed on (11), scored by `SubmissionScoring` as the deck would score them, and the
//  AUC of accepted over passed (0.5 is a coin flip). The model does not rank anything here.
//
//  The notes are the owner's private editorial notes, so they are read from WritingCorpus on this Mac
//  (set SCOUT_WRITING_CORPUS to move it) and never copied into this repository. Without them the test is skipped.
//

import Evaluations
import Foundation
import Testing
@testable import ScoutKit

/// One labelled submission: title and opening, without the editor's verdict.
struct EditorialSubmission: Sendable {
    let id: String
    let title: String
    let opening: String
    let accepted: Bool

    var prompt: String { "\(title)\n\n\(opening)" }

    static let corpus = URL(filePath: ProcessInfo.processInfo.environment["SCOUT_WRITING_CORPUS"]
                            ?? NSString("~/Desktop/workspace/WritingCorpus").expandingTildeInPath)

    static var available: Bool {
        FileManager.default.fileExists(atPath: corpus.appending(path: "runs/editorial-notes/labels.json").path())
    }

    /// The labelled set the curation judge was measured on (`runs/editorial-notes`), split the way `Editorial.swift` splits it.
    static func load() -> [EditorialSubmission] {
        guard let labelData = try? Data(contentsOf: corpus.appending(path: "runs/editorial-notes/labels.json")),
              let labels = try? JSONDecoder().decode([String: String].self, from: labelData),
              let indexData = try? Data(contentsOf: corpus.appending(path: "corpus/index.json")),
              let index = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any],
              let items = index["items"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return items.compactMap { item -> EditorialSubmission? in
            // The index lists one note twice; count each submitted piece once, as Editorial.swift does.
            guard let id = item["id"] as? String, let label = labels[id], seen.insert(id).inserted, let path = item["path"] as? String,
                  let title = item["title"] as? String,
                  let text = try? String(contentsOf: corpus.appending(path: "corpus").appending(path: path), encoding: .utf8)
            else { return nil }
            let body = text.components(separatedBy: "\n---\n").dropFirst().joined(separator: "\n---\n")
            let parts = body.components(separatedBy: "\n\n> ")
            guard parts.count > 1 else { return nil }
            let opening = parts.dropFirst().joined(separator: "\n\n").replacingOccurrences(of: "\n> ", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTitle = title.hasPrefix("Note on: ") ? String(title.dropFirst("Note on: ".count)) : title
            return EditorialSubmission(id: id, title: cleanTitle, opening: opening, accepted: label == "accepted")
        }
        .sorted { $0.id < $1.id }
    }
}

/// Expected: the editor's verdict. Subject: Scout's code score and the lane it scored best in.
struct EditorialOutcome: Codable, Sendable, Equatable {
    var accepted: Bool?
    var score: Int?
    var lane: String?
}

struct EditorialRankingEvaluation: Evaluation {
    let packName: String
    let lanes: [LaneSpec]
    let submissions: [EditorialSubmission]
    /// Scores computed once, in code, so each accepted piece can be compared with every passed one.
    let scores: [String: (score: Int, lane: String)]

    let codeScore = Metric("Code score")
    /// Mean over accepted pieces of the share of passed pieces they outrank: the ROC AUC.
    let outranksPassed = Metric("Accepted outranks passed (AUC)")

    init(pack: RolePack, submissions: [EditorialSubmission]) {
        packName = pack.name
        lanes = pack.laneSpecs
        self.submissions = submissions
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        scores = Dictionary(submissions.map { ($0.prompt, SubmissionScoring.score(title: $0.title, text: $0.opening, lanes: pack.laneSpecs, now: now)) },
                            uniquingKeysWith: { first, _ in first })
    }

    var name: String { "Editorial ranking: \(packName)" }

    var dataset: ArrayLoader<ModelSample<EditorialOutcome>> {
        ArrayLoader(samples: submissions.map { ModelSample(prompt: $0.prompt, expected: EditorialOutcome(accepted: $0.accepted)) })
    }

    var passedScores: [Double] {
        submissions.filter { !$0.accepted }.compactMap { scores[$0.prompt].map { Double($0.score) } }
    }

    func subject(from sample: ModelSample<EditorialOutcome>) async throws -> ModelSubject<EditorialOutcome> {
        let scored = scores[sample.promptDescription]
        return ModelSubject(value: EditorialOutcome(score: scored?.score, lane: scored?.lane))
    }

    var evaluators: Evaluators {
        Evaluator { _, subject in
            guard let score = subject.value.score else { return codeScore.ignore(rationale: "not scored") }
            return codeScore.scoring(Double(score), rationale: subject.value.lane)
        }
        Evaluator { sample, subject in
            guard sample.expected?.accepted == true, let score = subject.value.score else {
                return outranksPassed.ignore(rationale: "passed piece")
            }
            let share = SubmissionScoring.outrankShare(Double(score), over: passedScores)
            return outranksPassed.scoring(share, rationale: "score \(score) beats \(Int((share * 100).rounded()))% of passed pieces")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: codeScore)
        aggregator.computeMean(of: outranksPassed)
    }
}

let editorialSubmissions = EditorialSubmission.available ? EditorialSubmission.load() : []
let engineeringRanking = EditorialRankingEvaluation(pack: .engineering, submissions: editorialSubmissions)
let techWriterRanking = EditorialRankingEvaluation(pack: .techWriter, submissions: editorialSubmissions)

@Suite(.enabled(if: EditorialSubmission.available, "needs ~/Desktop/workspace/WritingCorpus"))
struct EditorialRankingTests {

    @Test func loadsTheLabelledSet() {
        #expect(editorialSubmissions.count == 25)
        #expect(editorialSubmissions.filter(\.accepted).count == 14)
        #expect(editorialSubmissions.allSatisfy { !$0.opening.lowercased().contains("you're live") && !$0.opening.contains("pass on this piece") })
    }

    @Test(.evaluates(engineeringRanking, info: ["pack": "engineering-editor"]))
    func engineeringPackRanking() {
        let auc = EvaluationContext.current.result.aggregateValue(.mean(of: engineeringRanking.outranksPassed))
        let direct = SubmissionScoring.auc(
            positives: editorialSubmissions.filter(\.accepted).compactMap { engineeringRanking.scores[$0.prompt].map { Double($0.score) } },
            negatives: engineeringRanking.passedScores)
        print("Editorial AUC, Engineering editor pack: \(auc)")
        #expect(abs(auc - direct) < 1e-9, "the framework's mean must equal the AUC computed directly")
    }

    @Test(.evaluates(techWriterRanking, info: ["pack": "tech-writer"]))
    func techWriterPackRanking() {
        let auc = EvaluationContext.current.result.aggregateValue(.mean(of: techWriterRanking.outranksPassed))
        print("Editorial AUC, Tech writer pack: \(auc)")
        #expect((0...1).contains(auc))
    }
}

struct SubmissionScoringTests {
    @Test func aucCountsTiesAsHalf() {
        #expect(SubmissionScoring.auc(positives: [3, 2], negatives: [1, 2]) == 0.875)
        #expect(SubmissionScoring.auc(positives: [1], negatives: [2]) == 0)
        #expect(SubmissionScoring.outrankShare(5, over: []) == 0.5)
    }

    @Test func onTopicPiecesScoreHigher() {
        let lanes = RolePack.engineering.laneSpecs
        let swift = SubmissionScoring.score(title: "Actors and task groups in Swift concurrency",
                                            text: "How async await, actors and task groups keep Swift code free of data races.", lanes: lanes)
        let cooking = SubmissionScoring.score(title: "My grandmother's lentil soup", text: "Soak the lentils overnight and add cumin.", lanes: lanes)
        #expect(swift.score > cooking.score)
        #expect(swift.lane == "Swift concurrency")
    }
}
