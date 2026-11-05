//
//  ShortlistView.swift
//  Scout
//

import ScoutKit
import SwiftData
import SwiftUI

struct ShortlistView: View {
    @Environment(ScoutModel.self) private var model
    @Query(sort: \Decision.decided, order: .reverse) private var decisions: [Decision]
    @Query(sort: \IssueDraft.created, order: .reverse) private var issues: [IssueDraft]
    @Query(filter: #Predicate<StoryPick> { $0.verdictRaw == "shortlist" }, sort: \StoryPick.decided, order: .reverse)
    private var stories: [StoryPick]

    @State private var showsIssue = false

    private var shortlisted: [Decision] { decisions.filter { $0.verdict == .shortlist } }

    private var rows: [ShortlistRow] {
        shortlisted.map { ShortlistRow(name: $0.authorName, handle: $0.handle, lane: $0.lane,
                                       postTitle: $0.bestPostTitle, postURL: $0.bestPostLink, note: $0.note) }
            + stories.map { ShortlistRow(name: $0.authorName, handle: $0.handle, lane: "\($0.lane) · stories",
                                         postTitle: $0.title, postURL: $0.link, note: "") }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Dictionary(grouping: shortlisted, by: \.lane).sorted(by: { $0.key < $1.key }), id: \.key) { lane, group in
                    Section { ForEach(group) { ShortlistRowView(decision: $0) } } header: { MonoLabel(lane) }
                }
                if !stories.isEmpty {
                    Section {
                        ForEach(stories) { StoryPickRow(pick: $0) }
                    } header: { MonoLabel("Stories") }
                }
                if let issue = issues.first {
                    Section {
                        NavigationLink {
                            IssueEditorView(issue: issue)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title).font(.headline).foregroundStyle(Color.ink)
                                Text(issue.entries.count == 1 ? "1 post" : "\(issue.entries.count) posts")
                                    .font(.subheadline).foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .accessibilityIdentifier("shortlist.issue")
                    } header: {
                        MonoLabel("\(issue.title) · next issue")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .overlay {
                if shortlisted.isEmpty && stories.isEmpty && (issues.first?.entries.isEmpty ?? true) {
                    ContentUnavailableView("Nobody shortlisted yet", systemImage: "checkmark.circle",
                                           description: Text("Swipe right on a writer in Today."))
                }
            }
            .navigationTitle("Shortlist")
            .navigationDestination(isPresented: $showsIssue) {
                if let issue = issues.first { IssueEditorView(issue: issue) }
            }
            .toolbar {
                if !issues.isEmpty {
                    ToolbarItem {
                        Button("Issue", systemImage: "newspaper") { showsIssue = true }
                            .accessibilityIdentifier("shortlist.openIssue")
                    }
                }
                ToolbarItem {
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        ShareLink("Markdown", item: ShortlistMarkdownExport(rows: rows),
                                  preview: SharePreview("Shortlist.md"))
                        ShareLink("CSV", item: ShortlistCSVExport(rows: rows), preview: SharePreview("Shortlist.csv"))
                    }
                    .disabled(rows.isEmpty)
                }
            }
        }
    }
}

struct ShortlistRowView: View {
    @Bindable var decision: Decision
    @Environment(ScoutModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var isDrafting = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(decision.authorName).font(.headline).foregroundStyle(Color.ink)
                if let handle = decision.handle {
                    Text("@\(handle)").font(.subheadline).foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Text("\(decision.score)").font(.subheadline.monospacedDigit()).foregroundStyle(Color.scoutGreen)
            }
            Text(decision.bestPostTitle).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(2)

            ZStack(alignment: .topLeading) {
                TextField("Outreach note", text: $decision.note, axis: .vertical)
                    .font(.callout)
                    .lineLimit(2...10)
                    .padding(10)
                    .background(Color.paper, in: .rect(cornerRadius: 12))
                if isDrafting { ProgressView().padding(10).frame(maxWidth: .infinity, alignment: .trailing) }
            }

            HStack(spacing: 10) {
                Button(copied ? "Copied" : "Copy note", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    Pasteboard.copy(decision.note + "\n\n" + decision.bestPostLink)
                    copied = true
                }
                .disabled(decision.note.isEmpty)
                Button("Open post", systemImage: "safari") {
                    if let url = URL(string: decision.bestPostLink) { openURL(url) }
                }
                Spacer()
                Button("Draft", systemImage: "sparkles") { Task { await draft() } }
                    .labelStyle(.iconOnly)
                    .disabled(isDrafting)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
        .swipeActions {
            Button("Remove", systemImage: "arrow.uturn.backward", role: .destructive) { model.undo(decision) }
        }
        .task(id: decision.authorKey) { if decision.note.isEmpty { await draft() } }
    }

    private func draft() async {
        isDrafting = true
        defer { isDrafting = false }
        if let note = await model.draftNote(for: decision) {
            decision.note = note
            copied = false
        }
    }
}

struct StoryPickRow: View {
    let pick: StoryPick
    @Environment(ScoutModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Query private var writerDecisions: [Decision]

    init(pick: StoryPick) {
        self.pick = pick
        let key = pick.authorKey
        _writerDecisions = Query(filter: #Predicate<Decision> { $0.authorKey == key })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pick.title).font(.headline).foregroundStyle(Color.ink).lineLimit(3)
            Text(pick.handle.map { "\(pick.authorName) · @\($0)" } ?? pick.authorName)
                .font(.subheadline).foregroundStyle(Color.inkSecondary)
            FlowLayout { ForEach(pick.tags, id: \.self) { TagChip(text: $0) } }
            HStack(spacing: 10) {
                Button("Open post", systemImage: "safari") { if let url = URL(string: pick.link) { openURL(url) } }
                Button(writerDecisions.isEmpty ? "Shortlist writer" : "Writer shortlisted",
                       systemImage: writerDecisions.isEmpty ? "person.badge.plus" : "checkmark") { model.shortlistWriter(of: pick) }
                    .disabled(!writerDecisions.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
        .swipeActions {
            Button("Remove", systemImage: "arrow.uturn.backward", role: .destructive) { model.undoStory(pick) }
        }
    }
}
