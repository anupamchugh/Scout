//
//  SiriCardStage.swift
//  Scout
//

#if DEBUG
import SwiftUI

/// `-siriCardStage`: renders the Siri card on a light platter, as SiriCardKit's preview stage does.
/// A rehearsal only; the real card must be judged through Siri on a device.
struct SiriCardStage: View {
    @Environment(ScoutModel.self) private var model
    @State private var snapshot: SiriDeckSnapshot?

    var body: some View {
        VStack(spacing: 14) {
            Text("Rehearsal render · not real Siri").font(.caption.monospaced()).foregroundStyle(.secondary)
            Text("\(snapshot?.total ?? 0) writers for \(snapshot?.lane ?? "…").")
                .font(.headline)
            if let snapshot {
                ScoutSiriCard(snapshot: snapshot, shortlisted: [])
                    .frame(width: 360)
            } else {
                ProgressView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.93))
        .task {
            await model.loadDeck()
            snapshot = SiriDeckSnapshot.make(lane: model.activeLaneName, deck: model.deck)
        }
    }
}
#endif
