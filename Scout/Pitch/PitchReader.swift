//
//  PitchReader.swift
//  Scout
//

import Foundation
import PDFKit
import ScoutKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Vision

enum PitchReader {
    enum Failure: Error { case unreadable, noText }

    /// Reads text from a PDF or image file with Vision's document recognition.
    @concurrent
    static func read(_ url: URL) async throws -> PitchFacts {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var images: [Data] = []
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
            for index in 0..<min(document.pageCount, 3) {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
                if let data = pngData(image) { images.append(data) }
            }
        } else {
            images.append(try Data(contentsOf: url))
        }

        var pages: [String] = []
        for data in images {
            let observations = try await RecognizeDocumentsRequest().perform(on: data)
            pages += observations.map(\.document.text.transcript)
        }
        let text = pages.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.noText }
        return PitchFacts(text: text)
    }

    private static func pngData(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        return image.pngData()
        #else
        return image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
        #endif
    }
}
