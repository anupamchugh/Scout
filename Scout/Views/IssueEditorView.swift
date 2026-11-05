//
//  IssueEditorView.swift
//  Scout
//

import ScoutKit
import SwiftData
import SwiftUI

struct IssueEditorView: View {
    @Bindable var issue: IssueDraft
    @Environment(\.modelContext) private var context
    @State private var showsPreview = false
    @State private var copied = false
    @State private var agents = IssueAgents()
    @Environment(ScoutModel.self) private var model

    private var content: IssueContent { issue.content }

    /// Entries grouped by the Curator's sections, in order; one group before the agents run.
    private var groups: [(name: String, entries: [IssueEntry])] {
        var order: [String] = []
        var byName: [String: [IssueEntry]] = [:]
        for entry in issue.orderedEntries {
            if byName[entry.section] == nil { order.append(entry.section) }
            byName[entry.section, default: []].append(entry)
        }
        return order.map { ($0, byName[$0]!) }
    }

    var body: some View {
        List {
            Section {
                agentPanel
            } header: { MonoLabel("Agents · on device") }

            Section {
                TextField("Issue title", text: $issue.title).font(.title3.weight(.semibold))
                Stepper("Issue \(issue.number)", value: $issue.number, in: 1...999)
            } header: { MonoLabel("Issue · Editor's title") }

            Section {
                TextField("A short intro for readers", text: $issue.intro, axis: .vertical).lineLimit(2...8)
                if ModelAvailability.current.isAvailable && !issue.intro.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(["Shorter", "More technical", "Plainer"], id: \.self) { chip in
                            Button(chip) { Task { await agents.followUp(chip, issue: issue, in: context) } }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(agents.isRunning)
                        }
                    }
                }
            } header: { MonoLabel("Intro · Editor") }

            if !issue.agentFlags.isEmpty {
                Section {
                    ForEach(issue.agentFlags, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.footnote) }
                        .foregroundStyle(.orange)
                } header: { MonoLabel("Checker") }
            }

            ForEach(groups, id: \.name) { group in
                Section {
                    ForEach(group.entries) { IssueEntryRow(entry: $0) }
                        .onMove { move($0, $1, in: group.entries) }
                        .onDelete { delete($0, in: group.entries) }
                } header: {
                    if group.name.isEmpty { MonoLabel("Entries · drag to reorder") } else { MonoLabel(group.name) }
                } footer: {
                    if issue.entries.isEmpty { Text("Swipe a writer or story up in Today to add it here.") }
                }
            }

            if let name = issue.spotlightName, !issue.spotlightQuestions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(issue.spotlightHandle.map { "\(name) · @\($0)" } ?? name).font(.headline)
                        if !issue.spotlightIntro.isEmpty { Text(verbatim: issue.spotlightIntro).font(.callout) }
                        ForEach(issue.spotlightQuestions, id: \.self) { Text(verbatim: "• \($0)").font(.callout).foregroundStyle(Color.inkSecondary) }
                    }
                    .padding(.vertical, 4)
                } header: { MonoLabel("Writer spotlight · Spotlight agent") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle(issue.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem { EditButton() }
            #endif
            ToolbarItem {
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button(copied ? "Copied" : "Copy Markdown", systemImage: "doc.on.doc") {
                        Pasteboard.copy(IssueRenderer.markdown(content))
                        copied = true
                    }
                    ShareLink("Share Markdown / HTML", item: IssueExport(issue: content),
                              preview: SharePreview(content.heading))
                    ShareLink("Share llms.txt", item: IssueLLMsExport(issue: content), preview: SharePreview("llms.txt"))
                }
            }
            ToolbarItem {
                Button("Preview", systemImage: "eye") { showsPreview = true }
                    .accessibilityIdentifier("issue.preview")
            }
        }
        .sheet(isPresented: $showsPreview) { IssuePreview(content: content) }
        .task(id: issue.entries.count) {
            for entry in issue.orderedEntries { await LinkPreview.fetch(into: entry) }
            try? context.save()
        }
    }

    @ViewBuilder
    private var agentPanel: some View {
        if case .unavailable(let reason) = ModelAvailability.current {
            Label(reason, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Color.inkSecondary)
        } else {
            Button(agents.isRunning ? "Drafting…" : "Draft with agents", systemImage: "sparkles") {
                Task { await agents.run(issue, in: context, pack: model.activePack) }
            }
            .buttonStyle(.glassProminent)
            .disabled(agents.isRunning || issue.entries.isEmpty)
            .accessibilityIdentifier("issue.agents")
            if agents.isRunning || !agents.finished.isEmpty {
                ForEach(IssueAgents.Step.allCases, id: \.self) { step in
                    HStack {
                        if agents.finished.contains(step) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.scoutGreen)
                        } else if agents.current == step {
                            ProgressView()
                        } else {
                            Image(systemName: "circle").foregroundStyle(Color.hairline)
                        }
                        Text(step.title).font(.footnote)
                    }
                }
            }
            if let message = agents.message { Text(message).font(.footnote).foregroundStyle(Color.inkSecondary) }
            Text("Curator picks sections from your stories, Blurber writes a line each, Spotlight features a shortlisted writer, Editor titles it. Code checks every link, title and author and replaces anything that fails.")
                .font(.caption).foregroundStyle(Color.inkSecondary)
        }
    }

    private func move(_ source: IndexSet, _ destination: Int, in group: [IssueEntry]) {
        var reordered = group
        reordered.move(fromOffsets: source, toOffset: destination)
        let positions = group.map(\.position).sorted()
        for (entry, position) in zip(reordered, positions) { entry.position = position }
        try? context.save()
    }

    private func delete(_ offsets: IndexSet, in group: [IssueEntry]) {
        for index in offsets { context.delete(group[index]) }
        try? context.save()
    }
}

