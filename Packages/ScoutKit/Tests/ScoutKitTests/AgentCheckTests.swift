//
//  AgentCheckTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

private let cards = [
    StoryCard(id: "a", title: "Actors without the fear", subtitle: "A calm tour of isolation.", tags: ["swift"],
              author: "Writer A", handle: "a", link: "https://medium.com/@a/actors", lane: "Swift concurrency"),
    StoryCard(id: "b", title: "Prompt evaluation notes", subtitle: "Scoring prompts against a dataset.", tags: ["llm"],
              author: "Writer B", handle: nil, link: "https://b.example/evals", lane: "AI and LLMs"),
    StoryCard(id: "c", title: "Task groups in practice", subtitle: "Capping concurrency.", tags: ["swift"],
              author: "Writer C", handle: "c", link: "https://medium.com/@c/groups", lane: "Swift concurrency"),
]

struct AgentCheckTests {

    @Test func lineupKeepsOnlyKnownIDsOnceAndFilesLeftovers() {
        let repaired = IssueChecker.repairLineup([
            LineupSection(lane: "Swift concurrency", storyIDs: ["a", "zzz", "a"]),
            LineupSection(lane: "Empty", storyIDs: ["nope"]),
        ], cards: cards)
        #expect(repaired == [LineupSection(lane: "Swift concurrency", storyIDs: ["a", "c"]),
                             LineupSection(lane: "AI and LLMs", storyIDs: ["b"])])
    }

    @Test func blurbsWithNumbersOrTooLongFallBackToSubtitle() {
        #expect(IssueChecker.blurb("A clear walk through actor isolation.", card: cards[0]).flag == nil)
        let numbered = IssueChecker.blurb("Ten tips in 5 minutes.", card: cards[0])
        #expect(numbered.text == "A calm tour of isolation.")
        #expect(numbered.flag != nil)
        let long = IssueChecker.blurb(String(repeating: "word ", count: 60), card: cards[0])
        #expect(long.text == "A calm tour of isolation.")
        #expect(IssueChecker.blurb(nil, card: cards[0]).flag != nil)
        let card = StoryCard(id: "f", title: "500 Flutter Interview Questions", subtitle: "", tags: [], author: "M", handle: nil,
                             link: "https://x/f", lane: "L")
        #expect(IssueChecker.blurb("A tour of the 500 Flutter questions seniors get asked.", card: card).flag == nil)
    }

    @Test func introAndTitleChecks() {
        #expect(IssueChecker.intro("Actors, task groups and evaluating prompts this week.").flag == nil)
        #expect(IssueChecker.intro(String(repeating: "word ", count: 70)).text == "")
        #expect(IssueChecker.title("Issue 12: Actors", fallback: "Coffee Bytes").text == "Coffee Bytes")
        #expect(IssueChecker.title("Calm concurrency", fallback: "Coffee Bytes").text == "Calm concurrency")
    }

    @Test func editorLineMayAppearVerbatimButNothingElseNew() {
        let line = "This week: 3 agents that ship"
        // The line itself, numbers included, may be copied (ignoring case).
        #expect(IssueChecker.title("This week: 3 agents that ship", fallback: "Coffee Bytes", editorLine: line).flag == nil)
        #expect(IssueChecker.intro("this week: 3 agents that ship, from actors to evaluating prompts.", editorLine: line).flag == nil)
        // Numbers and links the line doesn't have still fail.
        #expect(IssueChecker.title("This week: 3 agents that ship in 2027", fallback: "Coffee Bytes", editorLine: line).text == "Coffee Bytes")
        #expect(IssueChecker.intro("Agents that ship, 5 of them.", editorLine: line).text == "")
        #expect(IssueChecker.intro("Agents that ship. Read more at agents.dev", editorLine: line).text == "")
        #expect(IssueChecker.intro("Agents that ship, see agents.dev", editorLine: "agents").text == "")
        // A digit borrowed from the line but not the line itself fails.
        #expect(IssueChecker.title("Top 3 picks", fallback: "Coffee Bytes", editorLine: line).text == "Coffee Bytes")
    }

    @Test func noEditorLineKeepsTodaysChecks() {
        for line in [nil, "", "   "] {
            #expect(IssueChecker.title("Issue 12: Actors", fallback: "Coffee Bytes", editorLine: line).text == "Coffee Bytes")
            #expect(IssueChecker.title("Calm concurrency", fallback: "Coffee Bytes", editorLine: line).text == "Calm concurrency")
            #expect(IssueChecker.intro("Read https://x.dev now.", editorLine: line).text == "")
            #expect(IssueChecker.intro("Actors and task groups this week.", editorLine: line).flag == nil)
        }
    }

    @Test func spotlightQuestionsMustCiteARealPost() {
        let digest = AuthorDigest(authorKey: "a", name: "Writer A", handle: "a",
                                  posts: [.init(title: "Actors without the fear", snippet: ""), .init(title: "Sendable in practice", snippet: "")])
        let result = IssueChecker.spotlight(intro: "Writer A explains isolation calmly.", questions: [
            "In “Actors without the fear”, what surprised readers most?",
            "What do you think about the future of AI?",
            "How did Sendable in practice change your code?",
        ], digest: digest)
        #expect(result.block?.questions.count == 2)
        #expect(result.flag != nil)
        let none = IssueChecker.spotlight(intro: "", questions: ["What's next?"], digest: digest)
        #expect(none.block == nil)
    }

    @Test func entriesMustMatchTheirCards() {
        let good = IssueContent.Entry(title: "Actors without the fear", url: "https://medium.com/@a/actors", author: "Writer A", handle: "a", note: "")
        let wrong = IssueContent.Entry(title: "Actors with fear", url: "https://medium.com/@a/actors", author: "Writer A", handle: "a", note: "")
        let invented = IssueContent.Entry(title: "X", url: "https://made.up/x", author: "Y", handle: nil, note: "")
        #expect(IssueChecker.mismatches([good], cards: cards).isEmpty)
        #expect(IssueChecker.mismatches([wrong, invented], cards: cards).count == 2)
    }

    @Test func suggestionsAreFilteredByCode() {
        let suggestions = [
            Suggestion(action: .shortlist, targetID: "a", label: "Shortlist them"),
            Suggestion(action: .shortlist, targetID: "a", label: "Shortlist again"),
            Suggestion(action: .draftOutreach, targetID: "b", label: "Write to them"),
            Suggestion(action: .openPost, targetID: "offscreen", label: "Open it"),
            Suggestion(action: .addToIssue, targetID: "a", label: "Add to issue"),
            Suggestion(action: .muteTag, targetID: "a", label: "Mute this tag please now"),
            Suggestion(action: .openPost, targetID: "c", label: "Read 3 posts"),
            Suggestion(action: .openPost, targetID: "a", label: "Open post"),
            Suggestion(action: .followWriter, targetID: "c", label: "Follow"),
        ]
        let kept = SuggestionFilter.filter(suggestions, onScreen: ["a", "b", "c"], withHandle: ["a", "c"], hasIssue: false)
        #expect(kept.map(\.label) == ["Shortlist them", "Open post", "Follow"])
    }

    @Test func sectionedIssueRendersSectionsAndSpotlight() {
        let issue = IssueContent(number: 3, title: "Calm concurrency", intro: "", entries: [
            .init(title: "Actors without the fear", url: "https://medium.com/@a/actors", author: "Writer A", handle: "a",
                  note: "A calm tour.", section: "Swift concurrency"),
            .init(title: "Prompt evaluation notes", url: "https://b.example/evals", author: "Writer B", handle: nil,
                  note: "", section: "AI and LLMs"),
        ], spotlight: SpotlightBlock(name: "Writer A", handle: "a", intro: "Writes calmly about isolation.",
                                     questions: ["In “Actors without the fear”, what surprised readers?"]))
        #expect(IssueRenderer.markdown(issue) == """
            ## Issue 3: Calm concurrency

            ### Swift concurrency

            - [Actors without the fear](https://medium.com/@a/actors) by Writer A (@a): A calm tour.

            ### AI and LLMs

            - [Prompt evaluation notes](https://b.example/evals) by Writer B

            ### Writer spotlight: Writer A (@a)

            Writes calmly about isolation.

            - In “Actors without the fear”, what surprised readers?

            """)
        #expect(IssueRenderer.html(issue).contains("<h3>Swift concurrency</h3>"))
    }
}
