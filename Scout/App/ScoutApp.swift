//
//  ScoutApp.swift
//  Scout
//

import CoreSpotlight
import ScoutKit
import SwiftData
import SwiftUI

@main
struct ScoutApp: App {
    @State private var model: ScoutModel

    init() {
        #if DEBUG
        // -demoData: fictional writers in an in-memory store, for UI tests without the network.
        let demo = ProcessInfo.processInfo.arguments.contains("-demoData")
        #else
        let demo = false
        #endif
        _model = State(initialValue: ScoutModel(container: demo ? ScoutStore.make(inMemory: true) : ScoutStore.container,
                                                usesDemoData: demo))
        CSUserQuery.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environment(model)
                .modelContainer(model.container)
                .tint(.scoutGreen)
        }
    }
}

struct RootTabs: View {
    @State private var navigator = Navigator.shared

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-siriCardStage") {
            SiriCardStage()
        } else {
            tabs.task { await Self.runIntentFromArguments() }
        }
        #else
        tabs
        #endif
    }

    #if DEBUG
    /// -runIntent publications | slop:<publication key>: runs what the Siri intent runs and prints what Siri would say.
    private static func runIntentFromArguments() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-runIntent"), i + 1 < args.count else { return }
        let request = args[i + 1]
        let text: String
        if request == "publications" {
            text = await CheckPublicationsIntent.briefing()
        } else if request == "digest" {
            // Every preset publication read on this device, one after another, as the Markdown digest.
            var sides: [PublicationSide] = []
            for choice in PublicationChoice.presets {
                if let side = try? await PublicationComparison.side(choice) { sides.append(side) }
                print("SIRI-DIALOG[digest]: read \(choice.name)")
            }
            text = PublicationDigest.markdown(sides, generated: .now, where: "in the Scout app on an iOS simulator")
        } else if request.hasPrefix("slop:"), let publication = ProgrammingPublication(rawValue: String(request.dropFirst(5))) {
            text = (try? await CheckPublicationSlopIntent.report(publication)) ?? "failed"
        } else {
            text = "unknown request \(request)"
        }
        print("SIRI-DIALOG[\(request)]: \(text)")
        let file = URL.documentsDirectory.appending(path: "siri-dialog-\(request.replacingOccurrences(of: ":", with: "-")).txt")
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }
    #endif

    private var tabs: some View {
        TabView(selection: $navigator.tab) {
            Tab("Today", systemImage: "rectangle.stack", value: ScoutTab.today) { TodayView() }
            Tab("Shortlist", systemImage: "checkmark.circle", value: ScoutTab.shortlist) { ShortlistView() }
                .accessibilityIdentifier("tab.shortlist")
            Tab("Compare", systemImage: "chart.bar.xaxis", value: ScoutTab.compare) { CompareView() }
                .accessibilityIdentifier("tab.compare")
            Tab("Search", systemImage: "magnifyingglass", value: ScoutTab.search, role: .search) { SearchView() }
        }
    }
}
