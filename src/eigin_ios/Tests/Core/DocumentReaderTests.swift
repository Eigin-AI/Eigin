import CoreText
@testable import Eigin
import Foundation
import PDFKit
import Testing

@Suite("Document reader", .serialized)
struct DocumentReaderTests {
    @Test func textContinuationPreservesEveryCharacter() async throws {
        let reader = DocumentReader()
        let text = String(repeating: "Invoice æøå €123.45\n", count: 150)
        let data = Data(text.utf8)
        var selection = DocumentSelection(outputLimit: 2000)
        let first = try await reader.read(data: data, mimeType: "text/plain", selection: selection)
        #expect(first.status == .partial)
        #expect(first.content.count == 2000)
        selection.contentOffset = try #require(first.nextContentOffset)
        let second = try await reader.read(data: data, mimeType: "text/plain", selection: selection)
        #expect(first.content + second.content == text)
        #expect(second.status == .complete)
    }

    @Test func decodesDeclaredCharsetAndRejectsBinary() async throws {
        let reader = DocumentReader()
        let result = try await reader.read(
            data: Data([0xE6, 0xF8, 0xE5]),
            mimeType: "text/plain; charset=iso-8859-1",
            selection: .init()
        )
        #expect(result.content == "æøå")
        await #expect(throws: DocumentReadError.self) {
            try await reader.read(data: Data([0, 1, 2]), mimeType: "text/plain", selection: .init())
        }
    }

    @Test func unsupportedAndInvalidDocumentsAreExplicit() async throws {
        let reader = DocumentReader()
        let unsupported = try await reader.read(
            data: Data(),
            mimeType: "image/png",
            selection: .init()
        )
        #expect(unsupported.status == .unsupported)
        await #expect(throws: DocumentReadError.self) {
            try await reader.read(
                data: Data("Not a PDF".utf8),
                mimeType: "application/pdf",
                selection: .init()
            )
        }
        await #expect(throws: DocumentReadError.self) {
            try await reader.read(
                data: Data("hello".utf8),
                mimeType: "text/plain",
                selection: .init(contentOffset: 6)
            )
        }
    }

    @Test func extractsPDFPagesAndProvidesContinuation() async throws {
        let data = try Self.pdf(pages: ["Invoice 123 - Total EUR 120.00", "Payment due 2026-12-01"])
        let reader = DocumentReader()
        let first = try await reader.read(
            data: data,
            mimeType: "application/pdf",
            selection: .init(pageCount: 1)
        )
        #expect(first.content.contains("Invoice 123"))
        #expect(first.content.contains("## Page 1"))
        #expect(first.methods["1"] == .embeddedText)
        #expect(first.nextPage == 2)
        let second = try await reader.read(
            data: data,
            mimeType: "application/pdf",
            selection: .init(startPage: 2)
        )
        #expect(second.content.contains("2026-12-01"))
        #expect(second.status == .complete)
    }

    @Test func expiredBudgetAndCancellationPreventParsing() async throws {
        let reader = DocumentReader()
        await #expect(throws: DocumentReadError.self) {
            try await reader.read(
                data: Data("invoice".utf8),
                mimeType: "text/plain",
                selection: .init(deadline: .distantPast)
            )
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.read(
                data: Data("invoice".utf8),
                mimeType: "text/plain",
                selection: .init()
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func utf8BOMOverridesConflictingCharset() async throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("æøå".utf8)
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "text/plain; charset=iso-8859-1",
            selection: .init()
        )
        #expect(result.content == "æøå")
    }

    @Test func terminalPDFOffsetIsComplete() async throws {
        let data = try Self.pdf(pages: ["Invoice 123"])
        let document = try #require(PDFDocument(data: data))
        let count = try #require(document.page(at: 0)?.string).count
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "application/pdf",
            selection: .init(contentOffset: count)
        )
        #expect(result.status == .complete)
        #expect(result.content.isEmpty)
    }

    @Test func encryptedPDFHasAnExplicitFailure() async throws {
        let data = try Self.pdf(pages: ["Private invoice"])
        let document = try #require(PDFDocument(data: data))
        let encrypted = try #require(document.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "secret",
            PDFDocumentWriteOption.ownerPasswordOption: "owner",
        ]))
        await #expect(throws: DocumentReadError.self) {
            try await DocumentReader().read(
                data: encrypted,
                mimeType: "application/pdf",
                selection: .init()
            )
        }
    }

    @Test(arguments: ["0020", "200B", "2060", "FEFF", "0000", "2800"])
    func visuallyBlankEmbeddedTextUsesPageImage(unicode: String) async throws {
        let data = DocumentReaderFixtures.mappedTextPDF(unicode: unicode)
        let document = try #require(PDFDocument(data: data))
        let extracted = try #require(document.page(at: 0)?.string)
        #expect(!extracted.contains("Invoice"))
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "application/pdf",
            selection: .init()
        )
        #expect(try [DocumentExtractionMethod.structuredOCR, .basicOCR]
            .contains(#require(result.methods["1"])))
        #expect(result.content.contains("123"))
        #expect(result.status == .complete)
    }

    @Test func mixedPagesChooseTextRecognitionIndependently() async throws {
        let data = DocumentReaderFixtures.mappedTextPDF(unicode: "2060", leadingReadablePage: true)
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "application/pdf",
            selection: .init()
        )
        #expect(result.methods["1"] == .embeddedText)
        #expect(try [DocumentExtractionMethod.structuredOCR, .basicOCR]
            .contains(#require(result.methods["2"])))
        #expect(result.content.contains("456"))
        #expect(result.content.contains("123"))
        #expect(result.warnings.count(where: { $0.contains("Confirm uncertain content") }) == 1)
    }

    @Test(arguments: [
        (String.Encoding.utf16LittleEndian, [0xFF, 0xFE] as [UInt8]),
        (.utf16BigEndian, [0xFE, 0xFF]),
        (.utf32LittleEndian, [0xFF, 0xFE, 0, 0]),
        (.utf32BigEndian, [0, 0, 0xFE, 0xFF]),
    ])
    func unicodeBOMOverridesDeclaredCharset(encoding: String.Encoding, bom: [UInt8]) async throws {
        let text = "Résumé: 120 €"
        let data = try Data(bom) + #require(text.data(using: encoding))
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "text/plain; charset=iso-8859-1",
            selection: .init()
        )
        #expect(result.content == text)
        #expect(result.status == .complete)
    }

    @Test func readableEmbeddedTextKeepsItsUnicodeFormatting() async throws {
        let data = DocumentReaderFixtures.mappedTextPDF(unicode: "004120600042")
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "application/pdf",
            selection: .init()
        )
        #expect(result.methods["1"] == .embeddedText)
        #expect(result.content.contains("A\u{2060}B"))
        #expect(result.jsonObject["status"] as? String == "complete")
        #expect(result
            .jsonObject["extraction_methods"] as? [String: String] == ["1": "embedded_text"])
        #expect(!result.warnings.contains { $0.contains("Confirm uncertain content") })
    }

    @Test func trulyBlankPDFDoesNotReturnEmptyPageHeadings() async throws {
        let data = try Self.pdf(pages: [" \n \t "])
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "application/pdf",
            selection: .init()
        )
        #expect(result.status == .unreadable)
        #expect(result.content.isEmpty)
        #expect(result.warnings.contains { $0.contains("No readable text") })
    }

    @Test(arguments: [1, 3])
    func scannedPDFUsesOneImageRecognitionWarning(pageCount: Int) async throws {
        let data = try Self.pdf(
            pages: Array(repeating: "Invoice 123 Total EUR 120.00", count: pageCount),
            scanned: true
        )
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "application/pdf",
            selection: .init()
        )
        #expect(try [DocumentExtractionMethod.structuredOCR, .basicOCR]
            .contains(#require(result.methods["1"])))
        #expect(result.content.contains("123"))
        #expect(result.methods.count == pageCount)
        #expect(result.status == .complete)
        #expect(result.warnings.count(where: { $0.contains("Confirm uncertain content") }) == 1)
        #expect(result.warnings
            .contains { $0.hasPrefix("Some pages were read using image recognition") })
        #expect(!result.warnings.contains { $0.contains("OCR") })
    }

    @Test func scannedInvoiceTablePreservesRowsWhenStructuredOCRIsAvailable() async throws {
        let data = try Self.pdf(pages: [""], scanned: true, table: true)
        let result = try await DocumentReader().read(
            data: data,
            mimeType: "application/pdf",
            selection: .init()
        )
        #expect(result.content.contains("225.00"))
        if result.methods["1"] == .structuredOCR {
            #expect(result.content.contains("| Consulting | 2 | 100.00 | 200.00 |"))
        } else {
            #expect(result.warnings.contains { $0.contains("Image recognition was used") })
        }
    }

    /// Creates synthetic documents without retaining real financial data in test fixtures.
    private static func pdf(
        pages: [String],
        scanned: Bool = false,
        table: Bool = false
    ) throws -> Data {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for text in pages {
            context.beginPDFPage(nil)
            if scanned {
                let raster = try #require(CGContext(
                    data: nil,
                    width: 1224,
                    height: 1584,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ))
                raster.setFillColor(CGColor(gray: 1, alpha: 1))
                raster.fill(CGRect(x: 0, y: 0, width: 1224, height: 1584))
                raster.scaleBy(x: 2, y: 2)
                if table { drawTable(in: raster) } else { draw(text, in: raster) }
                try context.draw(#require(raster.makeImage()), in: bounds)
            } else {
                draw(text, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func drawTable(in context: CGContext) {
        let rows = [
            ["Description", "Quantity", "Unit price", "Amount"],
            ["Consulting", "2", "100.00", "200.00"],
            ["Hosting", "1", "25.00", "25.00"],
            ["Total EUR", "", "", "225.00"],
        ]
        let xs: [CGFloat] = [30, 210, 340, 460]
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica" as CFString,
                18,
                nil
            ),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                gray: 0,
                alpha: 1
            ),
        ]
        for (r, row) in rows.enumerated() {
            for (c, text) in row.enumerated() {
                context.textPosition = CGPoint(x: xs[c], y: 700 - CGFloat(r) * 60)
                CTLineDraw(
                    CTLineCreateWithAttributedString(NSAttributedString(
                        string: text,
                        attributes: attributes
                    )),
                    context
                )
            }
        }
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(1)
        for y in stride(from: CGFloat(500), through: CGFloat(740), by: 60) {
            context.move(to: CGPoint(x: 20, y: y)); context
                .addLine(to: CGPoint(x: 600, y: y)); context.strokePath()
        }
        for x: CGFloat in [20, 200, 330, 450, 600] {
            context.move(to: CGPoint(x: x, y: 500)); context
                .addLine(to: CGPoint(x: x, y: 740)); context.strokePath()
        }
    }

    private static func draw(_ text: String, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                gray: 0,
                alpha: 1
            ),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: attributes
        ))
        context.textPosition = CGPoint(x: 30, y: 700)
        CTLineDraw(line, context)
    }
}
