//
//  EvaluationsView.swift
//  Scout
//
//  Every model answer is a ModelRun on this device. This screen compares roles and instruction
//  versions by thumbs-up rate, counts what code rejected, and surfaces "missing info" and empty tool
//  calls as hints about tools Scout still lacks. Nothing leaves the device unless you export it.
//

import CoreTransferable
import ScoutKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// One run as plain JSON, for export and replay.
struct RunRecord: Codable, Equatable, Sendable {
    var date: Date
    var role: String
    var pack: String
    var instructionsVersion: String
    var input: String
    var subjectID: String
    var output: String
    var rejection: String?
    var latency: Double
    var rating: Int
    var reasons: [String]
    var desired: String

    init(_ run: ModelRun) {
        date = run.date
        role = run.role
        pack = run.pack
        instructionsVersion = run.instructionsVersion
        input = run.input
        subjectID = run.subjectID
        output = run.output
        rejection = run.rejection
        latency = run.latency
        rating = run.rating
        reasons = run.reasons
        desired = run.desired
    }

    static func jsonl(_ records: [RunRecord]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return records.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
    }

    static func parse(jsonl: String) -> [RunRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return jsonl.split(separator: "\n").compactMap { try? decoder.decode(RunRecord.self, from: Data($0.utf8)) }
    }
}

struct RunsExport: Transferable {
    let records: [RunRecord]
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data(RunRecord.jsonl($0.records).utf8) }
            .suggestedFileName { _ in "scout-model-runs.jsonl" }
    }
}

struct EvaluationsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ModelRun.date, order: .reverse) private var runs: [ModelRun]
    @State private var log = ToolCallLog.shared
    @State private var confirmDelete = false

    private var byRole: [(role: String, runs: [ModelRun])] {
        Dictionary(grouping: runs, by: \.role).map { ($0.key, $0.value) }.sorted { $0.role < $1.role }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Model runs", value: "\(runs.count)")
                LabeledContent("Rated", value: "\(runs.filter { $0.rating != 0 }.count)")
                ShareLink(item: RunsExport(records: runs.filter { $0.rating != 0 }.map(RunRecord.init)),
                          preview: SharePreview("scout-model-runs.jsonl")) {
                    Label("Export rated runs (JSONL)", systemImage: "square.and.arrow.up")
                }
                .disabled(runs.allSatisfy { $0.rating == 0 })
                Button("Delete all model runs", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Runs stay on this device. Export only shares what you choose.")
            }

            ForEach(byRole, id: \.role) { role, runs in
                Section {
                    let up = runs.filter { $0.rating > 0 }.count
                    let down = runs.filter { $0.rating < 0 }.count
                    LabeledContent("Runs", value: "\(runs.count)")
                    LabeledContent("👍 / 👎", value: "\(up) / \(down)")
                    LabeledContent("Rejected by code", value: "\(runs.filter { $0.rejection != nil }.count)")
                    let missing = runs.filter { $0.reasons.contains("Missing info") }.count
                    if missing > 0 {
                        Label("\(missing) thumbs-down marked “Missing info”: a tool may be missing", systemImage: "wrench.adjustable")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    ForEach(versions(runs), id: \.version) { entry in
                        LabeledContent("Instructions \(entry.version)",
                                       value: entry.rated == 0 ? "no ratings" : "\(Int((entry.rate * 100).rounded()))% 👍 of \(entry.rated)")
                            .font(.caption.monospaced())
                    }
                } header: { MonoLabel(role) }
            }

            if !log.emptyOutputs.isEmpty {
                Section {
                    ForEach(log.emptyOutputs.sorted { $0.key < $1.key }, id: \.key) { key, count in
                        LabeledContent(key, value: "empty \(count)×").font(.caption.monospaced())
                    }
                } header: { MonoLabel("Tools that returned nothing (this session)") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("Evaluations")
        .confirmationDialog("Delete every model run on this device?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                try? context.delete(model: ModelRun.self)
                try? context.save()
            }
        }
    }

    /// Thumbs-up rate per instructions version, newest version first.
    private func versions(_ runs: [ModelRun]) -> [(version: String, rated: Int, rate: Double)] {
        Dictionary(grouping: runs, by: \.instructionsVersion).map { version, runs in
            let rated = runs.filter { $0.rating != 0 }
            return (version, rated.count, rated.isEmpty ? 0 : Double(rated.filter { $0.rating > 0 }.count) / Double(rated.count))
        }.sorted { $0.version < $1.version }
    }
}
