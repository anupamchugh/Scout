//
//  SearchView.swift
//  Scout
//

import ScoutKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SearchResult: Identifiable, Hashable {
    var id: String { authorKey }
    let authorKey: String
    let name: String
    let handle: String?
    let postTitle: String
    let postCount: Int
    let score: Int
}

struct SearchView: View {
    @Environment(ScoutModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Pitch.imported, order: .reverse) private var pitches: [Pitch]
    @Query private var blocked: [BlockedAuthor]

    @State private var query = ""
    @State private var navigator = Navigator.shared
    @State private var lastSevenDays = true
    @State private var twoPlusPosts = false
    /// The Mac's tag catalog column filters this search through a shared binding.
    private let tagBinding: Binding<String?>?
    @State private var ownTag: String?
    private var tag: String? {
        get { tagBinding?.wrappedValue ?? ownTag }
        nonmutating set { if let tagBinding { tagBinding.wrappedValue = newValue } else { ownTag = newValue } }
    }
    @State private var includeBlocked = false
    @State private var minMatchingTags = 0
    @State private var minLanes = 0
    @State private var writer: String?
    @State private var tagOptions: [String] = []
    @State private var writerOptions: [(key: String, name: String)] = []
    @State private var results: [SearchResult] = []
    @State private var spotlightHits: [String] = []
    @State private var importing = false
    @State private var pitchStatus: String?

    init(tag: Binding<String?>? = nil) {
        tagBinding = tag
    }

