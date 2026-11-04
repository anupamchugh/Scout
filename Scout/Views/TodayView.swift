//
//  TodayView.swift
//  Scout
//

import ScoutKit
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(ScoutModel.self) private var model
    @Query(filter: #Predicate<Decision> { $0.verdictRaw == "shortlist" }) private var shortlisted: [Decision]
    @Query(filter: #Predicate<StoryPick> { $0.verdictRaw == "shortlist" }) private var shortlistedStories: [StoryPick]
    @Query(sort: \Lane.position) private var lanes: [Lane]

    @State private var showsSettings = false
    @State private var showsPackPicker = false
    @State private var showsNewLane = false
    @State private var asking: AskSubject?

    private var shortlistCount: Int { shortlisted.count + shortlistedStories.count }
    private var deckCount: Int { model.mode == .writers ? model.deck.count : model.storyDeck.count }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            header
            Picker("Deck", selection: $model.mode) {
                ForEach(DeckMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("today.mode")

            if deckCount == 0 {
                Spacer()
                if model.isLoading {
                    ProgressView("Reading Medium RSS…").frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView(model.mode == .writers ? "No writers left" : "No stories left",
                                           systemImage: "rectangle.stack",
                                           description: Text("Try a longer window or another lane."))
                }
                Spacer()
            } else if model.mode == .writers {
                SwipeDeck(items: model.deck, onDecide: { model.decide($0, $1) }) { candidate in
                    AuthorCard(candidate: candidate, why: model.whyLines[candidate.authorKey],
                               stats: model.authorStats[candidate.authorKey], onAsk: { asking = .writer(candidate) })
                        .contextMenu {
                            Button("Block \(candidate.name)", systemImage: "hand.raised", role: .destructive) { model.block(candidate) }
                        }
                }
            } else {
                let laneTags = model.activeLane.tags
                let visual = model.activePack.isVisual
                SwipeDeck(items: model.storyDeck, onDecide: { model.decideStory($0, $1) }) { story in
                    StoryCard(story: story, laneTags: laneTags, why: model.storyWhyLines[story.id], imageFirst: visual,
                              avatarURL: model.avatars[story.post.authorKey], onAsk: { asking = .story(story) })
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Color.paper.ignoresSafeArea())
        .task(id: "\(model.activePack.id)|\(model.activeLaneName)|\(model.window.rawValue)") { await model.loadDeck() }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsPackPicker) { PackPickerView() }
        .sheet(isPresented: $showsNewLane) { NewLaneView() }
        .sheet(item: $asking) { AskSheet(subject: $0) }
        .onAppear { showsPackPicker = model.needsPackChoice }
        .task(id: model.deck.first?.id) { if let top = model.deck.first { await model.ensureStats(for: top) } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today").font(.largeTitle.bold()).foregroundStyle(Color.ink)
                laneMenu
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button { showsSettings = true } label: {
                    Text(model.activePack.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityIdentifier("today.packChip")
                .accessibilityHint("Opens settings to switch role pack")
                Text("\(shortlistCount) shortlisted")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.scoutGreen)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glassEffect(.regular.tint(.scoutGreen.opacity(0.15)), in: .capsule)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: shortlistCount)
                    .accessibilityIdentifier("today.shortlistCount")
            }
        }
        .padding(.top, 8)
    }

    /// The lane switcher: a visible capsule listing "All my lanes" and every lane in the pack.
    private var laneMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Lane", selection: $model.activeLaneName) {
                Label(ScoutModel.allLanes, systemImage: "square.stack.3d.up").tag(ScoutModel.allLanes)
                ForEach(lanes.filter { $0.packID == model.activePack.id }) { Text($0.name).tag($0.name) }
            }
            Button("New lane…", systemImage: "plus") { showsNewLane = true }
            Picker("Window", selection: $model.window) {
                ForEach(DeckWindow.allCases) { Text($0.rawValue).tag($0) }
            }
            if !model.suggestedPairs.isEmpty {
                Section("Suggested lanes · tags seen together") {
                    ForEach(model.suggestedPairs, id: \.pair) { entry in
                        Button("\(entry.pair.label) (\(entry.count) posts)", systemImage: "plus") { model.addLane(from: entry.pair) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.isAllLanes ? "square.stack.3d.up" : "line.3.horizontal.decrease")
                Text(model.activeLaneName).lineLimit(1)
                Text("· \(deckCount)").foregroundStyle(Color.inkSecondary).monospacedDigit()
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityIdentifier("today.lanePicker")
        .accessibilityLabel("Lane: \(model.activeLaneName), \(deckCount) cards")
    }
}

/// Make a lane from tags seen this week and from tag pairs that keep appearing together.
struct NewLaneView: View {
    @Environment(ScoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var theme = ""
    @State private var picked: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("What it's about (optional)", text: $theme, axis: .vertical)
                }
                if !model.suggestedPairs.isEmpty {
                    Section {
                        FlowLayout(spacing: 6) {
                            ForEach(model.suggestedPairs, id: \.pair) { entry in
                                tagButton(entry.pair.label, isOn: picked.contains(entry.pair.first) && picked.contains(entry.pair.second)) {
                                    for tag in [entry.pair.first, entry.pair.second] where !picked.contains(tag) { picked.append(tag) }
                                    if name.isEmpty { name = entry.pair.label }
                                }
                            }
                        }
                    } header: { MonoLabel("Suggested pairs") }
                }
                Section {
                    FlowLayout(spacing: 6) {
                        ForEach(model.tagCloud, id: \.tag) { entry in
                            tagButton("\(entry.tag) \(entry.count)", isOn: picked.contains(entry.tag)) {
                                if let index = picked.firstIndex(of: entry.tag) { picked.remove(at: index) } else { picked.append(entry.tag) }
                            }
                        }
                    }
                } header: { MonoLabel("Tags this week") }
            }
            .navigationTitle("New lane")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.addLane(name: name.isEmpty ? picked.prefix(2).joined(separator: " + ") : name, tags: picked, theme: theme)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }

    private func tagButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { FilterCapsuleLabel(title: title, isOn: isOn) }.buttonStyle(.plain)
    }

}
