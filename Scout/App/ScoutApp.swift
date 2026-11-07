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
            tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $navigator.tab) {
            Tab("Today", systemImage: "rectangle.stack", value: ScoutTab.today) { TodayView() }
            Tab("Shortlist", systemImage: "checkmark.circle", value: ScoutTab.shortlist) { ShortlistView() }
            Tab("Compare", systemImage: "chart.bar.xaxis", value: ScoutTab.compare) { CompareView() }
                .accessibilityIdentifier("tab.shortlist")
            Tab("Search", systemImage: "magnifyingglass", value: ScoutTab.search, role: .search) { SearchView() }
        }
    }
}
