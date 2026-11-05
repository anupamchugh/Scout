//
//  DemoData.swift
//  Scout
//

#if DEBUG
import Foundation
import ScoutKit

/// Fictional writers and posts for `-demoData` (UI tests, the README and the demo video). Invented names; not real people or posts.
enum DemoData {
    private static func item(_ author: String, _ title: String, _ snippet: String, _ tags: [String], hoursAgo: Double) -> FeedItem {
        let handle = author.lowercased().replacingOccurrences(of: " ", with: "-")
        let slug = title.lowercased().filter { $0.isLetter || $0 == " " }.replacingOccurrences(of: " ", with: "-")
        return FeedItem(guid: "demo-\(slug)", title: title, link: URL(string: "https://medium.com/@\(handle)/\(slug)")!,
                        creator: author, published: Date(timeIntervalSinceNow: -hoursAgo * 3600),
                        categories: tags, snippet: snippet)
    }

    static let items: [FeedItem] = [
        item("Mara Quill", "Actors without the fear",
             "Actor isolation and reentrancy explained with one small chat app. Each actor owns its state, and every hop is an await you can see.", ["swift", "concurrency", "swift-concurrency"], hoursAgo: 3),
        item("Mara Quill", "Task groups in practice",
             "Capping concurrency in a task group so a photo importer never opens two hundred requests at once.", ["swift", "concurrency", "ios"], hoursAgo: 30),
        item("Mara Quill", "Cancellation is cooperative",
             "Why a cancelled parent task keeps running children until they check, and how to make them check.", ["swift", "async-await"], hoursAgo: 70),
        item("Theo Lantern", "Observable view models without the boilerplate",
             "Moving a settings screen from ObservableObject to the Observation framework, one property at a time.", ["swiftui", "ios", "swift"], hoursAgo: 6),
        item("Theo Lantern", "Layout that survives Dynamic Type",
             "Building a profile header that still reads well at the largest text sizes.", ["swiftui", "ios-development", "accessibility"], hoursAgo: 50),
        item("Iris Fernhall", "Review checklists that scale",
             "What a code review checklist should catch, and what it should leave to the compiler and the tests.", ["software-engineering", "programming", "engineering-management"], hoursAgo: 8),
        item("Iris Fernhall", "Running a calm on-call rotation",
             "Small rules that cut pages in half: owners for alerts, runbooks next to dashboards, and a weekly review.", ["engineering-management", "software-engineering", "devops"], hoursAgo: 40),
        item("Iris Fernhall", "Hiring your first staff engineer",
             "Questions that separate scope from seniority, and how to write a role people want.", ["engineering-management", "careers", "leadership"], hoursAgo: 90),
        item("Juno Ashby", "Prompt evaluation notes",
             "Scoring prompts against a fixed dataset so a change is a number, not a feeling.", ["artificial-intelligence", "llm", "machine-learning"], hoursAgo: 12),
        item("Juno Ashby", "RAG without a vector database",
             "Retrieval for a small docs site with plain keyword search and a reranker, measured before and after.", ["rag", "llm", "artificial-intelligence"], hoursAgo: 20),
        item("Juno Ashby", "When an agent should stop",
             "Counted exits for tool-calling loops: a budget, a required first tool, then a final answer.", ["ai-agent", "llm", "artificial-intelligence"], hoursAgo: 55),
        item("Felix Marrow", "On-device models for app features",
             "Choosing between the system model and a server model by privacy, cost and offline needs.", ["machine-learning", "ios", "artificial-intelligence"], hoursAgo: 16),
        item("Felix Marrow", "Structured output beats string parsing",
             "Asking for a typed result so the app never splits sentences with regular expressions.", ["llm", "swift", "ios-development"], hoursAgo: 60),
        item("Wren Calloway", "Interview prep that respects your time",
             "A two-week plan for iOS interviews: one system design, one debugging story, one take-home.", ["careers", "interview", "ios-interview-question"], hoursAgo: 10),
        item("Wren Calloway", "Leaving a job well",
             "A handover document template and the three conversations to have before your last day.", ["careers", "engineering-management"], hoursAgo: 80),
        item("Ola Brightwater", "Writing a technical newsletter people open",
             "Subject lines that promise one thing, a single link that matters, and a schedule you can keep.", ["newsletters", "writing", "blogging"], hoursAgo: 5),
        item("Ola Brightwater", "From blog post to book chapter",
             "How twelve posts on one theme became a chapter outline, and what had to be cut.", ["writing", "blogging", "content-creation"], hoursAgo: 45),
        item("Ola Brightwater", "Editing your own drafts",
             "Read it aloud, cut the first paragraph, and replace every adjective with a number or an example.", ["writing", "editing", "blogging"], hoursAgo: 100),
        item("Silas Thornbury", "Static sites in an afternoon",
             "Publishing a personal blog with a static site generator, a custom domain and an RSS feed.", ["web-development", "blogging", "programming"], hoursAgo: 22),
        item("Silas Thornbury", "CSS that a designer can read",
             "Naming tokens after intent, not colour, so a theme change touches one file.", ["web-development", "css", "design"], hoursAgo: 65),
        item("Nadia Pell", "A gentle intro to Postgres indexes",
             "Reading a query plan, adding the right index and checking that it is used.", ["programming", "databases", "software-engineering"], hoursAgo: 14),
        item("Nadia Pell", "Background jobs that do not lose work",
             "Idempotent handlers, retries with backoff, and a dead-letter queue you actually look at.", ["backend", "software-engineering", "programming"], hoursAgo: 75),
        item("Rowan Vale", "Modularising an iOS app",
             "Splitting features into Swift packages without a dependency tangle, with build times before and after.", ["ios-development", "software-architecture", "swift"], hoursAgo: 18),
        item("Rowan Vale", "Testing view models with Swift Testing",
             "Parameterised tests for a form's validation rules, and why the view stays out of it.", ["swift", "testing", "ios"], hoursAgo: 85),
        item("Esme Holloway", "Open-source maintainers need editors too",
             "How a docs pass doubled first-time contributions to a small library.", ["open-source", "writing", "programming"], hoursAgo: 26),
        item("Esme Holloway", "Changelogs people read",
             "Writing release notes for users first and contributors second.", ["open-source", "software-engineering", "writing"], hoursAgo: 95),
    ]

    static func report(for sources: [FeedSource]) -> FeedClient.Report {
        var report = FeedClient.Report()
        for source in sources {
            switch source {
            case .tag(let slug): report.items[source] = items.filter { $0.categories.contains(slug) }
            case .author(let handle): report.items[source] = items.filter { $0.handle == handle }
            case .publication, .feed: report.items[source] = []
            }
        }
        return report
    }
}
#endif
