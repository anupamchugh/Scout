//
//  CompareView.swift
//  Scout
//
//  Publication vs publication, read on device. Pick two Medium publications (or any feed), and Scout reads
//  each one's current feed with the on-device model's neutral rubric, then shows numbers computed in code.
//  A feed holds about ten recent posts, so each side says which dates it covers; an archived publication
//  (Better Programming) shows its last posts and says so.
//

import Observation
import ScoutKit
import SwiftUI

@MainActor
@Observable
final class CompareRun {
    var a = PublicationChoice.presets[0]
    var b = PublicationChoice.presets[1]
    var sideA: PublicationSide?
    var sideB: PublicationSide?
    var status = ""
    var failure: String?
    var running = false

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-compareA"), i + 1 < args.count, let c = PublicationChoice.parse(args[i + 1]) { a = Self.named(c) }
        if let i = args.firstIndex(of: "-compareB"), i + 1 < args.count, let c = PublicationChoice.parse(args[i + 1]) { b = Self.named(c) }
        #endif
    }

    static func named(_ choice: PublicationChoice) -> PublicationChoice {
        PublicationChoice.presets.first { $0.key == choice.key } ?? choice
    }

    func run() async {
        guard !running else { return }
        running = true
        failure = nil
        sideA = nil
        sideB = nil
        defer { running = false; status = "" }
        for (choice, isA) in [(a, true), (b, false)] {
            do {
                let side = try await PublicationComparison.side(choice) { done, total in
                    await MainActor.run { self.status = "Reading \(choice.name) · \(min(done + 1, total)) of \(total)" }
                }
                if isA { sideA = side } else { sideB = side }
            } catch {
                failure = String(localized: "Couldn’t read \(choice.name): \(error.localizedDescription)")
                return
            }
        }
    }
}

struct CompareView: View {
    @State private var compare = CompareRun()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pickers
                    Button {
                        Task { await compare.run() }
                    } label: {
                        Label(compare.running ? compare.status : "Compare on device",
                              systemImage: compare.running ? "hourglass" : "sparkles")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.scoutGreen)
                    .disabled(compare.running || compare.a.key == compare.b.key)
                    .accessibilityIdentifier("compare.run")

                    if let failure = compare.failure {
                        Text(failure).font(.subheadline).foregroundStyle(.red)
                    }
                    if compare.sideA != nil || compare.sideB != nil {
                        results
                    } else if !compare.running {
                        Text("Scout reads each publication’s latest posts with Apple Intelligence on this device, using one rubric for every writer: clarity, depth, evidence and originality. Counts, shares and averages are computed in code.")
                            .font(.subheadline).foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .background(Color.paper)
            .navigationTitle("Compare")
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-compareRun") { await compare.run() }
                // Screenshots without taps: -compareScroll <anchor> (second, signals, stories).
                if let i = args.firstIndex(of: "-compareScroll"), i + 1 < args.count {
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation { proxy.scrollTo(args[i + 1], anchor: .top) }
                }
                #endif
            }
            }
        }
    }

    private var pickers: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { picker("First", $compare.a); picker("Second", $compare.b) }
            VStack(spacing: 12) { picker("First", $compare.a); picker("Second", $compare.b) }
        }
    }

    private func picker(_ label: LocalizedStringResource, _ choice: Binding<PublicationChoice>) -> some View {
        PublicationPicker(label: label, choice: choice).disabled(compare.running)
    }

    @ViewBuilder
    private var results: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { sideCard(compare.sideA, compare.a); sideCard(compare.sideB, compare.b).id("second") }
            VStack(spacing: 12) { sideCard(compare.sideA, compare.a); sideCard(compare.sideB, compare.b).id("second") }
        }
        if let a = compare.sideA, let b = compare.sideB {
            SignalsTable(a: a, b: b).id("signals")
            VStack(spacing: 20) {
                ForEach([a, b], id: \.choice.key) { side in
                    if let story = side.topStory { TopStoryCard(side: side, story: story) }
                }
            }
            .id("stories")
            Text("A feed carries about ten recent posts, so each side describes those posts only. Member-only posts show a preview and are not judged. The rubric has not been measured against an editor’s decisions; these are patterns, not verdicts.")
                .font(.footnote).foregroundStyle(Color.inkSecondary)
        }
    }

    @ViewBuilder
    private func sideCard(_ side: PublicationSide?, _ choice: PublicationChoice) -> some View {
        if let side { SideCard(side: side) } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(choice.name).font(.title3.bold())
                ProgressView().controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.card, in: .rect(cornerRadius: 20))
        }
    }
}

