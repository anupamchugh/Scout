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
    @State private var isDraftingIntro = false
    @State private var showsPreview = false
    @State private var copied = false

    private var content: IssueContent {
        IssueContent(number: issue.number, title: issue.title, intro: issue.intro,
                     entries: issue.orderedEntries.map {
                         .init(title: $0.title, url: $0.link, author: $0.authorName, handle: $0.handle, note: $0.note)
                     })
    }

    var body: some View {
        List {
            Section {
                TextField("Issue title", text: $issue.title).font(.title3.weight(.semibold))
                Stepper("Issue \(issue.number)", value: $issue.number, in: 1...999)
            } header: { MonoLabel("Issue") }

            Section {
                TextField("A short intro for readers", text: $issue.intro, axis: .vertical).lineLimit(2...8)
                if ModelAvailability.current.isAvailable {
                    Button(isDraftingIntro ? "Drafting…" : "Draft intro on device", systemImage: "sparkles") {
                        Task { await draftIntro() }
                    }
                    .disabled(isDraftingIntro || issue.entries.isEmpty)
                }
            } header: { MonoLabel("Intro") }

            Section {
                ForEach(issue.orderedEntries) { IssueEntryRow(entry: $0) }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
            } header: {
                MonoLabel("Entries · drag to reorder")
            } footer: {
                if issue.entries.isEmpty { Text("Swipe a writer up in Today to add their best post here.") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle(issue.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem { EditButton() }
            ToolbarItem {
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button(copied ? "Copied" : "Copy Markdown", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = IssueRenderer.markdown(content)
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

    private func move(_ source: IndexSet, _ destination: Int) {
        var entries = issue.orderedEntries
        entries.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in entries.enumerated() { entry.position = index }
        try? context.save()
    }

    private func delete(_ offsets: IndexSet) {
        let entries = issue.orderedEntries
        for index in offsets { context.delete(entries[index]) }
        try? context.save()
    }

    private func draftIntro() async {
        isDraftingIntro = true
        defer { isDraftingIntro = false }
        let entries = issue.orderedEntries.map { (title: $0.title, note: $0.note) }
        if let intro = try? await Writer.issueIntro(title: issue.title, entries: entries) { issue.intro = intro }
    }
}

struct IssueEntryRow: View {
    @Bindable var entry: IssueEntry
    @Environment(\.modelContext) private var context
    @State private var isDrafting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data = entry.previewImage, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
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
            .navigationBarTitleDisplayMode(.inline)
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
