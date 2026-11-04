//
//  LinkPreview.swift
//  Scout
//

import Foundation
import LinkPresentation
import ScoutKit
import UIKit

/// Title and image for an issue entry, fetched with LinkPresentation and cached on the entry.
@MainActor
enum LinkPreview {
    static func fetch(into entry: IssueEntry) async {
        guard entry.previewTitle == nil, let url = URL(string: entry.link) else { return }
        let provider = LPMetadataProvider()
        provider.timeout = 10
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }
        entry.previewTitle = metadata.title ?? entry.title
        if let image = await loadImage(metadata.imageProvider) {
            entry.previewImage = image.preparingThumbnail(of: CGSize(width: 240, height: 240))?.jpegData(compressionQuality: 0.7)
        }
    }

    private static func loadImage(_ provider: NSItemProvider?) async -> UIImage? {
        guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}
