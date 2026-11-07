//
//  Navigator.swift
//  Scout
//

import Foundation
import Observation

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
}
