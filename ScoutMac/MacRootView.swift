//
//  MacRootView.swift
//  Scout (macOS)
//
//  Three columns: lanes and the desk (sidebar), a ranked list (content), the selected card (detail).
//  The list order, ranks and scores come straight from ScoutModel's ranking code; the model only writes
//  the "why" line shown in the detail.
//

import ScoutKit
import SwiftData
import SwiftUI

enum MacSection: Hashable {
    case lane(String)
    case shortlist
    case issue
    case search
}

/// A sheet the window can show; one at a time.
enum MacSheet: Identifiable {
    case newLane, newTopic, addSite, packPicker
    case ask(AskSubject)
    case read(ReaderItem)
    case threadBrief(Int)

    var id: String {
        switch self {
        case .newLane: "newLane"
        case .newTopic: "newTopic"
        case .addSite: "addSite"
        case .packPicker: "packPicker"
        case .ask(let subject): "ask:\(subject.id)"
        case .read(let item): "read:\(item.id)"
        case .threadBrief(let id): "thread:\(id)"
        }
    }
}

struct MacRootView: View {
    @Environment(ScoutModel.self) private var model
    @State private var navigator = Navigator.shared
    @State private var section: MacSection? = MacRootView.startSection
    @State private var selection: String?
    @State private var sheet: MacSheet?
    @State private var searchTag: String?
    @State private var refreshes = 0
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            MacSidebar(section: $section, sheet: $sheet)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            detail
        }
        .focusedSceneValue(\.macSection, $section)
        .sheet(item: $sheet) { sheet in
            sheetView(sheet).frame(minWidth: 540, idealWidth: 600, minHeight: 520, idealHeight: 640)
        }
        .onAppear {
            if model.needsPackChoice { sheet = .packPicker }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openSettings") { openSettings() }
            #endif
        }
        .onChange(of: section) { _, section in
            if case .lane(let name) = section, model.activeLaneName != name {
                model.activeLaneName = name
                selection = nil
            }
        }
        .onChange(of: model.activeLaneName) { _, name in
            if case .lane = section { section = .lane(name) }
        }
        // App Intents ("Show my shortlist") pick a tab; the Mac maps it to a section.
        .onChange(of: navigator.tab) { _, tab in
            switch tab {
            case .today: section = .lane(model.activeLaneName)
            case .shortlist: section = .shortlist
            case .search: section = .search
            }
        }
        .task(id: "\(model.activePack.id)|\(model.activeLaneName)|\(model.window.rawValue)|\(refreshes)") {
            await model.loadDeck()
            #if DEBUG
            model.makeDemoDecisions()
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section ?? .lane(model.activeLaneName) {
        case .lane:
            MacDeckList(selection: $selection, refresh: { refreshes += 1 })
        case .shortlist:
            ShortlistView()
        case .issue:
            MacIssueColumn()
        case .search:
            SearchView(tag: $searchTag)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .lane(model.activeLaneName) {
        case .lane:
            MacCardDetail(selection: $selection, sheet: $sheet)
        case .shortlist:
            MacIssueColumn()
        case .issue:
            MacIssuePreview()
        case .search:
            NavigationStack {
                TagCatalogView { picked in searchTag = searchTag == picked ? nil : picked }
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: MacSheet) -> some View {
        switch sheet {
        case .newLane: NewLaneView()
        case .newTopic: NewTopicLaneView()
        case .addSite: AddSiteView()
        case .packPicker: PackPickerView()
        case .ask(let subject): AskSheet(subject: subject)
        case .read(let item): ReaderView(guid: item.id, askSubject: item.subject)
        case .threadBrief(let id): ThreadBriefView(storyID: id)
        }
    }

    /// -section shortlist|issue|search opens on that section (debug builds, for screenshots).
    private static var startSection: MacSection {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-section"), i + 1 < args.count {
            switch args[i + 1] {
            case "shortlist": return .shortlist
            case "issue": return .issue
            case "search": return .search
            default: break
            }
        }
        if let i = args.firstIndex(of: "-lane"), i + 1 < args.count { return .lane(args[i + 1]) }
        #endif
        return .lane(ScoutModel.allLanes)
    }
}

// MARK: Sidebar

struct MacSidebar: View {
    @Environment(ScoutModel.self) private var model
    @Binding var section: MacSection?
    @Binding var sheet: MacSheet?
    @Query(sort: \Lane.position) private var lanes: [Lane]
    @Query(filter: #Predicate<Decision> { $0.verdictRaw == "shortlist" }) private var shortlisted: [Decision]
    @Query(filter: #Predicate<StoryPick> { $0.verdictRaw == "shortlist" }) private var shortlistedStories: [StoryPick]
    @Query(sort: \IssueDraft.created, order: .reverse) private var issues: [IssueDraft]

    var body: some View {
        List(selection: $section) {
            Section("Today") {
                Label("All my lanes", systemImage: "square.stack.3d.up")
                    .tag(MacSection.lane(ScoutModel.allLanes))
                ForEach(lanes.filter { $0.packID == model.activePack.id }) { lane in
                    Label { Text(verbatim: lane.name) } icon: { Image(systemName: icon(for: lane)) }
                        .tag(MacSection.lane(lane.name))
                }
            }
            if !model.suggestedPairs.isEmpty {
                Section("Suggested lanes") {
                    ForEach(model.suggestedPairs.prefix(4), id: \.pair) { entry in
                        Button { model.addLane(from: entry.pair) } label: {
                            Label { Text(verbatim: entry.pair.label) } icon: { Image(systemName: "plus.circle") }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.inkSecondary)
                        .help("Tags seen together on \(entry.count) posts")
                    }
                }
            }
            Section("Desk") {
                Label("Shortlist", systemImage: "checkmark.circle")
                    .badge(shortlisted.count + shortlistedStories.count)
                    .tag(MacSection.shortlist)
                Label { Text(verbatim: issues.first?.title ?? "Issue") } icon: { Image(systemName: "newspaper") }
                    .badge(issues.first?.entries.count ?? 0)
                    .tag(MacSection.issue)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(MacSection.search)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { packBar }
        .toolbar {
            ToolbarItem {
                Menu("Add", systemImage: "plus") {
                    Button("New Topic…", systemImage: "sparkle.magnifyingglass") { sheet = .newTopic }
                    Button("New Lane from Tags…", systemImage: "tag") { sheet = .newLane }
                    Button("Add a Site…", systemImage: "globe") { sheet = .addSite }
                }
                .help("Add a lane")
            }
        }
    }

    /// The role pack in use, switchable here or in Settings.
    private var packBar: some View {
        Menu {
            ForEach(PackStore.all) { pack in
                Button { model.switchPack(to: pack) } label: {
                    if pack.id == model.activePack.id { Label(pack.name, systemImage: "checkmark") } else { Text(pack.name) }
                }
            }
            Divider()
            SettingsLink { Text("Settings…") }
        } label: {
            Label { Text(verbatim: model.activePack.name) } icon: { Image(systemName: "person.crop.rectangle.stack") }
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .help("Role pack")
    }

    private func icon(for lane: Lane) -> String {
        if lane.tags.contains(where: { $0.contains("ycombinator") || $0.hasPrefix("hn") }) { return "flame" }
        if lane.tags.contains(where: { $0.hasPrefix("http") }) { return "dot.radiowaves.up.forward" }
        return "number"
    }
}

// MARK: Ranked list

struct MacDeckList: View {
    @Environment(ScoutModel.self) private var model
    @Binding var selection: String?
    let refresh: () -> Void

    private var ids: [String] { model.mode == .writers ? model.deck.map(\.id) : model.storyDeck.map(\.id) }

    var body: some View {
        @Bindable var model = model
        List(selection: $selection) {
            if model.mode == .writers {
                ForEach(Array(model.deck.enumerated()), id: \.element.id) { index, candidate in
                    MacWriterRow(rank: index + 1, candidate: candidate, avatar: model.avatars[candidate.authorKey])
                        .tag(candidate.id)
                        .contextMenu {
                            Button("Shortlist") { model.decide(candidate, .shortlist) }
                            Button("Add to Issue") { model.decide(candidate, .issue) }
                            Button("Pass") { model.decide(candidate, .pass) }
                            Divider()
                            Button("Block \(candidate.name)", role: .destructive) { model.block(candidate) }
                        }
                }
            } else {
                ForEach(Array(model.storyDeck.enumerated()), id: \.element.id) { index, story in
                    MacStoryRow(rank: index + 1, story: story)
                        .tag(story.id)
                        .contextMenu {
                            Button("Shortlist") { model.decideStory(story, .shortlist) }
                            Button("Add to Issue") { model.decideStory(story, .issue) }
                            Button("Pass") { model.decideStory(story, .pass) }
                        }
                }
            }
        }
        .overlay {
            if ids.isEmpty {
                if model.isLoading {
                    ProgressView("Reading feeds…")
                } else {
                    ContentUnavailableView(model.mode == .writers ? "No writers left" : "No stories left",
                                           systemImage: "rectangle.stack",
                                           description: Text("Try a longer window or another lane."))
                }
            }
        }
        .navigationTitle(model.isAllLanes ? Text("All my lanes") : Text(verbatim: model.activeLaneName))
        .navigationSubtitle(Text("\(ids.count) ranked in code · \(model.window.title)"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Deck", selection: $model.mode) {
                    ForEach(DeckMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                Picker("Window", selection: $model.window) {
                    ForEach(DeckWindow.allCases) { Text($0.title).tag($0) }
                }
                .help("How far back to read")
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isLoading)
                    .help("Read the feeds again (⌘R)")
            }
        }
        .onChange(of: ids, initial: true) { _, ids in
            if selection.map({ !ids.contains($0) }) ?? true { selection = ids.first }
        }
    }
}

#if DEBUG
/// -demoDecisions (with -demoData): shortlists and adds a few top writers to the issue once,
/// so screenshots of the shortlist and issue have content without keystrokes.
@MainActor private var madeDemoDecisions = false

extension ScoutModel {
    func makeDemoDecisions() {
        guard usesDemoData, !madeDemoDecisions, deck.count >= 5,
              ProcessInfo.processInfo.arguments.contains("-demoDecisions") else { return }
        madeDemoDecisions = true
        let top = Array(deck.prefix(5))
        decide(top[0], .shortlist)
        decide(top[1], .issue)
        decide(top[2], .shortlist)
        decide(top[3], .issue)
        decide(top[4], .issue)
    }
}
#endif

struct MacWriterRow: View {
    let rank: Int
    let candidate: AuthorCandidate
    let avatar: URL?

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.caption.monospacedDigit()).foregroundStyle(Color.inkSecondary).frame(width: 22, alignment: .trailing)
            Avatar(name: candidate.name, url: avatar ?? candidate.avatarURL, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: candidate.name).font(.body.weight(.semibold)).lineLimit(1)
                    if candidate.authorKey.hasPrefix("hn:") { MonoLabel("HN") }
                }
                Text(verbatim: candidate.bestPost.title).font(.callout).foregroundStyle(Color.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(candidate.score)").font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(Color.scoutGreen)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct MacStoryRow: View {
    let rank: Int
    let story: StoryCandidate

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(rank)").font(.caption.monospacedDigit()).foregroundStyle(Color.inkSecondary).frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: story.post.title).font(.body.weight(.semibold)).lineLimit(2)
                Text(verbatim: byline).font(.caption).foregroundStyle(Color.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(story.score)").font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(Color.scoutGreen)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var byline: String {
        var parts = [story.post.authorName]
        if story.lanesSurfacing > 1 { parts.append(String(localized: "\(story.lanesSurfacing) lanes")) }
        parts.append(story.post.published.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}

// MARK: Detail

struct MacCardDetail: View {
    @Environment(ScoutModel.self) private var model
    @Binding var selection: String?
    @Binding var sheet: MacSheet?

    private var writer: AuthorCandidate? {
        model.mode == .writers ? model.deck.first { $0.id == selection } : nil
    }

    private var story: StoryCandidate? {
        model.mode == .stories ? model.storyDeck.first { $0.id == selection } : nil
    }

    var body: some View {
        Group {
            if let writer {
                ScrollView { writerCard(writer).frame(maxWidth: 680).padding(24).frame(maxWidth: .infinity) }
                    .task(id: writer.id) {
                        model.explain(writer)
                        await model.ensureStats(for: writer)
                    }
            } else if let story {
                ScrollView { storyCard(story).frame(maxWidth: 680).padding(24).frame(maxWidth: .infinity) }
                    .task(id: story.id) { model.explain(story) }
            } else {
                ContentUnavailableView("Pick a card", systemImage: "rectangle.stack",
                                       description: Text("Use ↑ and ↓ in the list. ⌘↩ shortlists, ⌘I adds to the issue, ⌘⌫ passes."))
            }
        }
        .background(Color.paper)
        .toolbar {
            ToolbarItemGroup {
                Button("Pass", systemImage: "xmark") { actions?.pass() }
                    .help("Pass (⌘⌫)")
                    .disabled(actions == nil)
                Button("Add to Issue", systemImage: "newspaper") { actions?.addToIssue() }
                    .help("Add to the issue (⌘I)")
                    .disabled(actions == nil)
                Button("Shortlist", systemImage: "checkmark") { actions?.shortlist() }
                    .help("Shortlist (⌘↩)")
                    .buttonStyle(.glassProminent)
                    .disabled(actions == nil)
            }
        }
        .focusedSceneValue(\.deckActions, actions)
    }

    private func writerCard(_ candidate: AuthorCandidate) -> some View {
        Group {
            if candidate.authorKey.hasPrefix("hn:") {
                HNPersonCard(candidate: candidate, stats: model.hnStats[candidate.authorKey], why: model.whyLines[candidate.authorKey],
                             onAsk: { sheet = .ask(.writer(candidate)) }, onThreadBrief: { sheet = .threadBrief($0) })
            } else {
                AuthorCard(candidate: candidate, why: model.whyLines[candidate.authorKey],
                           stats: model.authorStats[candidate.authorKey], onAsk: { sheet = .ask(.writer(candidate)) },
                           onRead: { sheet = .read(ReaderItem(id: candidate.bestPost.guid, subject: .writer(candidate))) },
                           site: model.siteContext(for: candidate.bestPost))
            }
        }
    }

    private func storyCard(_ story: StoryCandidate) -> some View {
        StoryCardView(story: story, laneTags: model.activeLane.tags, why: model.storyWhyLines[story.id],
                      imageFirst: model.activePack.isVisual, avatarURL: model.avatars[story.post.authorKey],
                      onAsk: { sheet = .ask(.story(story)) }, site: model.siteContext(for: story.post),
                      onRead: { sheet = .read(ReaderItem(id: story.id, subject: .story(story))) },
                      onThreadBrief: { sheet = .threadBrief($0) })
    }

    /// The selected card's actions. After a decision the next card in the ranked order is selected.
    private var actions: DeckActions? {
        if let writer {
            return DeckActions(shortlist: { decide(writer, .shortlist) }, pass: { decide(writer, .pass) },
                               addToIssue: { decide(writer, .issue) },
                               read: { sheet = .read(ReaderItem(id: writer.bestPost.guid, subject: .writer(writer))) },
                               ask: { sheet = .ask(.writer(writer)) })
        }
        if let story {
            return DeckActions(shortlist: { decide(story, .shortlist) }, pass: { decide(story, .pass) },
                               addToIssue: { decide(story, .issue) },
                               read: { sheet = .read(ReaderItem(id: story.id, subject: .story(story))) },
                               ask: { sheet = .ask(.story(story)) })
        }
        return nil
    }

    private func decide(_ candidate: AuthorCandidate, _ verdict: Verdict) {
        let next = following(candidate.id, in: model.deck.map(\.id))
        model.decide(candidate, verdict)
        selection = next
    }

    private func decide(_ story: StoryCandidate, _ verdict: Verdict) {
        let next = following(story.id, in: model.storyDeck.map(\.id))
        model.decideStory(story, verdict)
        selection = next
    }

    private func following(_ id: String, in ids: [String]) -> String? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        return index + 1 < ids.count ? ids[index + 1] : (index > 0 ? ids[index - 1] : nil)
    }
}
