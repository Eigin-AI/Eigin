import Foundation
import PDFKit
import Vision

/// Reads text from a bounded raster of a PDF page using on-device OCR.
enum DocumentOCR {
    private static let maximumRasterDimension: CGFloat = 2500
    private static let maximumRasterScale: CGFloat = 3

    static func render(_ page: PDFPage, deadline: Date) throws -> CGImage {
        guard deadline.timeIntervalSinceNow > DocumentLimits.minimumRemainingSeconds
        else {
            throw DocumentReadError
                .unreadable("Insufficient time remains for image recognition.")
        }
        try Task.checkCancellation()
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0,
              bounds.height > 0
        else {
            throw DocumentReadError.unreadable("PDF page has invalid dimensions.")
        }
        let scale = min(
            maximumRasterScale,
            maximumRasterDimension / max(bounds.width, bounds.height)
        )
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw DocumentReadError
                .unreadable("Could not render this PDF page for image recognition.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else {
            throw DocumentReadError
                .unreadable("Could not render this PDF page for image recognition.")
        }
        return image
    }

    static func recognize(_ image: CGImage, deadline: Date) async throws -> DocumentPageContent {
        try checkBudget(deadline)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                var request = RecognizeDocumentsRequest()
                request.textRecognitionOptions.automaticallyDetectLanguage = true
                let observations = try await request.perform(on: image)
                try Task.checkCancellation()
                let text = observations.map { markdown($0.document) }.joined(separator: "\n\n")
                if DocumentText.hasReadableContent(text) {
                    return DocumentPageContent(text: text, method: .structuredOCR)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try checkBudget(deadline)
            }
        }
        try checkBudget(deadline)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        return DocumentPageContent(
            text: (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n"),
            method: .basicOCR,
            warning: "Document layout recognition was unavailable or returned no text. Image recognition was used; table columns may not be preserved."
        )
    }

    private static func checkBudget(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard deadline.timeIntervalSinceNow > DocumentLimits.minimumRemainingSeconds else {
            throw DocumentReadError
                .unreadable("Insufficient time remains for image recognition.")
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func markdown(_ document: DocumentObservation.Container) -> String {
        DocumentMarkdown.render(
            transcript: document.text.transcript,
            tables: document.tables.map { table in
                table.rows.map { row in row.map { $0.content.text.transcript } }
            }
        )
    }
}
