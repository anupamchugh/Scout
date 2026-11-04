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
}

struct AskAnswer: Identifiable {
    let id = UUID()
    let question: String
    let text: String
    /// "On-device model" or "From your data".
    let source: String
    var run: ModelRun?
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
                        AnswerCard(answer: $answer, actions: actions, perform: perform)
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
            .navigationBarTitleDisplayMode(.inline)
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
                let reply = try await session.respond(options: ScoutMode.asking.options) {
                    "Writer: \(subject.name). Post: \"\(subject.post.title)\"."
                    if let stats = model.authorStats[subject.authorKey] { stats }
                    "<feed>\(subject.post.snippet)</feed>"
                    prompt
                }.content
                if TextGuard.isGrounded(reply, in: corpus + " " + prompt) {
                    output = reply
                } else {
                    rejection = "numbers or links not in your data"
                    output = String(localized: "The answer used numbers or links that aren't in your data, so Scout hid it. Try asking another way.")
                }
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
        answers.append(AskAnswer(question: chip, text: output, source: rejection == nil ? "On-device model" : "Scout", run: run))
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
            perform("Add to issue")
        }
    }

    // MARK: Actions (chosen by code, run only on a tap)

    private var actions: [String] {
        ["Shortlist", "Add to issue", "Open post"].filter { !done.contains($0) }
    }

    private func perform(_ action: String) {
        switch action {
        case "Open post":
            if let url = URL(string: subject.post.link) { openURL(url) }
        case "Shortlist", "Add to issue":
            let verdict: Verdict = action == "Shortlist" ? .shortlist : .issue
            switch subject {
            case .writer(let candidate): model.decide(candidate, verdict)
            case .story(let story): model.decideStory(story, verdict)
            }
            done.insert(action)
            answers.append(AskAnswer(question: action, text: action == "Shortlist" ? "Added to your shortlist."
                                     : "Added to this week's issue.", source: "Scout"))
        default:
            break
        }
    }
}

struct AnswerCard: View {
    @Binding var answer: AskAnswer
    let actions: [String]
    let perform: (String) -> Void
    @State private var showsReasons = false

    private let reasons = ["Wrong", "Too vague", "Made something up", "Missing info", "Wrong tone"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(answer.question)
            Text(verbatim: answer.text).font(.callout).foregroundStyle(Color.ink).textSelection(.enabled)
            Text(answer.source).font(.caption2).foregroundStyle(Color.inkSecondary)

            HStack(spacing: 8) {
                ForEach(actions.prefix(3), id: \.self) { action in
                    Button(action) { perform(action) }
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
