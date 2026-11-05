//
//  HackerNewsViews.swift
//  Scout
//

import FoundationModels
import ScoutKit
import SwiftData
import SwiftUI

/// A Hacker News poster in Writers mode. Every number comes from `HNAuthorStats` (the official API, computed in code).
struct HNPersonCard: View {
    let candidate: AuthorCandidate
    let stats: HNAuthorStats?
    let why: String?
    var onAsk: (() -> Void)?
    var onThreadBrief: ((Int) -> Void)?

    private var user: String { String(candidate.authorKey.dropFirst(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(String(user.prefix(2)).uppercased())
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.orange.gradient, in: .rect(cornerRadius: 16))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if let onAsk { AskButton(action: onAsk) }
                VStack(spacing: 0) {
                    Text("\(candidate.score)").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Color.scoutGreen)
                    MonoLabel("match")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(user).font(.title2.weight(.bold)).foregroundStyle(Color.ink)
                Text(stats.map { "Hacker News · karma \($0.karma.formatted()) · joined \($0.joined.formatted(.dateTime.year()))" } ?? "Hacker News")
                    .font(.callout).foregroundStyle(Color.inkSecondary)
            }
            if let about = stats?.about, !about.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("About, from their profile")
                    Text(about).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(3)
                }
            }
            if let stats {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        tile(stats.submissionsPerWeek.formatted(.number.precision(.fractionLength(1))), "posts a week")
                        tile("\(stats.showHN)", "Show HNs")
                        tile(stats.medianPoints.map(String.init) ?? "—", "median points")
                    }
                }
                if !stats.topDomains.isEmpty {
                    MonoLabel("Links most to")
                    FlowLayout { ForEach(stats.topDomains, id: \.domain) { TagChip(text: "\($0.domain) · \($0.count)") } }
                }
                if !stats.titleWords.isEmpty {
                    FlowLayout { ForEach(stats.titleWords, id: \.word) { TagChip(text: $0.word) } }
                }
            } else {
                ProgressView("Reading their Hacker News history…").font(.caption)
            }
            Spacer(minLength: 0)
            if let why {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Why this builder · on-device model", color: .scoutGreen)
                    Text(verbatim: why).font(.callout).foregroundStyle(Color.ink)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.scoutGreen.opacity(0.09), in: .rect(cornerRadius: 16))
            }
            if let id = candidate.bestPost.hnID, let onThreadBrief {
                Button("Thread brief", systemImage: "text.bubble") { onThreadBrief(id) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("hn.threadBrief")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.card, in: .rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.card")
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Color.ink)
            Text(label).font(.caption2).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.paper, in: .rect(cornerRadius: 12))
    }
}

/// Feedloom's Thread brief: the model writes the summary, arguments and tags; title, points and counts come from the API.
struct ThreadBriefView: View {
    let storyID: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var brief: ThreadBrief?
    @State private var problem: String?
    @State private var rating = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch ThreadBriefAvailability.current(writing: "thread briefs") {
                    case .unavailable(let reason):
                        Label(reason, systemImage: "exclamationmark.circle").foregroundStyle(Color.inkSecondary)
                    case .available:
                        if let brief {
                            Text(brief.storyTitle).font(.title3.bold())
                            Text(brief.facts).font(.caption.monospaced()).foregroundStyle(Color.inkSecondary)
                            Text(verbatim: brief.summary)
                            MonoLabel("Arguments in the comments")
                            ForEach(brief.arguments, id: \.self) { Text(verbatim: "• \($0)").font(.callout) }
                            FlowLayout { ForEach(brief.tags, id: \.self) { TagChip(text: $0) } }
                            Text(ThreadBrief.provenance).font(.caption2).foregroundStyle(Color.inkSecondary)
                            HStack {
                                Spacer()
                                Button { rate(1) } label: { Image(systemName: rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup") }
                                    .accessibilityLabel("Good brief")
                                Button { rate(-1) } label: { Image(systemName: rating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
                                    .accessibilityLabel("Bad brief")
                            }
                            .foregroundStyle(Color.scoutGreen)
                        } else if let problem {
                            Text(problem).foregroundStyle(Color.inkSecondary)
                        } else {
                            HStack { ProgressView(); Text("Reading the thread on device…").foregroundStyle(Color.inkSecondary) }
                        }
                    }
                    Link("Open the thread on Hacker News", destination: HackerNewsLink.permalink(forItem: storyID)).font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color.paper)
            .navigationTitle("Thread brief")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
    }

    private func load() async {
        guard case .available = ThreadBriefAvailability.current(writing: "thread briefs"), brief == nil else { return }
        let started = Date.now
        do {
            let service = ThreadBriefService(reader: try HackerNewsReader(transport: SessionTransport()),
                                             responder: FoundationThreadBriefResponder())
            let made = try await service.brief(storyID: storyID)
            brief = made
            context.insert(ModelRun(role: "threadBrief", pack: Writer.pack.id, instructionsVersion: made.recipe, input: made.storyTitle,
                                    subjectID: "hn:\(storyID)", output: ([made.summary] + made.arguments).joined(separator: "\n"),
                                    rejection: nil, latency: Date.now.timeIntervalSince(started)))
        } catch ThreadBriefError.noDiscussion {
            problem = String(localized: "There's no discussion on this story yet.")
        } catch {
            problem = String(localized: "Couldn't read this thread. Try again in a minute.")
        }
    }

    private func rate(_ value: Int) {
        rating = rating == value ? 0 : value
        let subject = "hn:\(storyID)"
        if let run = try? context.fetch(FetchDescriptor<ModelRun>(predicate: #Predicate { $0.subjectID == subject },
                                                                  sortBy: [SortDescriptor(\.date, order: .reverse)])).first {
            run.rating = rating
        }
    }
}
