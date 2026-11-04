//
//  SpotlightIndex.swift
//  Scout
//

import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Shortlisted writers and their posts go into Core Spotlight; `CSUserQuery` searches them semantically.
enum SpotlightIndex {
    static let domain = "scout-shortlist"

    static func index(_ decisions: [Decision], posts: [StoredPost]) async {
        let byAuthor = Dictionary(grouping: posts, by: \.authorKey)
        var items: [CSSearchableItem] = []
        for decision in decisions where decision.verdict != .pass {
            let writer = CSSearchableItemAttributeSet(contentType: .contact)
            writer.title = decision.authorName
            writer.contentDescription = "\(decision.lane): \(decision.bestPostTitle)"
            writer.keywords = [decision.lane] + (decision.handle.map { [$0] } ?? [])
            items.append(CSSearchableItem(uniqueIdentifier: "author:\(decision.authorKey)", domainIdentifier: domain, attributeSet: writer))
            for post in byAuthor[decision.authorKey] ?? [] {
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = post.title
                attributes.contentDescription = "\(post.authorName): \(post.snippet)"
                attributes.keywords = post.categories
                attributes.url = URL(string: post.link)
                items.append(CSSearchableItem(uniqueIdentifier: "post:\(post.guid)", domainIdentifier: domain, attributeSet: attributes))
            }
        }
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }

    /// Identifiers (`author:<key>` or `post:<guid>`) Spotlight's semantic search returns for `text`.
    static func search(_ text: String) async -> [String] {
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title", "contentDescription"]
        let query = CSUserQuery(userQueryString: text, userQueryContext: context)
        var identifiers: [String] = []
        do {
            for try await element in query.responses {
                if case .item(let item) = element { identifiers.append(item.item.uniqueIdentifier) }
                if identifiers.count >= 20 { break }
            }
        } catch {
            return identifiers
        }
        return identifiers
    }
}
