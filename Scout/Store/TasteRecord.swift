//
//  TasteRecord.swift
//  Scout
//

import Foundation
import ScoutKit
import SwiftData

/// Taste for one role pack, persisted.
@Model
final class TasteRecord {
    @Attribute(.unique) var packID: String
    var data: Data
    /// Vision feature prints of liked images (visual packs), newest last, capped.
    var likedPrints: [Data] = []

    init(packID: String, taste: Taste = Taste()) {
        self.packID = packID
        self.data = (try? JSONEncoder().encode(taste)) ?? Data()
    }

    var taste: Taste {
        get { (try? JSONDecoder().decode(Taste.self, from: data)) ?? Taste() }
        set { data = (try? JSONEncoder().encode(newValue)) ?? data }
    }
}