    private var filterKey: String {
        "\(query)|\(lastSevenDays)|\(twoPlusPosts)|\(tag ?? "")|\(includeBlocked)|\(minMatchingTags)|\(minLanes)|\(writer ?? "")|\(model.activeLaneName)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filters.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                PotentialTagsSection(laneTags: model.activeLane.tags, picked: tag.map { [$0] } ?? []) { picked in
                    tag = tag == picked ? nil : picked
                }
                Section {
                    NavigationLink {
                        TagCatalogView { picked in tag = picked }
                    } label: {
                        Label("Every tag Scout has seen", systemImage: "tag")
                    }
                    .accessibilityIdentifier("search.catalog")
                }
                Section {
                    ForEach(results) { result in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.name).font(.headline).foregroundStyle(Color.ink)
                                Text(result.postTitle).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(2)
                                Text([result.handle.map { "@\($0)" }, result.postCount == 1 ? "1 post" : "\(result.postCount) posts"]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Color.inkSecondary)
                            }
                            Spacer()
                            Text("\(result.score)")
                                .font(.title3.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.scoutGreen)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    MonoLabel("Sorted by match · code decides the order")
                }
                if !spotlightHits.isEmpty {
                    Section { ForEach(spotlightHits, id: \.self) { Text($0) } } header: { MonoLabel("From Spotlight · shortlisted") }
                }
                Section { pitchDropZone.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                if !pitches.isEmpty {
                    Section {
                        ForEach(pitches) { pitch in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pitch.title).font(.headline)
                                Text(verbatim: pitch.summary).font(.subheadline).foregroundStyle(Color.inkSecondary)
                                if let handle = pitch.handle {
                                    Text(pitch.linkedAuthorKey == nil ? "@\(handle) · not seen in feeds yet" : "@\(handle) · matched to a known writer")
                                        .font(.caption).foregroundStyle(Color.scoutBlue)
                                }
                            }
                        }
                        .onDelete { $0.map { pitches[$0] }.forEach(context.delete) }
                    } header: { MonoLabel("Pitches") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Ask in your own words")
            .task(id: navigator.pendingSearch) {
                if let term = navigator.pendingSearch {
                    navigator.pendingSearch = nil
                    query = term
                }
            }
            .task(id: filterKey) { await search() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
                if case .success(let url) = result { Task { await importPitch(url) } }
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterCapsule(title: "Last 7 days", isOn: $lastSevenDays)
                FilterCapsule(title: "2+ posts", isOn: $twoPlusPosts)
                Menu {
                    Button("Any tag") { tag = nil }
                    ForEach(tagOptions, id: \.self) { slug in Button(slug) { tag = slug } }
                } label: {
                    FilterCapsuleLabel(title: tag ?? "Tags", isOn: tag != nil)
                }
                Menu {
                    Picker("Matching lane tags", selection: $minMatchingTags) {
                        Text("Any").tag(0)
                        ForEach(1...3, id: \.self) { Text("\($0)+ lane tags").tag($0) }
                    }
                } label: {
                    FilterCapsuleLabel(title: minMatchingTags == 0 ? "Lane tags" : "\(minMatchingTags)+ lane tags", isOn: minMatchingTags > 0)
                }
                Menu {
                    Picker("Surfaced by", selection: $minLanes) {
                        Text("Any").tag(0)
                        ForEach(1...3, id: \.self) { Text("\($0)+ lanes").tag($0) }
                    }
                } label: {
                    FilterCapsuleLabel(title: minLanes == 0 ? "Lanes" : "Surfaced by \(minLanes)+", isOn: minLanes > 0)
                }
                Menu {
                    Button("Any writer") { writer = nil }
                    ForEach(writerOptions, id: \.key) { option in Button(option.name) { writer = option.key } }
                } label: {
                    FilterCapsuleLabel(title: writerOptions.first { $0.key == writer }?.name ?? "Writer", isOn: writer != nil)
                }
                FilterCapsule(title: includeBlocked ? "Including blocked" : "Not blocked", isOn: .init(
                    get: { !includeBlocked }, set: { includeBlocked = !$0 }))
            }
            .padding(.vertical, 4)
        }
    }

    private var pitchDropZone: some View {
        Button { importing = true } label: {
            VStack(spacing: 6) {
                Image(systemName: "doc.viewfinder").font(.title2)
                Text("Import a pitch").font(.headline)
                Text(pitchStatus ?? "PDF or screenshot · read on device").font(.caption).foregroundStyle(Color.inkSecondary)
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.inkSecondary.opacity(0.5),
                                                                         style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await importPitch(url) }
            return true
        }
    }

    // MARK: Search

    /// Filters with SwiftData predicates, then orders by a score computed in code: the lane match,
    /// blended with on-device similarity to the question when there is one.
    private func search() async {
        let now = Date.now
        let cutoff = lastSevenDays ? now.addingTimeInterval(-7 * 86_400) : .distantPast
        var descriptor = FetchDescriptor<StoredPost>(predicate: #Predicate { $0.published >= cutoff },
                                                     sortBy: [SortDescriptor(\.published, order: .reverse)])
        if let tag {
            descriptor.predicate = #Predicate { $0.published >= cutoff && ($0.categories.contains(tag) || $0.foundUnder.contains(tag)) }
        }
        let allPosts = Matching.unifyAuthors(((try? context.fetch(descriptor)) ?? []).map(ScoutModel.record))
        let blockedKeys = includeBlocked ? Set<String>() : Set(blocked.map(\.authorKey))
        let lane = model.activeLane
        let lanes = model.laneSpecs
        if tag == nil {
            // The catalog keeps every tag ever seen; fall back to this window's tags before it fills.
            let catalog = TagCatalogStore.all(context, limit: 60).map(\.tag)
            tagOptions = catalog.isEmpty ? TagCooccurrence.tagCounts(allPosts).prefix(40).map(\.tag) : catalog
        }
        writerOptions = Matching.candidates(from: allPosts, lane: lane, semantic: [:], excluding: blockedKeys, now: now,
                                            window: now.timeIntervalSince(cutoff)).prefix(30).map { ($0.authorKey, $0.name) }
        let posts = allPosts.filter { post in
            !blockedKeys.contains(post.authorKey)
                && post.topics.intersection(lane.tags).count >= minMatchingTags
                && Matching.lanesSurfacing(post, lanes: lanes) >= minLanes
                && (writer.map { post.authorKey == $0 } ?? true)
        }
        let byAuthor = Dictionary(grouping: posts, by: \.authorKey)
            .filter { !twoPlusPosts || $0.value.count >= 2 }
        let texts = byAuthor.mapValues { $0.map { "\($0.title). \($0.snippet)" }.joined(separator: " ") }

        let laneSimilarity = await Embedder.similarities(texts, to: lane.theme)
        let querySimilarity = query.isEmpty ? [:] : await Embedder.similarities(texts, to: query)
        guard !Task.isCancelled else { return }
        let words = query.lowercased().split(separator: " ").filter { $0.count > 2 }

        results = Matching.candidates(from: byAuthor.values.flatMap { $0 }, lane: lane, semantic: laneSimilarity,
                                      excluding: [], now: now, window: now.timeIntervalSince(cutoff))
            .compactMap { candidate -> SearchResult? in
                var score = candidate.score
                if !query.isEmpty {
                    let similarity = querySimilarity[candidate.authorKey] ?? 0
                    let mentions = words.contains { texts[candidate.authorKey]?.lowercased().contains($0) ?? false }
                    guard mentions || similarity >= 0.45 else { return nil }
                    score = Int((0.6 * similarity * 100 + 0.4 * Double(candidate.score)).rounded())
                }
                return SearchResult(authorKey: candidate.authorKey, name: candidate.name, handle: candidate.handle,
                                    postTitle: candidate.bestPost.title, postCount: candidate.posts.count, score: score)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }

        spotlightHits = query.isEmpty ? [] : await spotlightTitles(for: query)
    }

    private func spotlightTitles(for text: String) async -> [String] {
        let identifiers = await SpotlightIndex.search(text)
        let guids = identifiers.compactMap { $0.hasPrefix("post:") ? String($0.dropFirst(5)) : nil }
        let posts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { guids.contains($0.guid) }))) ?? []
        return posts.map { "\($0.title) · \($0.authorName)" }
    }

    // MARK: Pitches

    private func importPitch(_ url: URL) async {
        pitchStatus = String(localized: "Reading on device…")
        do {
            let facts = try await PitchReader.read(url)
            var summary = String(facts.text.prefix(180))
            if ModelAvailability.current.isAvailable, let written = try? await Writer.pitchSummary(facts.text) {
                summary = written
            }
            let handle = facts.handle
            let known = handle.flatMap { key in
                (try? context.fetchCount(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.authorKey == key }))) ?? 0 > 0 ? key : nil
            }
            context.insert(Pitch(title: facts.title, summary: summary, text: facts.text, handle: handle, linkedAuthorKey: known))
            try? context.save()
            pitchStatus = nil
        } catch {
            pitchStatus = String(localized: "Couldn't read text from that file.")
        }
    }
}

struct FilterCapsule: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: { FilterCapsuleLabel(title: title, isOn: isOn) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct FilterCapsuleLabel: View {
    let title: String
    let isOn: Bool

    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.white : Color.ink)
            .background(isOn ? Color.ink : Color.card, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.hairline))
    }
}
