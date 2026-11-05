//
//  AskSheet.swift
//  Scout
//
//  The Apple Intelligence entry point. Some chips are answered by code from your data ("What else did
//  they write?", "Find similar writers", "Add to this week's issue"); the rest go to the on-device model,
//  whose answers are shown only if they pass TextGuard. Suggested actions are chosen by code.
//

import FoundationModels
import ScoutKit
import SwiftData
import SwiftUI

enum AskSubject: Identifiable {
    case writer(AuthorCandidate)
    case story(StoryCandidate)

    var id: String {
        switch self {
        case .writer(let candidate): "writer:\(candidate.authorKey)"
        case .story(let story): "story:\(story.id)"
        }
    }

    var authorKey: String {
        switch self {
        case .writer(let candidate): candidate.authorKey
        case .story(let story): story.post.authorKey
        }
    }

    var name: String {
        switch self {
        case .writer(let candidate): candidate.name
        case .story(let story): story.post.authorName
        }
    }

    var post: PostRecord {
        switch self {
        case .writer(let candidate): candidate.bestPost
        case .story(let story): story.post
        }
    }

    var lane: String {
        switch self {
        case .writer(let candidate): candidate.lane
        case .story(let story): story.lane
        }
    }

    var handle: String? {
        switch self {
        case .writer(let candidate): candidate.handle
        case .story(let story): story.post.handle
        }
    }
}

struct AskAnswer: Identifiable {
    let id = UUID()
    let question: String
    let text: String
    /// "On-device model" or "From your data".
    let source: String
    var run: ModelRun?
    /// Proposed by the model, filtered by code; empty means the code defaults are shown.
    var suggestions: [Suggestion] = []
}

struct AskSheet: View {
    let subject: AskSubject
    @Environment(ScoutModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var session: LanguageModelSession?
    @State private var answers: [AskAnswer] = []
    @State private var question = ""
    @State private var isThinking = false
    @State private var done: Set<String> = []

    private var availability: ModelAvailability { .current }

    private var modelChips: [String] {
        switch subject {
        case .writer: ["Why this writer?", "Summarize this post", "Draft outreach"]
        case .story: ["Why this story?", "Summarize this post", "Draft outreach"]
        }
    }

    private let dataChips = ["What else did they write?", "Find similar writers", "Add to this week's issue"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Avatar(name: subject.name, url: model.avatars[subject.authorKey], size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subject.name).font(.headline)
                            Text(subject.post.title).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(2)
                        }
                    }

                    if case .unavailable(let reason) = availability {
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(Color.inkSecondary)
                    }

                    FlowLayout(spacing: 8) {
                        if availability.isAvailable {
                            ForEach(modelChips, id: \.self) { chip in
                                chipButton(chip, systemImage: "sparkles") { Task { await ask(chip) } }
                            }
                        }
                        ForEach(dataChips, id: \.self) { chip in
                            chipButton(chip, systemImage: "tablecells") { Task { await answerFromData(chip) } }
                        }
                    }

