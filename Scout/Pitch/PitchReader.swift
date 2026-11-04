//
//  PitchReader.swift
//  Scout
//

import Foundation
import PDFKit
import UIKit
import Vision

/// What code reads from a pitch before the model sees it: the text, a title line and any @handle.
struct PitchFacts: Sendable, Equatable {
    var text: String
    var title: String
    var handle: String?

    /// The first line of five characters or more is the title; the first `@handle` names the writer.
    init(text: String) {
        self.text = text
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        title = lines.first { $0.count >= 5 } ?? String(localized: "Untitled pitch")
        if let range = text.range(of: #"@[A-Za-z0-9_.-]{2,}"#, options: .regularExpression) {
            handle = String(text[range].dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }
}

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
                if let data = image.pngData() { images.append(data) }
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
}
