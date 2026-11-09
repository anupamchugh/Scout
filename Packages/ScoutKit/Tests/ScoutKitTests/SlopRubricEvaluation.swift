//
//  SlopRubricEvaluation.swift
//  ScoutKitTests
//
//  Does the on-device StoryCritique reader agree with the editor? Each article the editor rated in the label set
//  (see SlopLabels and the SlopLabelSet tool) is read on device exactly as the Compare tab reads it, then code
//  compares the model's five ratings and its "solid" decision (the one that splits good slop from bad) with the
//  editor's. The set lives in WritingCorpus on this Mac and is never copied here; without rated articles, or
//  without Apple Intelligence, the suite is skipped.
//

import Evaluations
import Foundation
import FoundationModels
import Testing
@testable import ScoutKit

enum SlopLabelSetFixture {
    static let folder = URL(filePath: ProcessInfo.processInfo.environment["SCOUT_WRITING_CORPUS"]
                            ?? NSString("~/Desktop/workspace/WritingCorpus").expandingTildeInPath)
        .appending(path: "runs/slop-labels")

    /// Fully rated articles whose Markdown is present.
    static let rated: [(label: SlopLabel, markdown: String)] = {
        guard let labels = try? SlopLabels.load(folder.appending(path: "labels.json")) else { return [] }
        return labels.compactMap { label in
            guard label.editor.critique != nil,
                  let text = try? String(contentsOf: folder.appending(path: label.article), encoding: .utf8) else { return nil }
            return (label, text)
        }
    }()

    static var runnable: Bool {
        guard case .available = SystemLanguageModel.default.availability else { return false }
        return !rated.isEmpty
    }
}

/// Ratings in rubric order: clarity, depth, evidence, originality, specificity.
struct SlopRubricOutcome: Codable, Sendable, Equatable {
    var ratings: [CritiqueRating]?
    var status: String?

    static func ratings(_ c: StoryCritique) -> [CritiqueRating] {
        [c.clarity, c.depth, c.evidence, c.originality, c.specificity]
    }
}

struct SlopRubricEvaluation: Evaluation {
    let articles: [String: (label: SlopLabel, markdown: String)]

    /// Code's checks passed: both quotes are in the article, the reason has no number or link.
    let quoteChecked = Metric("Quote check passed")
    /// Share of the five ratings that equal the editor's.
    let exactAgreement = Metric("Ratings equal to the editor's")
    /// Share of the five ratings at most one step from the editor's.
    let withinOne = Metric("Ratings within one step")
    /// Model and editor make the same solid / thin decision, the split behind good vs bad slop.
    let solidAgreement = Metric("Solid decision agrees")
    let modelSolid = Metric("Model calls it solid")
    let editorSolid = Metric("Editor calls it solid")

