import Foundation
import Markdown
import SwiftUI

extension Markdown.Table: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        var bodyContainer = attributeContainer
        var headerContainer = attributeContainer
        bodyContainer[.font] = config.paragraphStyle.textFonts.normal
        bodyContainer[.typography] = config.paragraphStyle.textFonts
        headerContainer[.font] = config.paragraphStyle.textFonts.bold ?? config.paragraphStyle
            .textFonts.normal
        headerContainer[.typography] = config.paragraphStyle.textFonts
        let headerCells = head
            .children
            .compactMap { $0 as? Cell }
            .map { $0.convert(attributeContainer: headerContainer, config: config) }
        let rows = body
            .children
            .compactMap { $0 as? Row }
            // It may never happen but we filter out rows with wrong # of columns
            .filter { $0.childCount == headerCells.count }
            .map { row in
                let cells = row.children.compactMap { $0 as? Cell }
                return cells.map { $0.convert(attributeContainer: bodyContainer, config: config) }
            }
        // swift-markdown's MarkupFormatter.visitTable crashes with an array index
        // out of bounds when any body row has fewer columns than the header
        // (https://github.com/swiftlang/swift-markdown/issues/238).
        // Guard against this by only calling format() when the table is well-formed.
        let headerColumnCount = head.childCount
        let isWellFormed = body.children.allSatisfy { $0.childCount == headerColumnCount }
        let rawMarkdown = isWellFormed ? format() : ""
        return .table(id: id, headers: headerCells, rows: rows, rawMarkdown: rawMarkdown)
    }
}
