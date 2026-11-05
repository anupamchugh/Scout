//
//  ScoutMacApp.swift
//  Scout (macOS)
//
//  The desk version of Scout: lanes on the left, a ranked list in the middle, the writer or story on
//  the right. Same store, same ranking code and same on-device model as the iPhone app.
//

import CoreSpotlight
import ScoutKit
import SwiftData
import SwiftUI

@main
struct ScoutMacApp: App {
    @State private var model: ScoutModel

    init() {
        #if DEBUG
        // -demoData: fictional writers in an in-memory store, for screenshots without the network.
        let demo = ProcessInfo.processInfo.arguments.contains("-demoData")
        #else
        let demo = false
        #endif
        _model = State(initialValue: ScoutModel(container: demo ? ScoutStore.make(inMemory: true) : ScoutStore.container,
                                                usesDemoData: demo))
        CSUserQuery.prepare()
    }

    var body: some Scene {
        WindowGroup("Scout") {
            MacRootView()
                .environment(model)
                .modelContainer(model.container)
                .tint(.scoutGreen)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            SidebarCommands()
            ScoutCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
                .modelContainer(model.container)
                .tint(.scoutGreen)
                .frame(width: 560, height: 640)
        }
    }
}

/// What the focused window can do with the selected card; nil when nothing is selected.
struct DeckActions {
    let shortlist: () -> Void
    let pass: () -> Void
    let addToIssue: () -> Void
    let read: () -> Void
    let ask: () -> Void
}

extension FocusedValues {
    @Entry var deckActions: DeckActions?
    @Entry var macSection: Binding<MacSection?>?
}

/// The Card and Go menus. Shortcuts live here only, so toolbar buttons don't claim the same keys.
struct ScoutCommands: Commands {
    @FocusedValue(\.deckActions) private var actions
    @FocusedValue(\.macSection) private var section

    var body: some Commands {
        CommandMenu("Card") {
            Button("Shortlist", systemImage: "checkmark.circle") { actions?.shortlist() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(actions == nil)
            Button("Add to Issue", systemImage: "newspaper") { actions?.addToIssue() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(actions == nil)
            Button("Pass", systemImage: "xmark.circle") { actions?.pass() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions == nil)
            Divider()
            Button("Read Article", systemImage: "book") { actions?.read() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Ask Apple Intelligence", systemImage: "sparkles") { actions?.ask() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }

        CommandMenu("Go") {
            Button("Today") { section?.wrappedValue = .lane(ScoutModel.allLanes) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Shortlist") { section?.wrappedValue = .shortlist }
                .keyboardShortcut("2", modifiers: .command)
            Button("Issue") { section?.wrappedValue = .issue }
                .keyboardShortcut("3", modifiers: .command)
            Button("Search") { section?.wrappedValue = .search }
                .keyboardShortcut("4", modifiers: .command)
        }
    }
}
