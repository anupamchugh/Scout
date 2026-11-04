//
//  ScoutSiriCard.swift
//  Scout
//
//  Built to SiriCardKit's rendering rules: plain values only, no glass or materials (the Siri sheet
//  is already glass), fixed point sizes, one headline, at most four rows, actions last, accent once,
//  under about 340 points tall.
//

import AppIntents
import SwiftUI

struct ScoutSiriCard: View {
    let snapshot: SiriDeckSnapshot
    let shortlisted: Set<String>

    private let ink = Color(red: 0.08, green: 0.08, blue: 0.08)
    private let secondary = Color(red: 0.35, green: 0.34, blue: 0.31)
    private let accent = Color(red: 0.12, green: 0.42, blue: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCOUT · \(snapshot.lane.uppercased())")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(accent)
            Text(snapshot.rows.isEmpty ? "No new writers yet" : "\(snapshot.total) writers today")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ink)

            VStack(spacing: 8) {
                ForEach(snapshot.rows.prefix(4), id: \.authorKey) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name).font(.system(size: 15, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                        if shortlisted.contains(row.authorKey) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(ink)
                        }
                        Spacer()
                        Text("\(row.score)").font(.system(size: 16, design: .monospaced)).foregroundStyle(ink)
                        Text("MATCH").font(.system(size: 11, design: .monospaced)).foregroundStyle(secondary)
                    }
                }
            }

            if !snapshot.rows.isEmpty {
                HStack(spacing: 10) {
                    Button(intent: OpenDeckIntent()) { Text("Open deck").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .tint(ink)
                    Button(intent: ShortlistAllIntent()) { Text("Shortlist all").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .tint(ink)
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.97, green: 0.96, blue: 0.94), in: .rect(cornerRadius: 22))
    }
}
