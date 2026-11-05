//
//  TagCatalog.swift
//  ScoutKit
//
//  Every tag seen on fetched posts, and which tags keep turning up beside each other. "Potential tags"
//  for a lane are the tags that most often share a post with the lane's own tags, counted in code.
//

import Foundation

public enum TagCatalog {

    /// Medium tag slugs as feeds give them: lowercased and trimmed. Feed URLs and empty strings aren't tags.
    public static func normalized(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.contains("://") })).sorted()
    }

    /// One post's contribution: each tag once, and each other tag on the same post once.
    public static func neighbours(of tags: [String]) -> [String: [String]] {
        let unique = normalized(tags)
        return Dictionary(uniqueKeysWithValues: unique.map { tag in (tag, unique.filter { $0 != tag }) })
    }

    public struct Potential: Sendable, Hashable {
        public let tag: String
        /// Posts on which this tag appeared beside at least one lane tag (summed over lane tags).
        public let together: Int
        /// Posts that carried this tag at all.
        public let seen: Int

        public init(tag: String, together: Int, seen: Int) {
            self.tag = tag
            self.together = together
            self.seen = seen
        }
    }

    /// Tags that share posts with `laneTags`, most shared first (ties: more seen, then alphabetical).
    /// `cooccurrence[tag][other]` is the number of posts carrying both; `counts[tag]` the posts carrying `tag`.
    public static func potential(for laneTags: Set<String>, counts: [String: Int], cooccurrence: [String: [String: Int]],
                                 minimum: Int = 2, limit: Int = 12) -> [Potential] {
        let lane = Set(normalized(Array(laneTags)))
        var together: [String: Int] = [:]
        for tag in lane {
            for (other, count) in cooccurrence[tag] ?? [:] where !lane.contains(other) {
                together[other, default: 0] += count
            }
        }
        return together.filter { $0.value >= minimum }
            .map { Potential(tag: $0.key, together: $0.value, seen: counts[$0.key] ?? $0.value) }
            .sorted {
                if $0.together != $1.together { return $0.together > $1.together }
                if $0.seen != $1.seen { return $0.seen > $1.seen }
                return $0.tag < $1.tag
            }
            .prefix(limit).map { $0 }
    }

    /// Counts and co-occurrence for a batch of posts, for tests and for building a catalog from scratch.
    public static func tally(_ posts: [[String]]) -> (counts: [String: Int], cooccurrence: [String: [String: Int]]) {
        var counts: [String: Int] = [:]
        var cooccurrence: [String: [String: Int]] = [:]
        for tags in posts {
            for (tag, others) in neighbours(of: tags) {
                counts[tag, default: 0] += 1
                for other in others { cooccurrence[tag, default: [:]][other, default: 0] += 1 }
            }
        }
        return (counts, cooccurrence)
    }
}
