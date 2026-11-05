//
//  TagCatalogView.swift
//  Scout
//
//  Every Medium tag Scout has seen on a fetched post, and the "potential tags" that keep turning up
//  beside a lane's own tags. Counts come from code; exploring a tag reads its public RSS feed once.
//

import ScoutKit
import SwiftData
import SwiftUI

/// Potential tags for a set of lane tags, as chips. Tapping a chip calls `onPick`; the arrow explores it.
struct PotentialTagsSection: View {
    @Environment(ScoutModel.self) private var model
    @Environment(\.modelContext) private var context
    let laneTags: Set<String>
    var picked: Set<String> = []
    let onPick: (String) -> Void

    @State private var potential: [TagCatalog.Potential] = []
    @State private var exploring: String?

    var body: some View {
        Section {
            if potential.isEmpty {
                Text("No tags seen beside this lane yet. Refresh Today or explore a tag.")
                    .font(.footnote).foregroundStyle(Color.inkSecondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(potential, id: \.tag) { entry in
                        HStack(spacing: 2) {
                            Button { onPick(entry.tag) } label: {
                                FilterCapsuleLabel(title: "\(entry.tag) \(entry.together)", isOn: picked.contains(entry.tag))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("\(entry.tag), seen beside your lane on \(entry.together) posts"))
                            Button {
                                Task { await explore(entry.tag) }
                            } label: {
                                Image(systemName: exploring == entry.tag ? "hourglass" : "arrow.down.circle")
                                    .foregroundStyle(Color.scoutBlue)
                            }
                            .buttonStyle(.plain)
                            .disabled(exploring != nil)
                            .accessibilityLabel(Text("Explore \(entry.tag)"))
                        }
                    }
                }
            }
        } header: {
            MonoLabel("Potential tags · seen beside your lane tags")
        } footer: {
            Text("The number is how many fetched posts carried that tag beside one of your lane's tags. The arrow reads that tag's feed to find more.")
        }
        .task(id: "\(laneTags.sorted())|\(model.catalogVersion)") {
            potential = TagCatalogStore.potential(for: laneTags, in: context)
        }
    }

    private func explore(_ tag: String) async {
        exploring = tag
        defer { exploring = nil }
        await model.exploreTag(tag)
    }
}

/// The whole catalog: every tag seen, with how many posts carried it.
struct TagCatalogView: View {
    @Environment(ScoutModel.self) private var model
    @Environment(\.modelContext) private var context
    let onPick: (String) -> Void

    @State private var filter = ""
    @State private var records: [(tag: String, count: Int)] = []
    @State private var newTag = ""
    @State private var status: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("A Medium tag, e.g. engineering-management", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await explore() } }
                        .accessibilityIdentifier("catalog.explore.field")
                    Button("Explore") { Task { await explore() } }
                        .disabled(slug.isEmpty)
                        .accessibilityIdentifier("catalog.explore")
                }
                if let status { Text(status).font(.footnote).foregroundStyle(Color.inkSecondary) }
            } footer: {
                Text("Reads medium.com/feed/tag/… once. Every tag on those posts joins the catalog.")
            }
            Section {
                ForEach(shown, id: \.tag) { entry in
                    Button { onPick(entry.tag) } label: {
                        HStack {
                            Text(verbatim: entry.tag).foregroundStyle(Color.ink)
                            Spacer()
                            Text(entry.count, format: .number).monospacedDigit().foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
            } header: {
                MonoLabel("\(records.count) tags seen · posts carrying each")
            }
        }
        .searchable(text: $filter, prompt: "Filter tags")
        .navigationTitle("Tag catalog")
        .task(id: model.catalogVersion) {
            records = TagCatalogStore.all(context, limit: 2_000).map { ($0.tag, $0.postCount) }
        }
    }

    private var slug: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private var shown: [(tag: String, count: Int)] {
        filter.isEmpty ? records : records.filter { $0.tag.contains(filter.lowercased()) }
    }

    private func explore() async {
        let tag = slug
        guard !tag.isEmpty else { return }
        status = String(localized: "Reading the \(tag) feed…")
        let inserted = await model.exploreTag(tag)
        status = String(localized: "\(inserted) new posts from \(tag).")
        newTag = ""
    }
}
