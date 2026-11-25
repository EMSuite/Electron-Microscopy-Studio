//
//  ThumbnailProvider.swift
//  Role: the Finder thumbnail of a DigitalMicrograph (.dm3, .dm4), MRC, EMD or TIA .ser file (#903): one decimated frame read by
//        FormatoKit's `Peek` and drawn by EMSuiteUI's `QuickLookRendering` (images percentile-stretched, patterns in log scale).
//        A thin class: the reading is the kit's, the pixels are EMSuiteUI's, and Quick Look caches the thumbnail itself.
//  Budget: one frame, well under a second and 64 MB (FormatoKit's Peek tests measure it); the system ends a longer request.
//

import QuickLookThumbnailing
import FormatoPeek
import ShellQuickLook

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let side = Int((max(request.maximumSize.width, request.maximumSize.height) * request.scale).rounded(.up))
            let frame = try Peek.thumbnailFrame(url: request.fileURL, maxPixels: min(max(side, 64), 1024))
            let size = QuickLookRendering.fittedSize(for: frame, within: request.maximumSize)
            guard size.width >= 1, size.height >= 1 else { handler(nil, nil); return }
            handler(QLThumbnailReply(contextSize: size, drawing: { context in
                QuickLookRendering.draw(frame, in: context, size: size)
                return true
            }), nil)
        } catch {
            handler(nil, error)
        }
    }
}
