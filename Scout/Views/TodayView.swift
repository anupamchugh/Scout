//
//  TodayView.swift
//  Scout
//

import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(ScoutModel.self) private var model
    @Query(filter: #Predicate<Decision> { $0.verdictRaw == "shortlist" }) private var shortlisted: [Decision]
    @Query(sort: \Lane.position) private var lanes: [Lane]

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            header
            if model.deck.isEmpty {
                Spacer()
                if model.isLoading {
                    ProgressView("Reading Medium RSS…").frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("No writers left", systemImage: "rectangle.stack",
                                           description: Text("Try a longer window or another lane."))
                }
                Spacer()
            } else {
                SwipeDeck(items: model.deck, onDecide: { model.decide($0, $1) }) { candidate in
                    AuthorCard(candidate: candidate, why: model.whyLines[candidate.authorKey])
                        .contextMenu {
                            Button("Block \(candidate.name)", systemImage: "hand.raised", role: .destructive) { model.block(candidate) }
                        }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Color.paper.ignoresSafeArea())
        .task(id: "\(model.activeLaneName)|\(model.window.rawValue)") { await model.loadDeck() }
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
                } label: {
                    HStack(spacing: 4) {
                        Text("\(model.deck.count) writers · lane: \(model.activeLaneName)")
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
            Text("\(shortlisted.count) shortlisted")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.scoutGreen)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(.regular.tint(.scoutGreen.opacity(0.15)), in: .capsule)
                .contentTransition(.numericText())
                .animation(.snappy, value: shortlisted.count)
                .accessibilityIdentifier("today.shortlistCount")
        }
        .padding(.top, 8)
    }
}
