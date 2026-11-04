//
//  AuthorCard.swift
//  Scout
//

import ScoutKit
import SwiftUI

/// An opaque card (no glass on content), laid out like the approved deck mockup.
struct AuthorCard: View {
    let candidate: AuthorCandidate
    /// Shown only when the on-device model wrote a line that passed `TextGuard`; otherwise the box is left out.
    let why: String?
    /// From the writer's own feed, computed in code.
    var stats: AuthorStats?

    private var post: PostRecord { candidate.bestPost }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(name: candidate.name, url: candidate.avatarURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name).font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                    if let handle = candidate.handle {
                        Text("@\(handle)").font(.subheadline).foregroundStyle(Color.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("\(candidate.score)").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Color.scoutGreen)
                    MonoLabel("match")
                }
                .accessibilityElement(children: .combine)
            }

            if !post.snippet.isEmpty {
                Text(post.snippet)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("Best this week")
                Text(post.title).font(.headline).foregroundStyle(Color.ink).lineLimit(3)
                Text(meta).font(.caption).foregroundStyle(Color.inkSecondary)
            }

            if let stats {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow {
                        MonoLabel("Posts / week")
                        MonoLabel("Typical length")
                        MonoLabel("Title shape")
                    }
                    GridRow {
                        Text(stats.postsPerWeek, format: .number.precision(.fractionLength(1)))
                        Text(stats.typicalWords.map { "\($0.formatted()) words" } ?? "—")
                        Text(stats.leadingPatterns.first?.rawValue ?? "—").lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.ink)
                }
                .accessibilityIdentifier("deck.stats")
            }

            FlowLayout {
                ForEach(candidate.topics, id: \.self) { TagChip(text: $0) }
            }

            Spacer(minLength: 0)

            if let why {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Why this writer · on-device model", color: .scoutGreen)
                    Text(verbatim: why).font(.callout).foregroundStyle(Color.ink)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.scoutGreen.opacity(0.09), in: .rect(cornerRadius: 16))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.card, in: .rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.card")
    }

    /// Facts from code: reading time (only from full-text feeds), date and posts in the window.
    private var meta: String {
        var parts: [String] = []
        if let minutes = post.readingMinutes { parts.append("\(minutes) min read") }
        parts.append(post.published.formatted(.relative(presentation: .named)))
        let count = candidate.signals.postsInWindow
        parts.append(count == 1 ? "1 post in window" : "\(count) posts in window")
        return parts.joined(separator: " · ")
    }
}
