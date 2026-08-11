import Markdown

protocol MarkupPostParsingRewriter {
    func rewriteIfApplicable(document: Document) -> Document?
}

final class PartialStrongMarkupPostParsingRewriter: MarkupPostParsingRewriter {
    private let scanner: PartialEmphasisScanner

    init() {
        scanner = PartialEmphasisScanner()
    }

    func rewriteIfApplicable(document: Document) -> Document? {
        guard let targetNode = scanner.scan(document: document) else {
            return nil
        }

        var rewriter = PartialEmphasisRewriter(targetNode: targetNode)
        return rewriter.visit(document) as? Document
    }
}

final class PartialTableMarkupPostParsingRewriter: MarkupPostParsingRewriter {
    private let scanner: PartialTableScanner

    init() {
        scanner = PartialTableScanner()
    }

    func rewriteIfApplicable(document: Document) -> Document? {
        guard let targetNode = scanner.scan(document: document) else {
            return nil
        }

        var rewriter = PartialTableRewriter(targetParagraph: targetNode)
        return rewriter.visit(document) as? Document
    }
}
