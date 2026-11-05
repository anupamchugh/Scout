//
//  LinkPreview.swift
//  Scout
//

import Foundation
import LinkPresentation
import ScoutKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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
            entry.previewImage = thumbnailJPEG(image)
        }
    }

    private static func loadImage(_ provider: NSItemProvider?) async -> PlatformImage? {
        guard let provider, provider.canLoadObject(ofClass: PlatformImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: PlatformImage.self) { object, _ in
                continuation.resume(returning: object as? PlatformImage)
            }
        }
    }

    private static func thumbnailJPEG(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        return image.preparingThumbnail(of: CGSize(width: 240, height: 240))?.jpegData(compressionQuality: 0.7)
        #else
        let side: CGFloat = 240
        let scale = min(1, side / max(image.size.width, image.size.height, 1))
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        #endif
    }
}
