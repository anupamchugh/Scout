//
//  StoryCard.swift
//  Scout
//

import SwiftUI

/// One post, in the writer card's style: title large, every tag as a chip, the author line small.
struct StoryCard: View {
    let story: StoryCandidate
    let laneTags: Set<String>
    let why: String?

    private var post: PostRecord { story.post }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(story.lanesSurfacing > 1 ? "Surfaced by \(story.lanesSurfacing) lanes" : "Story")
                Spacer()
                VStack(spacing: 0) {
                    Text("\(story.score)").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Color.scoutGreen)
                    MonoLabel("match")
                }
                .accessibilityElement(children: .combine)
            }

            Text(post.title).font(.title2.weight(.bold)).foregroundStyle(Color.ink).lineLimit(4)
            if !post.snippet.isEmpty {
                Text(post.snippet).font(.body).foregroundStyle(Color.inkSecondary).lineLimit(3)
            }

            FlowLayout {
                ForEach(post.categories, id: \.self) { tag in
                    TagChip(text: tag)
                        .overlay(Capsule().strokeBorder(laneTags.contains(tag) ? Color.scoutGreen : .clear, lineWidth: 1.5))
                }
            }

            Spacer(minLength: 0)

            if let why {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Why this story · on-device model", color: .scoutGreen)
                    Text(verbatim: why).font(.callout).foregroundStyle(Color.ink)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.scoutGreen.opacity(0.09), in: .rect(cornerRadius: 16))
            }

            HStack(spacing: 8) {
                Avatar(name: post.authorName, url: nil, size: 28)
                Text(byline).font(.footnote).foregroundStyle(Color.inkSecondary).lineLimit(1)
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

    /// Author, handle, reading time (only from full-text feeds) and date, all from the feed.
    private var byline: String {
        var parts = [post.handle.map { "\(post.authorName) · @\($0)" } ?? post.authorName]
        if let minutes = post.readingMinutes { parts.append("\(minutes) min read") }
        parts.append(post.published.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
