//
//  SettingsView.swift
//  Scout
//

import ScoutKit
import SwiftData
import SwiftUI

/// Pick a role pack at first launch.
struct PackPickerView: View {
    @Environment(ScoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Scout reads open feeds and ranks what it finds in code. Pick the kind of scouting you do; you can switch or import another pack later.")
                        .foregroundStyle(Color.inkSecondary)
                }
                ForEach(PackStore.all) { pack in
                    Button {
                        model.switchPack(to: pack)
                        dismiss()
                    } label: {
                        PackRow(pack: pack, isActive: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pack.\(pack.id)")
                }
                Section {
                    Button { importing = true } label: {
                        Label("Import a pack…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.inkSecondary.opacity(0.5),
                                                                                         style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Your swipes tune the pack: tags you keep rise, tags you pass fall. Scout does this in code, on this device.")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.scoutPack, .json]) { result in
                if case .success(let url) = result, let pack = try? PackStore.importPack(from: url) {
                    model.switchPack(to: pack)
                    dismiss()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("What do you scout?")
        }
        .interactiveDismissDisabled()
    }
}

struct PackRow: View {
    let pack: RolePack
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pack.isVisual ? "paintpalette" : pack.output == .markdownAndHTML ? "text.quote" : "chevron.left.forwardslash.chevron.right")
                .font(.title3)
                .foregroundStyle(Color.scoutGreen)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name).font(.headline).foregroundStyle(Color.ink)
                Text(pack.summary).font(.subheadline).foregroundStyle(Color.inkSecondary)
                Text(pack.lanes.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
            if isActive { Image(systemName: "checkmark").foregroundStyle(Color.scoutGreen) }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

struct SettingsView: View {
    @Environment(ScoutModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var importMessage: String?
    @State private var log = ToolCallLog.shared

    private var taste: Taste { ScoutStore.taste(for: model.activePack, in: context).taste }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PackStore.all) { pack in
                        Button { model.switchPack(to: pack) } label: { PackRow(pack: pack, isActive: pack.id == model.activePack.id) }
                            .buttonStyle(.plain)
                    }
                    Button("Import a pack…", systemImage: "square.and.arrow.down") { importing = true }
                    ShareLink(item: model.activePack, preview: SharePreview(model.activePack.name)) {
                        Label("Share \(model.activePack.name)", systemImage: "square.and.arrow.up")
                    }
                    if let importMessage { Text(importMessage).font(.caption).foregroundStyle(Color.inkSecondary) }
                } header: { MonoLabel("Role pack") }

                Section {
                    let weights = taste.tagWeights.sorted { abs($0.value) != abs($1.value) ? abs($0.value) > abs($1.value) : $0.key < $1.key }
                    LabeledContent("Swipes", value: "\(taste.likes) kept · \(taste.passes) passed")
                    if weights.isEmpty {
                        Text("Swipe a few cards and Scout starts weighting tags you keep or pass.").font(.caption).foregroundStyle(Color.inkSecondary)
                    }
                    ForEach(weights.prefix(8), id: \.key) { tag, weight in
                        LabeledContent(tag) {
                            Text(weight, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                                .monospacedDigit()
                                .foregroundStyle(weight >= 0 ? Color.scoutGreen : Color.inkSecondary)
                        }
                    }
                    Button("Reset what Scout learned", role: .destructive) {
                        let record = ScoutStore.taste(for: model.activePack, in: context)
                        record.taste = Taste()
                        record.likedPrints = []
                        try? context.save()
                    }
                } header: {
                    MonoLabel("Learned from swipes · computed in code")
                }

                Section {
                    switch ModelAvailability.current {
                    case .available:
                        Label("Available on this device", systemImage: "checkmark.circle").foregroundStyle(Color.scoutGreen)
                    case .unavailable(let reason):
                        Label(reason, systemImage: "exclamationmark.circle").foregroundStyle(Color.inkSecondary)
                    }
                    Text("On this device, Apple Intelligence writes the “why” lines, outreach and issue drafts, and answers in Ask. It reads only feed text and what Scout stored, through tools that return your data. Code decides every score, count, link and order, and hides any answer with numbers or links that aren't in your data.")
                        .font(.footnote).foregroundStyle(Color.inkSecondary)
                    Text("Private Cloud Compute is off: it needs an entitlement this build doesn't have. Everything runs on device.")
                        .font(.footnote).foregroundStyle(Color.inkSecondary)
                    NavigationLink("Evaluations") { EvaluationsView() }
                } header: { MonoLabel("Apple Intelligence") }

                Section {
                    if log.entries.isEmpty {
                        Text("No tool calls yet.").font(.caption).foregroundStyle(Color.inkSecondary)
                    }
                    ForEach(log.entries) { entry in
                        LabeledContent(entry.tool, value: "\(entry.mode.rawValue) · \(entry.at.formatted(date: .omitted, time: .standard))")
                            .font(.caption.monospaced())
                    }
                } header: { MonoLabel("Model tool calls · debug") }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.scoutPack, .json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let pack = try PackStore.importPack(from: url)
                        model.switchPack(to: pack)
                        importMessage = "Imported \(pack.name)."
                    } catch {
                        importMessage = "That file isn't a Scout pack."
                    }
                case .failure:
                    importMessage = nil
                }
            }
        }
    }
}
