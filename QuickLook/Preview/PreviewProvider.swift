//
//  PreviewProvider.swift
//  Role: the spacebar preview of a DigitalMicrograph (.dm3, .dm4), MRC, EMD or TIA .ser file (#903): EMSuiteUI's `QuickLookCard`
//        (the image with its scale bar on the left, what the file's headers say on the right), rendered to PNG data and returned as
//        a data-based preview (`QLIsDataBasedPreview`): no view controller, no AppKit. The reading is FormatoKit's `Peek`: the header
//        facts and one decimated frame; a file whose frame does not read still gets its card.
//

import QuickLookUI
import UniformTypeIdentifiers
import FormatoPeek
import ShellQuickLook

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let summary = try Peek.summary(url: url)
        let frame = try? Peek.thumbnailFrame(url: url, maxPixels: 720)
        guard let png = await QuickLookCard.pngData(summary: summary, frame: frame, fileName: url.lastPathComponent) else {
            throw CocoaError(.fileReadUnknown)
        }
        return QLPreviewReply(dataOfContentType: .png, contentSize: QuickLookCard.contentSize) { _ in png }
    }
}
