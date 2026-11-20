import Foundation

/// Synthetic PDF text mappings that reproduce visually blank extraction from readable pages.
enum DocumentReaderFixtures {
    static func mappedTextPDF(unicode: String, leadingReadablePage: Bool = false) -> Data {
        let mappings = (32 ... 126).map { String(format: "<%02X> <%@>", $0, unicode) }
            .joined(separator: "\n")
        let cmap = """
        /CIDInit /ProcSet findresource begin
        12 dict begin
        begincmap
        /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
        /CMapName /FixtureTextMap def
        /CMapType 2 def
        1 begincodespacerange
        <00> <FF>
        endcodespacerange
        95 beginbfchar
        \(mappings)
        endbfchar
        endcmap
        CMapName currentdict /CMap defineresource pop
        end
        end
        """
        let content = "BT /F1 22 Tf 30 700 Td (Invoice 123 Total EUR 120.00) Tj ET"
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Length \(cmap.utf8.count) >>\nstream\n\(cmap)\nendstream",
        ]
        if leadingReadablePage {
            objects[1] = "<< /Type /Pages /Kids [7 0 R 3 0 R] /Count 2 >>"
            let readable = "BT /F1 22 Tf 30 700 Td (Embedded invoice 456) Tj ET"
            objects += [
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 8 0 R >> >> /Contents 9 0 R >>",
                "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
                "<< /Length \(readable.utf8.count) >>\nstream\n\(readable)\nendstream",
            ]
        }
        var pdf = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        pdf += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}
