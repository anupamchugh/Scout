//
//  ImageTaste.swift
//  ScoutKit
//
//  For visual packs, matching uses Vision feature prints instead of text embeddings:
//  an image scores by its distance to the nearest image you swiped right on.
//

import Foundation
import Vision

public enum ImageTaste {
    /// Liked prints kept per pack.
    public static let keep = 24

    /// A feature print for the image at `url`, serialised for storage; nil if it can't be downloaded or read.
    @concurrent
    public static func featurePrint(for url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let observation = try? await GenerateImageFeaturePrintRequest().perform(on: data)
        else { return nil }
        return try? JSONEncoder().encode(observation)
    }

    /// Similarity in 0...1 to the closest liked print; nil without liked prints.
    public static func similarity(_ print: Data, toLiked liked: [Data]) -> Double? {
        guard let candidate = try? JSONDecoder().decode(FeaturePrintObservation.self, from: print) else { return nil }
        let distances = liked.compactMap { data -> Double? in
            guard let other = try? JSONDecoder().decode(FeaturePrintObservation.self, from: data) else { return nil }
            return try? candidate.distance(to: other)
        }
        guard let nearest = distances.min() else { return nil }
        return similarity(distance: nearest)
    }

    /// Feature-print distances for photos fall roughly between 0 (same image) and 1.5 (unrelated).
    public static func similarity(distance: Double) -> Double {
        max(0, min(1, 1 - distance / 1.5))
    }

    /// Prints for many images, four downloads at a time; cancelled with the calling task.
    @concurrent
    public static func prints(for urls: [String: URL]) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            var queue = urls.makeIterator()
            for _ in 0..<4 {
                guard let (key, url) = queue.next() else { break }
                group.addTask { (key, await featurePrint(for: url)) }
            }
            var result: [String: Data] = [:]
            for await (key, data) in group {
                if let data { result[key] = data }
                if let (next, url) = queue.next() { group.addTask { (next, await featurePrint(for: url)) } }
            }
            return result
        }
    }
}