    init(rated: [(label: SlopLabel, markdown: String)]) {
        articles = Dictionary(rated.map { ($0.label.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var name: String { "Slop rubric vs editor" }

    var dataset: ArrayLoader<ModelSample<SlopRubricOutcome>> {
        ArrayLoader(samples: articles.values.sorted { $0.label.id < $1.label.id }.map {
            ModelSample(prompt: $0.label.id,
                        expected: SlopRubricOutcome(ratings: $0.label.editor.critique.map(SlopRubricOutcome.ratings)))
        })
    }

    func subject(from sample: ModelSample<SlopRubricOutcome>) async throws -> ModelSubject<SlopRubricOutcome> {
        guard let article = articles[sample.promptDescription] else { return ModelSubject(value: SlopRubricOutcome()) }
        let verdict = await StoryCritic.critique(title: article.label.title, markdown: article.markdown)
        return ModelSubject(value: SlopRubricOutcome(
            ratings: verdict.status == .scored ? verdict.critique.map(SlopRubricOutcome.ratings) : nil,
            status: ([verdict.status.rawValue] + verdict.problems).joined(separator: ": ")))
    }

    static func critique(_ r: [CritiqueRating]) -> StoryCritique {
        StoryCritique(evidenceQuote: "", clarity: r[0], depth: r[1], evidence: r[2], originality: r[3], specificity: r[4], reason: "")
    }

    var evaluators: Evaluators {
        Evaluator { _, subject in
            quoteChecked.scoring(subject.value.ratings == nil ? 0 : 1, rationale: subject.value.status)
        }
        Evaluator { sample, subject in
            guard let model = subject.value.ratings, let editor = sample.expected?.ratings else {
                return exactAgreement.ignore(rationale: subject.value.status ?? "not scored")
            }
            let equal = zip(model, editor).filter { $0 == $1 }.count
            return exactAgreement.scoring(Double(equal) / 5, rationale: "model \(model.map(\.rawValue)) editor \(editor.map(\.rawValue))")
        }
        Evaluator { sample, subject in
            guard let model = subject.value.ratings, let editor = sample.expected?.ratings else {
                return withinOne.ignore(rationale: subject.value.status ?? "not scored")
            }
            let near = zip(model, editor).filter { abs($0.points - $1.points) <= 1 }.count
            return withinOne.scoring(Double(near) / 5, rationale: nil)
        }
        Evaluator { sample, subject in
            guard let model = subject.value.ratings, let editor = sample.expected?.ratings else {
                return solidAgreement.ignore(rationale: subject.value.status ?? "not scored")
            }
            let m = SlopBucket.solid(Self.critique(model)), e = SlopBucket.solid(Self.critique(editor))
            return solidAgreement.scoring(m == e ? 1 : 0, rationale: "model \(m ? "solid" : "thin"), editor \(e ? "solid" : "thin")")
        }
        Evaluator { _, subject in
            guard let model = subject.value.ratings else { return modelSolid.ignore(rationale: "not scored") }
            return modelSolid.scoring(SlopBucket.solid(Self.critique(model)) ? 1 : 0, rationale: nil)
        }
        Evaluator { sample, _ in
            guard let editor = sample.expected?.ratings else { return editorSolid.ignore(rationale: "not rated") }
            return editorSolid.scoring(SlopBucket.solid(Self.critique(editor)) ? 1 : 0, rationale: nil)
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: quoteChecked)
        aggregator.computeMean(of: exactAgreement)
        aggregator.computeMean(of: withinOne)
        aggregator.computeMean(of: solidAgreement)
        aggregator.computeMean(of: modelSolid)
        aggregator.computeMean(of: editorSolid)
    }
}

let slopRubric = SlopRubricEvaluation(rated: SlopLabelSetFixture.rated)

@Suite(.enabled(if: SlopLabelSetFixture.runnable, "needs rated articles in WritingCorpus/runs/slop-labels and Apple Intelligence"))
struct SlopRubricTests {
    /// No pass mark yet: the first run on real ratings sets the baseline. This prints it and checks the arithmetic.
    @Test(.evaluates(slopRubric, info: ["rubric": "StoryCritique"]))
    func rubricAgreesWithTheEditor() {
        let result = EvaluationContext.current.result
        for metric in [slopRubric.quoteChecked, slopRubric.exactAgreement, slopRubric.withinOne,
                       slopRubric.solidAgreement, slopRubric.modelSolid, slopRubric.editorSolid] {
            let value = result.aggregateValue(.mean(of: metric))
            print("\(metric.name): \(value) over \(SlopLabelSetFixture.rated.count) rated articles")
            #expect((0...1).contains(value))
        }
    }
}

struct SlopLabelsTests {
    @Test func mergeKeepsRatingsAndAddsOnlyNewArticles() {
        let rated = SlopLabel(id: "a", publication: "P", title: "A", link: "https://x/a", article: "articles/a.md",
                              editor: .init(clarity: .strong))
        let fresh = SlopLabel(id: "a", publication: "P", title: "A", link: "https://x/a", article: "articles/a.md")
        let other = SlopLabel(id: "b", publication: "P", title: "B", link: "https://x/b", article: "articles/b.md")
        let merged = SlopLabels.merge([rated], adding: [fresh, other])
        #expect(merged.map(\.id) == ["a", "b"])
        #expect(merged[0].editor.clarity == .strong)
    }

    @Test func editorRatingsAreScoredByTheSameCode() {
        let partial = SlopLabel.Ratings(clarity: .strong, depth: .strong, evidence: .strong, originality: .adequate)
        #expect(partial.critique == nil)
        var full = partial
        full.specificity = .adequate
        #expect(full.critique.map(SlopBucket.solid) == true)   // (3+3+3+2)/4 = 2.75, specificity not weak
        full.specificity = .weak
        #expect(full.critique.map(SlopBucket.solid) == false)
    }

    @Test func ratingsRoundTripAsPlainWords() throws {
        let json = #"[{"id":"a","publication":"P","title":"A","link":"https://x/a","article":"articles/a.md","editor":{"clarity":"weak"}}]"#
        let labels = try JSONDecoder().decode([SlopLabel].self, from: Data(json.utf8))
        #expect(labels[0].editor.clarity == .weak)
        #expect(labels[0].editor.depth == nil)
    }
}
