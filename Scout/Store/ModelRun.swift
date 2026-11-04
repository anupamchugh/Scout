//
//  ModelRun.swift
//  Scout
//

import Foundation
import SwiftData

/// One model answer and how the person rated it. Stays on the device; used for prompt evaluation.
@Model
final class ModelRun {
    var date: Date
    /// What the model was doing: "ask", "why", "outreach"…
    var role: String
    var pack: String
    var instructionsVersion: String
    /// What the model was asked, and about which writer or story.
    var input: String
    var subjectID: String
    var output: String
    /// Why code refused to show the output, if it did.
    var rejection: String?
    var latency: Double
    /// 1 thumbs up, -1 thumbs down, 0 unrated.
    var rating: Int = 0
    var reasons: [String] = []
    var desired: String = ""

    init(role: String, pack: String, instructionsVersion: String, input: String, subjectID: String, output: String,
         rejection: String?, latency: Double, date: Date = .now) {
        self.date = date
        self.role = role
        self.pack = pack
        self.instructionsVersion = instructionsVersion
        self.input = input
        self.subjectID = subjectID
        self.output = output
        self.rejection = rejection
        self.latency = latency
    }
}
