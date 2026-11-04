//
//  StoryCard.swift
//  Scout
//

import ScoutKit
import SwiftUI

/// One post, in the writer card's style: title large, every tag as a chip, the author line small.
struct StoryCard: View {
    let story: StoryCandidate
    let laneTags: Set<String>
    let why: String?
    /// Visual packs lead with the post's image, large.
    var imageFirst = false
    /// The writer's avatar from their own feed, when fetched.
    var avatarURL: URL?
    /// Opens the Ask sheet; nil hides the sparkles button.
    var onAsk: (() -> Void)?

    private var post: PostRecord { story.post }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Avatar(name: post.authorName, url: avatarURL, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.authorName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                    if let handle = post.handle {
                        Text("@\(handle)").font(.caption).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if let onAsk { AskButton(action: onAsk) }
                VStack(spacing: 0) {
                    Text("\(story.score)").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Color.scoutGreen)
                    MonoLabel("match")
                }
                .accessibilityElement(children: .combine)
            }

            MonoLabel(story.lanesSurfacing > 1 ? "Surfaced by \(story.lanesSurfacing) of your lanes" : "Story")

            if imageFirst, let url = post.imageURL.flatMap(URL.init(string:)) {
                // The clear box sets the size; a fill-scaled image overlaid on it can't widen the card.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120, maxHeight: 240)
                    .overlay {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.paper).overlay(ProgressView())
                        }
                    }
                    .clipShape(.rect(cornerRadius: 18))
                    .layoutPriority(-1)
                    .accessibilityLabel("Image from the post")
            }
            Text(post.title).font(imageFirst ? .title3.weight(.bold) : .title2.weight(.bold)).foregroundStyle(Color.ink)
                .lineLimit(imageFirst ? 2 : 4)
            if !post.snippet.isEmpty {
                Text(post.snippet).font(.body).foregroundStyle(Color.inkSecondary).lineLimit(imageFirst ? 2 : 3)
            }

            FlowLayout {
                ForEach(imageFirst ? Array(post.categories.prefix(8)) : post.categories, id: \.self) { tag in
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

            Text(byline).font(.footnote).foregroundStyle(Color.inkSecondary).lineLimit(1)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.card, in: .rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.card")
    }

    /// Reading time (only from full-text feeds) and date, from the feed.
    private var byline: String {
        var parts: [String] = []
        if let minutes = post.readingMinutes { parts.append("\(minutes) min read") }
        parts.append(post.published.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
