//
//  NewTopicLaneView.swift
//  Scout
//
//  Type any topic in plain words. Apple Intelligence suggests tag names; Scout checks each one against
//  Medium's public feed, adds tags it already knows that mean something close, and builds a lane from
//  the tags that are real. The model only guesses words; code decides which become the lane.
//

import ScoutKit
import SwiftData
import SwiftUI

struct NewTopicLaneView: View {
    @Environment(ScoutModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var topic = ""
    @State private var name = ""
    @State private var finding = false
    @State private var suggested: Set<String> = []
    @State private var checked: [TopicTags.Checked] = []
    @State private var nearby: [String] = []
    @State private var picked: [String] = []
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apple tech, blogging, engineering management…", text: $topic)
                        .onSubmit { Task { await find() } }
                        .accessibilityIdentifier("topic.field")
                    Button(finding ? "Checking Medium…" : "Find tags", systemImage: "sparkle.magnifyingglass") { Task { await find() } }
                        .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty || finding)
                        .accessibilityIdentifier("topic.find")
                } footer: {
                    Text("Apple Intelligence suggests tag names on this device. Scout reads each tag's Medium feed and keeps only tags that have posts.")
                }
                if let note { Section { Text(note).font(.footnote).foregroundStyle(Color.inkSecondary) } }

                if !checked.isEmpty {
                    Section {
                        ForEach(checked, id: \.tag) { entry in
                            tagRow(entry.tag, detail: detail(for: entry), enabled: entry.isLive)
                        }
                    } header: { MonoLabel("Checked on Medium") }
                }
                if !nearby.isEmpty {
                    Section {
                        ForEach(nearby, id: \.self) { tag in
                            tagRow(tag, detail: Text("Already in your catalog, close in meaning"), enabled: true)
                        }
                    } header: { MonoLabel("Tags Scout already knows") }
                }
                if !checked.isEmpty {
                    Section {
                        TextField("Lane name", text: $name).accessibilityIdentifier("topic.name")
                    }
                }
            }
            .navigationTitle("New topic")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let lane = name.trimmingCharacters(in: .whitespaces)
                        model.addLane(name: lane.isEmpty ? topic : lane, tags: picked, theme: topic)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                    .accessibilityIdentifier("topic.add")
                }
            }
        }
    }

    private func detail(for entry: TopicTags.Checked) -> Text {
        guard entry.isLive else { return Text("No posts on Medium under this tag") }
        let posts = Text("^[\(entry.posts) post](inflect: true) now")
        return suggested.contains(entry.tag) ? Text("Suggested by Apple Intelligence · \(posts)") : Text("From your words · \(posts)")
    }

    private func tagRow(_ tag: String, detail: Text, enabled: Bool) -> some View {
        Button {
            if let index = picked.firstIndex(of: tag) { picked.remove(at: index) } else { picked.append(tag) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tag).foregroundStyle(enabled ? Color.ink : Color.inkSecondary)
                    detail.font(.caption).foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                if picked.contains(tag) { Image(systemName: "checkmark").foregroundStyle(Color.scoutGreen) }
            }
        }
        .disabled(!enabled)
        .accessibilityAddTraits(picked.contains(tag) ? .isSelected : [])
    }

    private func find() async {
        let text = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        finding = true
        defer { finding = false }
        note = nil
        var guesses: [String] = []
        if ModelAvailability.current.isAvailable {
            do { guesses = try await Writer.tagGuesses(for: text) } catch { note = WriterCopy.message(for: error) }
        } else {
            note = String(localized: "Apple Intelligence isn't available, so Scout checked the words of your topic only.")
        }
        let candidates = TopicTags.candidates(topic: text, guesses: guesses)
        suggested = Set(guesses.compactMap(TopicTags.slug))
        checked = await model.checkTags(candidates)
            .sorted { $0.posts != $1.posts ? $0.posts > $1.posts : $0.tag < $1.tag }
        let live = Set(checked.filter(\.isLive).map(\.tag))
        let known = TagCatalogStore.all(context, limit: 600).map(\.tag).filter { !live.contains($0) && !candidates.contains($0) }
        nearby = TopicTags.nearby(text, among: known, limit: 8).map(\.tag)
        picked = TopicTags.laneTags(checked: checked, nearby: [], limit: 6)
        if name.isEmpty { name = text.prefix(1).uppercased() + text.dropFirst() }
        if live.isEmpty { note = String(localized: "None of those tags has posts on Medium. Try other words.") }
    }
}
