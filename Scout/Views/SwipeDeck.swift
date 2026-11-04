//
//  SwipeDeck.swift
//  Scout
//
//  The stacked layout and Reduce Motion handling are adapted from Deckloom
//  (github.com/anupamchugh/Deckloom, MIT). Deckloom swipes to browse; Scout swipes to decide,
//  so the gesture and fly-out here are new.
//

import ScoutKit
import SwiftUI

struct SwipeDeck<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let onDecide: (Item, Verdict) -> Void
    @ViewBuilder let card: (Item) -> Card

    @State private var drag: CGSize = .zero
    @State private var leaving: (id: Item.ID, verdict: Verdict)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { depth, item in
                    let isTop = depth == 0
                    card(item)
                        .scaleEffect(1 - CGFloat(depth) * 0.04)
                        .offset(y: CGFloat(depth) * 12)
                        .offset(isTop ? offset(for: item) : .zero)
                        .rotationEffect(.degrees(isTop ? rotation(for: item) : Double(depth) * 1.2))
                        .overlay(alignment: .top) { if isTop { stamp } }
                        .allowsHitTesting(isTop)
                        .gesture(isTop ? swipe(item) : nil)
                        .accessibilityHidden(!isTop)
                        .accessibilityActions {
                            if isTop {
                                Button("Shortlist") { decide(item, .shortlist) }
                                Button("Add to issue") { decide(item, .issue) }
                                Button("Pass") { decide(item, .pass) }
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let top = items.first {
                GlassEffectContainer(spacing: 24) {
                    HStack(spacing: 28) {
                        roundButton("xmark", label: "Pass", tint: .inkSecondary) { decide(top, .pass) }
                            .accessibilityIdentifier("deck.pass")
                        roundButton("tray.and.arrow.up", label: "Issue", tint: .scoutBlue, prominent: true) { decide(top, .issue) }
                            .accessibilityIdentifier("deck.issue")
                        roundButton("checkmark", label: "Shortlist", tint: .scoutGreen, prominent: true) { decide(top, .shortlist) }
                            .accessibilityIdentifier("deck.shortlist")
                    }
                }
            }
        }
    }

    private func offset(for item: Item) -> CGSize {
        guard let leaving, leaving.id == item.id else { return drag }
        switch leaving.verdict {
        case .shortlist: return CGSize(width: 700, height: drag.height)
        case .pass: return CGSize(width: -700, height: drag.height)
        case .issue: return CGSize(width: drag.width, height: -1000)
        }
    }

    private func rotation(for item: Item) -> Double {
        Double(offset(for: item).width / 22)
    }

    private func swipe(_ item: Item) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let t = value.predictedEndTranslation
                if t.height < -threshold * 1.4 && abs(t.width) < threshold { decide(item, .issue) }
                else if t.width > threshold { decide(item, .shortlist) }
                else if t.width < -threshold { decide(item, .pass) }
                else { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) { drag = .zero } }
            }
    }

    private func decide(_ item: Item, _ verdict: Verdict) {
        guard leaving == nil else { return }
        if reduceMotion {
            drag = .zero
            onDecide(item, verdict)
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { leaving = (item.id, verdict) }
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            leaving = nil
            drag = .zero
            onDecide(item, verdict)
        }
    }

    @ViewBuilder
    private var stamp: some View {
        let label: (String, Color)? = drag.width > 40 ? ("SHORTLIST", .scoutGreen)
            : drag.width < -40 ? ("PASS", .inkSecondary)
            : drag.height < -60 ? ("ISSUE", .scoutBlue) : nil
        if let label {
            Text(label.0)
                .font(.headline.monospaced())
                .foregroundStyle(label.1)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(label.1, lineWidth: 2))
                .padding(.top, 24)
                .rotationEffect(.degrees(drag.width > 0 ? -8 : 8))
                .offset(drag)
                .transition(.opacity)
        }
    }

    private func roundButton(_ symbol: String, label: String, tint: Color, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : tint)
                .frame(width: prominent ? 64 : 56, height: prominent ? 64 : 56)
        }
        .glassEffect(prominent ? .regular.tint(tint).interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}
