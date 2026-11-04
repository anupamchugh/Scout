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
                               stats: model.authorStats[candidate.authorKey])
                        .contextMenu {
                            Button("Block \(candidate.name)", systemImage: "hand.raised", role: .destructive) { model.block(candidate) }
                        }
                }
            } else {
                let laneTags = model.activeLane.tags
                let visual = model.activePack.isVisual
                SwipeDeck(items: model.storyDeck, onDecide: { model.decideStory($0, $1) }) { story in
                    StoryCard(story: story, laneTags: laneTags, why: model.storyWhyLines[story.id], imageFirst: visual)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Color.paper.ignoresSafeArea())
        .task(id: "\(model.activePack.id)|\(model.activeLaneName)|\(model.window.rawValue)") { await model.loadDeck() }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsPackPicker) { PackPickerView() }
        .onAppear { showsPackPicker = model.needsPackChoice }
        .task(id: model.deck.first?.id) { if let top = model.deck.first { await model.ensureStats(for: top) } }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(.largeTitle.bold()).foregroundStyle(Color.ink)
                Menu {
                    Picker("Lane", selection: $model.activeLaneName) {
                        ForEach(lanes) { Text($0.name).tag($0.name) }
                    }
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
                    HStack(spacing: 4) {
                        Text("\(deckCount) \(model.mode == .writers ? "writers" : "stories") · lane: \(model.activeLaneName)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                }
                .accessibilityIdentifier("today.lanePicker")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button { showsSettings = true } label: {
                        Text(model.activePack.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityIdentifier("today.packChip")
                    .accessibilityHint("Opens settings to switch role pack")
                }
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
}
