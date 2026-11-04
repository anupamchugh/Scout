//
//  Models.swift
//  Scout
//

import Foundation
import ScoutKit
import SwiftData

/// A post as the feed described it.
@Model
final class StoredPost {
    @Attribute(.unique) var guid: String
    var title: String
    var link: String
    var authorName: String
    /// `handle`, or `name:<creator>` for posts on a publication's own domain.
    var authorKey: String
    var handle: String?
    var snippet: String
    var categories: [String]
    /// Tag feeds that listed this post.
    var foundUnder: [String]
    var published: Date
    var firstSeen: Date
    /// Known only from feeds with full text (author and publication feeds).
    var readingMinutes: Int?
    var imageURL: String?

    init(guid: String, title: String, link: String, authorName: String, authorKey: String, handle: String?,
         snippet: String, categories: [String], foundUnder: [String], published: Date, firstSeen: Date,
         readingMinutes: Int? = nil, imageURL: String? = nil) {
        self.guid = guid
        self.title = title
        self.link = link
        self.authorName = authorName
        self.authorKey = authorKey
        self.handle = handle
        self.snippet = snippet
        self.categories = categories
        self.foundUnder = foundUnder
        self.published = published
        self.firstSeen = firstSeen
        self.readingMinutes = readingMinutes
        self.imageURL = imageURL
    }
}

/// What the author's own feed says about them beyond their posts.
@Model
final class AuthorInfo {
    @Attribute(.unique) var authorKey: String
    var avatarURL: String?
    var fetched: Date

    init(authorKey: String, avatarURL: String?, fetched: Date) {
        self.authorKey = authorKey
        self.avatarURL = avatarURL
        self.fetched = fetched
    }
}

/// A theme writers are matched against: a newsletter issue or a publication topic.
@Model
final class Lane {
    @Attribute(.unique) var name: String
    /// Lane keys: Medium tag slugs, or feed URLs for any other RSS or Atom feed. They supply the lane
    /// and feed the topic overlap signal.
    var tags: [String]
    /// The role pack this lane belongs to.
    var packID: String = RolePack.engineering.id
    /// A sentence describing the theme, embedded for the semantic signal.
    var theme: String
    var position: Int

    init(name: String, tags: [String], theme: String, position: Int, packID: String = RolePack.engineering.id) {
        self.packID = packID
        self.name = name
        self.tags = tags
        self.theme = theme
        self.position = position
    }
}

enum Verdict: String, Codable, CaseIterable, Sendable {
    case shortlist
    case pass
    case issue
}

/// A swipe on an author card. Shortlisted rows carry the outreach note.
@Model
final class Decision {
    @Attribute(.unique) var authorKey: String
    var authorName: String
    var handle: String?
    var lane: String
    var verdictRaw: String
    var score: Int
    var bestPostGuid: String
    var bestPostTitle: String
    var bestPostLink: String
    var note: String
    var decided: Date

    var verdict: Verdict {
        get { Verdict(rawValue: verdictRaw) ?? .pass }
        set { verdictRaw = newValue.rawValue }
    }

    init(authorKey: String, authorName: String, handle: String?, lane: String, verdict: Verdict, score: Int,
         bestPostGuid: String, bestPostTitle: String, bestPostLink: String, note: String = "", decided: Date = .now) {
        self.authorKey = authorKey
        self.authorName = authorName
        self.handle = handle
        self.lane = lane
        self.verdictRaw = verdict.rawValue
        self.score = score
        self.bestPostGuid = bestPostGuid
        self.bestPostTitle = bestPostTitle
        self.bestPostLink = bestPostLink
        self.note = note
        self.decided = decided
    }
}

/// A swipe on a story card. An issue entry is always a story; outreach still targets the writer.
@Model
final class StoryPick {
    @Attribute(.unique) var guid: String
    var title: String
    var link: String
    var authorKey: String
    var authorName: String
    var handle: String?
    var tags: [String]
    var lane: String
    var verdictRaw: String
    var score: Int
    var decided: Date

    var verdict: Verdict {
        get { Verdict(rawValue: verdictRaw) ?? .pass }
        set { verdictRaw = newValue.rawValue }
    }

    init(guid: String, title: String, link: String, authorKey: String, authorName: String, handle: String?,
         tags: [String], lane: String, verdict: Verdict, score: Int, decided: Date = .now) {
        self.guid = guid
        self.title = title
        self.link = link
        self.authorKey = authorKey
        self.authorName = authorName
        self.handle = handle
        self.tags = tags
        self.lane = lane
        self.verdictRaw = verdict.rawValue
        self.score = score
        self.decided = decided
    }
}

@Model
final class BlockedAuthor {
    @Attribute(.unique) var authorKey: String
    var name: String
    var since: Date

    init(authorKey: String, name: String, since: Date = .now) {
        self.authorKey = authorKey
        self.name = name
        self.since = since
    }
}

/// A newsletter issue being drafted (Coffee Bytes style).
@Model
final class IssueDraft {
    var number: Int
    var title: String
    var intro: String
    var created: Date
    @Relationship(deleteRule: .cascade, inverse: \IssueEntry.issue) var entries: [IssueEntry] = []

    init(number: Int, title: String, intro: String = "", created: Date = .now) {
        self.number = number
        self.title = title
        self.intro = intro
        self.created = created
    }

    var orderedEntries: [IssueEntry] { entries.sorted { $0.position < $1.position } }
}

@Model
final class IssueEntry {
    var issue: IssueDraft?
    var position: Int
    var postGuid: String
    var title: String
    var link: String
    var authorName: String
    var handle: String?
    var note: String
    /// From LinkPresentation; nil until fetched or when the fetch fails (then the RSS title is used).
    var previewTitle: String?
    @Attribute(.externalStorage) var previewImage: Data?

    init(position: Int, postGuid: String, title: String, link: String, authorName: String, handle: String?, note: String = "") {
        self.position = position
        self.postGuid = postGuid
        self.title = title
        self.link = link
        self.authorName = authorName
        self.handle = handle
        self.note = note
    }
}

/// A pitch imported from a PDF or screenshot.
@Model
final class Pitch {
    var title: String
    var summary: String
    var text: String
    var handle: String?
    var linkedAuthorKey: String?
    var imported: Date

    init(title: String, summary: String, text: String, handle: String?, linkedAuthorKey: String?, imported: Date = .now) {
        self.title = title
        self.summary = summary
        self.text = text
        self.handle = handle
        self.linkedAuthorKey = linkedAuthorKey
        self.imported = imported
    }
}
