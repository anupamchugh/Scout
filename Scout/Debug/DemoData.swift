//
//  DemoData.swift
//  Scout
//

#if DEBUG
import Foundation
import ScoutKit

/// Obviously fictional writers for `-demoData` (UI tests). Not real people or posts.
enum DemoData {
    private static func item(_ author: String, _ title: String, _ snippet: String, _ tags: [String], hoursAgo: Double) -> FeedItem {
        let handle = author.lowercased().replacingOccurrences(of: " ", with: "-")
        let slug = title.lowercased().filter { $0.isLetter || $0 == " " }.replacingOccurrences(of: " ", with: "-")
        return FeedItem(guid: "demo-\(slug)", title: title, link: URL(string: "https://medium.com/@\(handle)/\(slug)")!,
                        creator: author, published: Date(timeIntervalSinceNow: -hoursAgo * 3600),
                        categories: tags, snippet: snippet)
    }

    static let items: [FeedItem] = [
        item("Sample Writer A", "Sample: Actors without the fear", "A walk through actor isolation and reentrancy.", ["swift", "concurrency"], hoursAgo: 3),
        item("Sample Writer A", "Sample: Task groups in practice", "Capping concurrency in a task group.", ["swift", "ios"], hoursAgo: 30),
        item("Sample Writer B", "Sample: Observable view models", "Moving to the Observation framework.", ["swiftui", "ios"], hoursAgo: 6),
        item("Sample Writer C", "Sample: Review checklists that scale", "What a review checklist should catch.", ["software-engineering"], hoursAgo: 8),
        item("Sample Writer D", "Sample: Prompt evaluation notes", "Scoring prompts against a fixed dataset.", ["artificial-intelligence", "llm"], hoursAgo: 12),
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