struct IssueEntryRow: View {
    @Bindable var entry: IssueEntry
    @Environment(\.modelContext) private var context
    @State private var isDrafting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data = entry.previewImage, let image = PlatformImage(data: data) {
                    Image(platformImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.richtext").foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.paper)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.previewTitle ?? entry.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(entry.handle.map { "\(entry.authorName) · @\($0)" } ?? entry.authorName)
                    .font(.caption).foregroundStyle(Color.inkSecondary)
                HStack {
                    TextField("One-line note", text: $entry.note, axis: .vertical).font(.callout).lineLimit(1...3)
                    if ModelAvailability.current.isAvailable && entry.note.isEmpty {
                        Button("Draft note", systemImage: "sparkles") { Task { await draft() } }
                            .labelStyle(.iconOnly)
                            .disabled(isDrafting)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .safeAreaInset(edge: .bottom, spacing: 6) {
            if let flag = entry.flag {
                Label(flag, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(entry.flag == nil ? 0 : 8)
        .overlay {
            if entry.flag != nil { RoundedRectangle(cornerRadius: 12).strokeBorder(.orange, lineWidth: 1.5) }
        }
    }

    private func draft() async {
        isDrafting = true
        defer { isDrafting = false }
        let guid = entry.postGuid
        let snippet = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.guid == guid })).first?.snippet) ?? ""
        if let note = try? await Writer.entryNote(title: entry.title, snippet: snippet) { entry.note = note }
    }
}

struct IssuePreview: View {
    let content: IssueContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(content.heading).font(.title2.bold())
                    if !content.intro.isEmpty { Text(content.intro) }
                    ForEach(Array(content.entries.enumerated()), id: \.offset) { _, entry in
                        Text(rendered(entry)).tint(.scoutBlue)
                    }
                    Divider()
                    MonoLabel("Markdown")
                    Text(IssueRenderer.markdown(content))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: .rect(cornerRadius: 12))
                }
                .padding()
            }
            .background(Color.paper)
            .navigationTitle("Preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("preview.done") }
        }
    }

    /// One Markdown bullet, parsed so its link is tappable.
    private func rendered(_ entry: IssueContent.Entry) -> AttributedString {
        let single = IssueContent(number: content.number, title: content.title, intro: "", entries: [entry])
        let line = IssueRenderer.markdown(single).split(separator: "\n").last.map(String.init) ?? entry.title
        return (try? AttributedString(markdown: "•" + line.dropFirst())) ?? AttributedString(entry.title)
    }
}
