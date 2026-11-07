//
//  Navigator.swift
//  Scout
//

import Foundation
import Observation
import ScoutKit

enum ScoutTab: String, Hashable {
    case today, shortlist, compare, search
}

/// Lets App Intents that open the app pick a tab.
@MainActor
@Observable
final class Navigator {
    static let shared = Navigator()
    var tab: ScoutTab = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let tab = ScoutTab(rawValue: args[i + 1]) { return tab }
        #endif
        return .today
    }()

    /// A search Siri handed over (searchInApp): SearchView picks it up and clears it.
    var pendingSearch: String?
    /// Two publications Siri asked about: CompareView picks them up, runs and clears it.
    var pendingCompare: (first: PublicationChoice, second: PublicationChoice)?

    /// Where a Siri search lands: Compare for publication questions, Search for everything else.
    func open(_ route: SearchRoute) {
        switch route {
        case .compare(let first, let second):
            pendingCompare = (first, second)
            tab = .compare
        case .search(let term):
            pendingSearch = term
            tab = .search
        }
    }
}
