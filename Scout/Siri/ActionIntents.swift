//
//  ActionIntents.swift
//  Scout
//
//  Each suggested action is also an App Intent, so Shortcuts and Siri run the same code a tap does.
//

import AppIntents
import Foundation
import ScoutKit
import SwiftData

struct ShortlistWriterIntent: AppIntent {
    static let title: LocalizedStringResource = "Shortlist a Writer"
    static let description = IntentDescription("Add a writer Scout has stored to your shortlist.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Writer handle") var handle: String

    init() {}
    init(handle: String) { self.handle = handle }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let key = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        let context = ScoutStore.container.mainContext
        guard let post = try context.fetch(FetchDescriptor<StoredPost>(predicate: #Predicate { $0.authorKey == key },
                                                                      sortBy: [SortDescriptor(\.published, order: .reverse)])).first
        else { return .result(dialog: "Scout hasn't seen @\(key) yet.") }
        guard try context.fetchCount(FetchDescriptor<Decision>(predicate: #Predicate { $0.authorKey == key })) == 0 else {
            return .result(dialog: "\(post.authorName) is already decided.")
        }
        context.insert(Decision(authorKey: key, authorName: post.authorName, handle: post.handle, lane: "Shortcuts",
                                verdict: .shortlist, score: 0, bestPostGuid: post.guid, bestPostTitle: post.title, bestPostLink: post.link))
        try context.save()
        return .result(dialog: "Shortlisted \(post.authorName).")
    }
}

struct MuteTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute a Tag"
    static let description = IntentDescription("Rank cards with this tag lower in the active role pack.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Tag") var tag: String

    init() {}
    init(tag: String) { self.tag = tag }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ScoutStore.container.mainContext
        let record = ScoutStore.taste(for: PackStore.pack(id: PackStore.activeID), in: context)
        var taste = record.taste
        taste.tagWeights[tag.lowercased()] = -1
        record.taste = taste
        try context.save()
        return .result(dialog: "Muted \(tag).")
    }
}

struct FollowWriterIntent: AppIntent {
    static let title: LocalizedStringResource = "Follow a Writer"
    static let description = IntentDescription("Add a Medium writer's own feed as a lane.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Writer handle") var handle: String

    init() {}
    init(handle: String) { self.handle = handle }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let key = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        let model = ScoutModel(container: ScoutStore.container, usesDemoData: false)
        return model.followWriter(handle: key, name: "@\(key)")
            ? .result(dialog: "Following @\(key).") : .result(dialog: "You already follow @\(key).")
    }
}