                    ForEach($answers) { $answer in
                        AnswerCard(answer: $answer, actions: actions(for: answer), perform: perform,
                                   appleFeedback: { run in appleFeedback(for: run) })
                    }
                    if !followUps.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(followUps, id: \.self) { chip in
                                chipButton(chip, systemImage: "arrow.turn.down.right") {
                                    followUps = []
                                    Task { await ask(chip) }
                                }
                            }
                        }
                    }

                    if isThinking {
                        HStack { ProgressView(); Text("Thinking on device…").foregroundStyle(Color.inkSecondary) }
                    }
                }
                .padding()
            }
            .background(Color.paper)
            .safeAreaInset(edge: .bottom) {
                if availability.isAvailable {
                    HStack {
                        TextField("Ask about \(subject.name)", text: $question)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { send() }
                        Button("Ask", systemImage: "arrow.up.circle.fill") { send() }
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                    }
                    .padding()
                    .background(.bar)
                }
            }
            .navigationTitle("Ask")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { Button("Done") { dismiss() } }
            .task {
                guard availability.isAvailable else { return }
                let made: LanguageModelSession
                if case .story(let story) = subject {
                    made = Writer.session(.asking, authorKey: subject.authorKey, storyGuid: story.id)
                } else {
                    made = Writer.session(.asking, authorKey: subject.authorKey)
                }
                made.prewarm()
                session = made
            }
        }
    }

    /// Opt-in: a feedback attachment for Apple, built only when the person asks for it.
    private func appleFeedback(for run: ModelRun) -> Data? {
        guard let session else { return nil }
        let issues = run.reasons.map { reason -> LanguageModelFeedback.Issue in
            let category: LanguageModelFeedback.Issue.Category = switch reason {
            case "Made something up", "Wrong": .incorrect
            case "Too vague", "Missing info": .unhelpful
            case "Wrong tone": .didNotFollowInstructions
            default: .unhelpful
            }
            return LanguageModelFeedback.Issue(category: category, explanation: reason)
        }
        return session.logFeedbackAttachment(sentiment: run.rating > 0 ? .positive : .negative, issues: issues,
                                             desiredResponseText: run.desired.isEmpty ? nil : run.desired)
    }

    private func chipButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.card, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.hairline))
        }
        .buttonStyle(.plain)
        .disabled(isThinking)
        .accessibilityIdentifier("ask.chip.\(title)")
    }

    private func send() {
        let text = question.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        question = ""
        Task { await ask(text) }
    }

    // MARK: Model answers

    /// The data the model may use, which is also what its numbers are checked against.
    private var corpus: String {
        let key = subject.authorKey
        let posts = (try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.authorKey == key }))) ?? []
        var text = posts.map { "\($0.title). \($0.snippet). Tags: \($0.categories.joined(separator: ", "))" }.joined(separator: "\n")
        if let stats = model.authorStats[key] {
            text += "\nAbout \(String(format: "%.1f", stats.postsPerWeek)) posts a week; \(stats.postCount) posts in their feed; "
                + "usual length \(stats.typicalWords.map(String.init) ?? "unknown") words."
        }
        return text
    }

    private func ask(_ chip: String) async {
        guard let session, !session.isResponding else { return }
        isThinking = true
        defer { isThinking = false }
        let started = Date.now
        let laneName = subject.lane.isEmpty ? model.activeLaneName : subject.lane
        var output = ""
        var rejection: String?

        if chip == "Draft outreach" {
            let post = subject.post
            output = (try? await Writer.outreach(title: post.title, snippet: post.snippet, lane: laneName))
                ?? OutreachCheck.template(title: post.title, snippet: post.snippet, lane: laneName)
        } else {
            let prompt: String = switch chip {
            case "Why this writer?", "Why this story?": "Why might \(subject.name)'s writing suit the \(laneName) lane? Point to what their posts say."
            case "Summarize this post": "Summarise the post \"\(subject.post.title)\" in two sentences."
            default: chip
            }
            do {
                (output, rejection) = try await Writer.ask(prompt, about: subject.name, post: subject.post.title,
                                                           snippet: subject.post.snippet, stats: model.authorStats[subject.authorKey],
                                                           corpus: corpus, session: session)
            } catch {
                rejection = "error"
                output = WriterCopy.message(for: error)
            }
        }

        let run = ModelRun(role: chip == "Draft outreach" ? "outreach" : "ask", pack: model.activePack.id,
                           instructionsVersion: Writer.instructionsVersion(.asking), input: chip, subjectID: subject.id,
                           output: output, rejection: rejection, latency: Date.now.timeIntervalSince(started))
        context.insert(run)
        try? context.save()
        var answer = AskAnswer(question: chip, text: output, source: rejection == nil ? "On-device model" : "Scout", run: run)
        if rejection == nil {
            let proposed = await Writer.suggestions(after: output, targetID: subject.id, session: session)
            answer.suggestions = SuggestionFilter.filter(proposed, onScreen: [subject.id],
                                                         withHandle: subject.handle == nil ? [] : [subject.id],
                                                         hasIssue: true, alreadyDone: doneActions)
        }
        answers.append(answer)
    }

    // MARK: Data answers

    private func answerFromData(_ chip: String) async {
        let key = subject.authorKey
        switch chip {
        case "What else did they write?":
            let posts = ((try? context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.authorKey == key },
                                                                          sortBy: [SortDescriptor(\.published, order: .reverse)]))) ?? [])
            let lines = posts.prefix(6).map { "• \($0.title) (\($0.published.formatted(date: .abbreviated, time: .omitted)))" }
            answers.append(AskAnswer(question: chip, text: lines.isEmpty ? "No other stored posts yet." : lines.joined(separator: "\n"),
                                     source: "From your data"))
        case "Find similar writers":
            let similar = await model.similarWriters(to: key)
            let text = similar.isEmpty ? "No similar writers in today's deck."
                : similar.map { "• \($0.name), \($0.percent)% similar" }.joined(separator: "\n")
            answers.append(AskAnswer(question: chip, text: text, source: "From your data · on-device embeddings"))
        default:
            perform(Suggestion(action: .addToIssue, targetID: subject.id, label: "Add to issue"))
        }
    }

    // MARK: Actions (proposed by the model or code, run only on a tap)

    @State private var doneActions: Set<ScoutAction> = []
    @State private var followUps: [String] = []

    /// Shown when the model proposed nothing that passed the filter.
    private var defaultActions: [Suggestion] {
        [Suggestion(action: .shortlist, targetID: subject.id, label: "Shortlist"),
         Suggestion(action: .addToIssue, targetID: subject.id, label: "Add to issue"),
         Suggestion(action: .openPost, targetID: subject.id, label: "Open post")].filter { !doneActions.contains($0.action) }
    }

    private func actions(for answer: AskAnswer) -> [Suggestion] {
        let proposed = answer.suggestions.filter { !doneActions.contains($0.action) }
        return proposed.isEmpty ? defaultActions : proposed
    }

    /// The same functions the swipe gestures and App Intents call.
    private func perform(_ suggestion: Suggestion) {
        switch suggestion.action {
        case .openPost:
            if let url = URL(string: subject.post.link) { openURL(url) }
        case .shortlist, .addToIssue:
            let verdict: Verdict = suggestion.action == .shortlist ? .shortlist : .issue
            switch subject {
            case .writer(let candidate): model.decide(candidate, verdict)
            case .story(let story): model.decideStory(story, verdict)
            }
            note(suggestion.action == .shortlist ? "Added to your shortlist." : "Added to this week's issue.")
        case .draftOutreach:
            Task { await ask("Draft outreach") }
        case .followWriter:
            if let handle = subject.handle, model.followWriter(handle: handle, name: subject.name) {
                note("Following \(subject.name): their feed is now a lane.")
            }
        case .muteTag:
            if let tag = subject.post.categories.first {
                model.muteTag(tag)
                note("Muted “\(tag)”: those cards rank lower now.")
            }
        case .askFollowUp:
            followUps = ["Shorter", "More technical", "Give an example from their posts"]
        }
        if suggestion.action != .askFollowUp && suggestion.action != .openPost { doneActions.insert(suggestion.action) }
    }

    private func note(_ text: String) {
        answers.append(AskAnswer(question: "Done", text: text, source: "Scout"))
    }
}

