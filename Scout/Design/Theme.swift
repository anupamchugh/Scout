//
//  Theme.swift
//  Scout
//

import ScoutKit
import SwiftUI
import UIKit

/// The approved palette, with dark-mode counterparts.
extension Color {
    static let paper = Color(light: 0xF7F5F0, dark: 0x121210)
    static let card = Color(light: 0xFFFFFF, dark: 0x1E1D1A)
    static let ink = Color(light: 0x141414, dark: 0xF2F0EA)
    static let inkSecondary = Color(light: 0x5A574F, dark: 0xA9A59A)
    static let scoutGreen = Color(light: 0x1E6B47, dark: 0x4FB283)
    static let scoutBlue = Color(light: 0x2156A8, dark: 0x6E9BE6)
    static let hairline = Color(light: 0xE4E0D6, dark: 0x34322D)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Small monospaced caps for section labels, as in the mockups.
struct MonoLabel: View {
    let text: Text
    var color: Color = .inkSecondary

    /// App copy: a String Catalog key, localized.
    init(_ resource: LocalizedStringResource, color: Color = .inkSecondary) {
        self.text = Text(resource)
        self.color = color
    }

    /// Data (a lane name, a question): shown as is. Disfavoured, so a string literal is a catalog key, as with `Text`.
    @_disfavoredOverload
    init<S: StringProtocol>(_ text: S, color: Color = .inkSecondary) {
        self.text = Text(verbatim: String(text))
        self.color = color
    }

    var body: some View {
        text
            .textCase(.uppercase)
            .font(.caption2.monospaced().weight(.medium))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(Color.ink)
            .background(Color.paper, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.hairline))
    }
}

struct Avatar: View {
    let name: String
    let url: URL?
    var size: CGFloat = 52

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Color.scoutGreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.scoutGreen.opacity(0.12))
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Lays chips out left to right, wrapping to a new line when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if var last = rows.last, last.width + spacing + size.width <= width {
                last.indices.append(index)
                last.width += spacing + size.width
                last.height = max(last.height, size.height)
                rows[rows.count - 1] = last
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// The Apple Intelligence entry point on cards, the issue editor and (later) the reader.
struct AskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.scoutGreen)
                .frame(width: 36, height: 36)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Ask Apple Intelligence")
        .accessibilityIdentifier("card.ask")
    }
}

/// "Site says:" from the writer's llms.txt, with what Scout found for the site.
struct SiteLine: View {
    let site: SiteContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                MonoLabel("Site says")
                Text("RSS ✓ · llms.txt ✓").font(.caption2.monospaced()).foregroundStyle(Color.scoutGreen)
            }
            if !site.summary.isEmpty {
                Text(verbatim: site.summary).font(.footnote).foregroundStyle(Color.inkSecondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("card.site")
    }
}
