import Foundation
import PDFKit

/// Serializes extraction off the main actor and keeps PDF/image objects local to one operation.
actor DocumentReader: DocumentReading {
    private static let pdfHeaderSearchBytes = 1024
    private var extracting = false
    func read(
        data: Data,
        mimeType: String,
        selection: DocumentSelection
    ) async throws -> DocumentReadResult {
        try await acquireReader(until: selection.deadline)
        defer { extracting = false }
        try validate(data, selection: selection)
        let type = mimeType.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
            .lowercased()
        switch type {
        case "application/pdf":
            return try await readPDF(data, selection: selection)
        case "text/plain":
            return try readPlainText(data, mimeType: mimeType, selection: selection)
        default:
            return DocumentReadResult(
                status: .unsupported,
                warnings: ["Only PDF and plain-text attachments can currently be read."]
            )
        }
    }

    private func acquireReader(until deadline: Date) async throws {
        while extracting {
            try Task.checkCancellation()
            guard deadline.timeIntervalSinceNow > DocumentLimits.minimumRemainingSeconds else {
                throw DocumentReadError
                    .unreadable(
                        "Document reader is busy. Retry this attachment in a separate call."
                    )
            }
            try await Task.sleep(for: DocumentLimits.readerPollInterval)
        }
        extracting = true
    }

    private func validate(_ data: Data, selection: DocumentSelection) throws {
        try Task.checkCancellation()
        guard selection.startPage >= 1,
              (1 ... DocumentLimits.maximumPages).contains(selection.pageCount),
              selection.contentOffset >= 0,
              selection.outputLimit >= DocumentLimits.minimumOutputCharacters
        else {
            throw DocumentReadError.invalidSelection
        }
        guard data.count <= DocumentLimits.maximumInputBytes else {
            throw DocumentReadError.unreadable("Document exceeds the 10 MiB reading limit.")
        }
        guard selection.deadline.timeIntervalSinceNow > DocumentLimits.minimumRemainingSeconds
        else {
            throw DocumentReadError
                .unreadable("Insufficient time remains to parse this document. Try fewer pages.")
        }
    }

    private func readPlainText(
        _ data: Data,
        mimeType: String,
        selection: DocumentSelection
    ) throws -> DocumentReadResult {
        guard !selection.ocr,
              selection.startPage == 1 else { throw DocumentReadError.invalidSelection }
        let text = try DocumentText.decode(data, mimeType: mimeType)
        var result = DocumentReadResult()
        result.methods["text"] = .text
        try append(
            text,
            page: nil,
            offset: selection.contentOffset,
            selection: selection,
            result: &result
        )
        return result
    }

    private func readPDF(
        _ data: Data,
        selection: DocumentSelection
    ) async throws -> DocumentReadResult {
        let deadline = min(
            selection.deadline,
            Date().addingTimeInterval(DocumentLimits.pdfProcessingSeconds)
        )
        let document = try openPDF(data, startPage: selection.startPage)
        var hasReadableSource = false
        var usedImageRecognition = false
        var result = DocumentReadResult(pageCount: document.pageCount)
        let end = min(document.pageCount, selection.startPage + selection.pageCount - 1)
        for number in selection.startPage ... end {
            try Task.checkCancellation()
            guard deadline.timeIntervalSinceNow > DocumentLimits.minimumRemainingSeconds else {
                result.status = .partial
                result.nextPage = number
                result.nextContentOffset = 0
                result.warnings
                    .append(
                        "Parsing budget exhausted. Fetch the remaining pages in a separate call."
                    )
                break
            }
            guard let page = document.page(at: number - 1) else {
                result.warnings.append("Page \(number) could not be opened.")
                result.status = .partial
                continue
            }
            let pageContent: DocumentPageContent
            do {
                pageContent = try await readPage(page, selection: selection, deadline: deadline)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result.status = .partial
                result.warnings.append(
                    "Page \(number) needs image recognition, which failed or is unavailable on this device. Its content was not read."
                )
                continue
            }
            let text = pageContent.text
            let method = pageContent.method
            if method != .embeddedText { usedImageRecognition = true }
            if let warning = pageContent.warning {
                result.warnings.append("Page \(number): " + warning)
            }
            try Task.checkCancellation()
            result.methods[String(number)] = method
            guard DocumentText.hasReadableContent(text) else {
                result.warnings
                    .append(
                        "No readable text was found on page \(number). Images and diagrams are not interpreted."
                    )
                result.status = .partial
                continue
            }
            hasReadableSource = true
            try append(
                text,
                page: number,
                offset: number == selection.startPage ? selection.contentOffset : 0,
                selection: selection,
                result: &result
            )
            if result.nextContentOffset != nil { break }
        }
        if result.nextPage == nil, end < document.pageCount {
            result.status = .partial
            result.nextPage = end + 1
            result.nextContentOffset = 0
        }
        if usedImageRecognition {
            result.warnings.append(
                "Some pages were read using image recognition and may contain misread text or layout errors. Confirm uncertain content with the user before taking action."
            )
        }
        if result.methods.values.contains(.embeddedText) {
            result.warnings
                .append(
                    "PDF text order may not preserve table columns. Image-only regions on text pages may be omitted; retry image recognition if needed."
                )
        }
        if !hasReadableSource {
            result.status = .unreadable
        }
        return result
    }

    private func openPDF(_ data: Data, startPage: Int) throws -> PDFDocument {
        guard data.prefix(Self.pdfHeaderSearchBytes).range(of: Data("%PDF-".utf8)) != nil,
              let document = PDFDocument(data: data)
        else {
            throw DocumentReadError.unreadable("The attachment is not a valid PDF.")
        }
        guard !document.isLocked else {
            throw DocumentReadError.unreadable("This PDF is password-protected and cannot be read.")
        }
        guard document.pageCount > 0, startPage <= document.pageCount else {
            throw DocumentReadError.invalidSelection
        }
        return document
    }

    private func readPage(
        _ page: PDFPage,
        selection: DocumentSelection,
        deadline: Date
    ) async throws -> DocumentPageContent {
        if !selection.ocr, let text = page.string, DocumentText.hasReadableContent(text) {
            return DocumentPageContent(text: text, method: .embeddedText)
        }
        let image = try DocumentOCR.render(page, deadline: deadline)
        return try await DocumentOCR.recognize(image, deadline: deadline)
    }

    private func append(
        _ text: String,
        page: Int?,
        offset: Int,
        selection: DocumentSelection,
        result: inout DocumentReadResult
    ) throws {
        guard offset <= text.count else { throw DocumentReadError.invalidSelection }
        let heading = page.map { "\n\n## Page \($0)\n\n" } ?? ""
        let available = max(0, selection.outputLimit - result.content.count - heading.count)
        let remainder = text.dropFirst(offset)
        let chunk = remainder.prefix(available)
        if !chunk.isEmpty { result.content += heading + chunk }
        if chunk.count < remainder.count {
            result.status = .partial
            result.nextPage = page
            result.nextContentOffset = offset + chunk.count
            result.warnings
                .append(
                    "Content truncated to \(selection.outputLimit) characters. Continue using the returned page and next_content_offset with the same extraction mode."
                )
        }
    }
}
