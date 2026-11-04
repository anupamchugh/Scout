//
//  OutreachTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct OutreachTests {
    let title = "You cancelled the caller. Why is the shared Task still running?"
    let snippet = "Cancellation in Swift is cooperative: an unstructured Task keeps running until it checks."

    /// The kind of note the owner flagged: generic, wordy, flattering, no title, no ask.
    let bad = """
        Your post presents a strong technical opportunity to explore Swift concurrency. Your insightful perspective \
        could add depth to the conversation. We would love to feature voices like yours in our newsletter.
        """

    let good = """
        I read “You cancelled the caller. Why is the shared Task still running?” and liked how you showed that an \
        unstructured Task keeps running until it checks. Would you write a follow-up on that for Swift concurrency?
        """

    @Test func badNoteFailsEveryRuleItBreaks() {
        let problems = OutreachCheck.problems(bad, title: title, snippet: snippet)
        #expect(problems.contains(.tooLong))
        #expect(problems.contains(.missingTitle))
        #expect(problems.contains(.nothingConcrete))
        #expect(problems.contains(.flattery))
        #expect(problems.contains(.noAsk))
    }

    @Test func goodNotePasses() {
        #expect(OutreachCheck.problems(good, title: title, snippet: snippet) == [])
    }

    @Test func templateMeetsTheRules() {
        let note = OutreachCheck.template(title: title, snippet: snippet, lane: "Swift concurrency")
        #expect(OutreachCheck.isGood(note, title: title, snippet: snippet), "\(OutreachCheck.problems(note, title: title, snippet: snippet))")
    }

    @Test func answersMayOnlyUseNumbersFromTheData() {
        let source = "Swift 6 rejected the race. 3 posts a week."
        #expect(TextGuard.isGrounded("They write about Swift 6, about 3 times a week.", in: source))
        #expect(!TextGuard.isGrounded("They have 12,000 followers.", in: source))
        #expect(!TextGuard.isGrounded("See https://example.com", in: source))
    }
}