struct AnswerCard: View {
    @Binding var answer: AskAnswer
    let actions: [Suggestion]
    let perform: (Suggestion) -> Void
    let appleFeedback: (ModelRun) -> Data?
    @State private var showsReasons = false
    @State private var feedbackFile: URL?

    private let reasons = ["Wrong", "Too vague", "Made something up", "Missing info", "Wrong tone"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(answer.question)
            Text(verbatim: answer.text).font(.callout).foregroundStyle(Color.ink).textSelection(.enabled)
            Text(answer.source).font(.caption2).foregroundStyle(Color.inkSecondary)

            HStack(spacing: 8) {
                ForEach(actions.prefix(3), id: \.self) { suggestion in
                    Button(suggestion.label) { perform(suggestion) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer()
                if let run = answer.run {
                    Button { rate(run, 1) } label: {
                        Image(systemName: run.rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    .accessibilityLabel("Good answer")
                    Button { rate(run, -1); showsReasons = true } label: {
                        Image(systemName: run.rating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                    .accessibilityLabel("Bad answer")
                }
            }
            .foregroundStyle(Color.scoutGreen)

            if showsReasons, let run = answer.run {
                FlowLayout(spacing: 6) {
                    ForEach(reasons, id: \.self) { reason in
                        Button(reason) {
                            if run.reasons.contains(reason) { run.reasons.removeAll { $0 == reason } } else { run.reasons.append(reason) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(run.reasons.contains(reason) ? .scoutGreen : .secondary)
                    }
                }
                TextField("Write what you wanted (optional)", text: Bindable(run).desired, axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Prepare feedback for Apple", systemImage: "envelope") {
                        if let data = appleFeedback(run) {
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("scout-feedback.json")
                            try? data.write(to: url)
                            feedbackFile = url
                        }
                    }
                    .font(.caption)
                    if let feedbackFile {
                        ShareLink(item: feedbackFile) { Label("Share", systemImage: "square.and.arrow.up") }.font(.caption)
                    }
                }
                Text("Nothing is sent unless you share the file yourself.").font(.caption2).foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.hairline))
    }

    private func rate(_ run: ModelRun, _ value: Int) {
        run.rating = run.rating == value ? 0 : value
        if run.rating != -1 { showsReasons = false }
    }
}