// MARK: Pieces

struct PublicationPicker: View {
    let label: LocalizedStringResource
    @Binding var choice: PublicationChoice
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(label)
            Menu {
                ForEach(PublicationChoice.presets) { preset in
                    Button(preset.name) { choice = preset }
                }
            } label: {
                HStack {
                    Text(choice.name).font(.headline).foregroundStyle(Color.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").foregroundStyle(Color.inkSecondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.card, in: .rect(cornerRadius: 12))
            }
            TextField("Or a Medium publication or feed link", text: $custom)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit {
                    if let parsed = PublicationChoice.parse(custom) { choice = CompareRun.named(parsed); custom = "" }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func percent(_ value: Double?) -> String {
    value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–"
}

private func decimal(_ value: Double?) -> String {
    value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "–"
}

struct SideCard: View {
    let side: PublicationSide

    private var archived: Bool {
        guard let last = side.lastPost else { return false }
        return Date.now.timeIntervalSince(last) > 90 * 86_400
    }

    private var dates: String {
        guard let first = side.firstPost, let last = side.lastPost else { return "" }
        let f = first.formatted(date: .abbreviated, time: .omitted), l = last.formatted(date: .abbreviated, time: .omitted)
        return f == l ? f : "\(f) – \(l)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(side.choice.name).font(.title3.bold()).foregroundStyle(Color.ink)
                if archived {
                    Text("Archived").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.hairline, in: .capsule)
                }
            }
            Text("\(side.stories.count) posts · \(side.writers) writers · \(dates)")
                .font(.subheadline).foregroundStyle(Color.inkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(decimal(side.score)).font(.system(size: 44, weight: .heavy)).foregroundStyle(Color.scoutGreen)
                Text("/ 3 writing score").font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkSecondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    stat("Judged", "\(side.scored) of \(side.stories.count)")
                    stat("Depth strong", percent(side.depthStrong))
                    stat("Evidence strong", percent(side.evidenceStrong))
                }
            }
            if side.previewOnly > 0 || side.flagged > 0 {
                Text("\(side.previewOnly) member-only previews not judged · ^[\(side.flagged) read](inflect: true) flagged by the checker")
                    .font(.caption).foregroundStyle(Color.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.card, in: .rect(cornerRadius: 20))
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Color.inkSecondary)
            Text(value).font(.headline).foregroundStyle(Color.ink)
        }
    }
}

struct SignalsTable: View {
    let a: PublicationSide
    let b: PublicationSide

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Packaging and voice · counted in code")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Signal").font(.caption.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                    Text(a.choice.name).font(.caption.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                    Text(b.choice.name).font(.caption.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                }
                row("“Topic: subtitle” titles", percent(a.colonTitles), percent(b.colonTitles))
                row("Titles in a repeated template", percent(a.templatedShare), percent(b.templatedShare))
                row("Top writer’s share", percent(a.topWriterShare), percent(b.topWriterShare))
                row("Stock phrases per 1,000 words", decimal(a.stockPerThousand), decimal(b.stockPerThousand))
                row("“Not X, but Y” per 1,000 words", decimal(a.reframesPerThousand), decimal(b.reframesPerThousand))
                row("Posts with assistant phrases", "\(a.assistantStories)", "\(b.assistantStories)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 20))
    }

    private func row(_ title: LocalizedStringKey, _ left: String, _ right: String) -> some View {
        GridRow {
            Text(title).font(.subheadline).foregroundStyle(Color.ink)
            Text(left).font(.subheadline.bold()).monospacedDigit()
            Text(right).font(.subheadline.bold()).monospacedDigit()
        }
    }
}

struct TopStoryCard: View {
    let side: PublicationSide
    let story: ComparedStory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Top read · \(side.choice.name) · \(decimal(story.verdict.score))")
            if let url = URL(string: story.link) {
                Link(destination: url) { Text(story.title).font(.headline).multilineTextAlignment(.leading) }
            } else {
                Text(story.title).font(.headline)
            }
            Text(story.writer).font(.subheadline).foregroundStyle(Color.inkSecondary)
            if let critique = story.verdict.critique {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("Quote · found in article")
                    Text("“\(critique.evidenceQuote)”").font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paper, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("Why · on-device model")
                    Text(critique.reason).font(.subheadline)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 20))
    }
}
